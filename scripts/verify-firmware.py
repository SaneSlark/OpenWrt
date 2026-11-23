#!/usr/bin/env python3
"""Reject missing images, damaged gzip files, or incomplete target manifests."""
import json
from pathlib import Path
import re
import subprocess
import sys
from uuid import UUID
import zlib


EFI_SYSTEM_PARTITION = UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
CORE_PACKAGES = ("xray-core", "sing-box", "hysteria", "tuic-client", "naiveproxy")
PACKAGE_VERSION = re.compile(r"(\d+(?:\.\d+)+)(?:-r?(\d+))?")


def verify_bios_boot_sector(path, header):
    if header[510:512] != b"\x55\xaa":
        raise SystemExit(f"{path.name}: BIOS MBR signature missing")
    if not any(header[:440]):
        raise SystemExit(f"{path.name}: BIOS boot code missing from MBR")
    if header[446] != 0x80:
        raise SystemExit(f"{path.name}: first BIOS partition is not active")


def verify_efi_partition_type(path, header):
    sector_size = 512
    if header[sector_size:sector_size + 8] != b"EFI PART":
        raise SystemExit(f"{path.name}: GPT header missing from UEFI image")
    entries_lba = int.from_bytes(header[sector_size + 72:sector_size + 80], "little")
    first_entry = entries_lba * sector_size
    if entries_lba < 2 or header[first_entry:first_entry + 16] != EFI_SYSTEM_PARTITION:
        raise SystemExit(f"{path.name}: first GPT partition is not an EFI System Partition")


def verify_image(path, fwtool):
    # OpenWrt may append fwtool metadata/signatures after the gzip member.
    # zlib checks the gzip CRC/length while allowing us to inspect that suffix.
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
    size = 0
    trailing = False
    header = bytearray()
    efi = path.name.endswith("-efi.img.gz")
    header_limit = 64 * 1024 if efi else 512
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                if decoder.eof:
                    trailing = True
                    break
                pending = chunk
                while pending and not decoder.eof:
                    decoded = decoder.decompress(pending, 1024 * 1024)
                    size += len(decoded)
                    if len(header) < header_limit:
                        header.extend(decoded[:header_limit - len(header)])
                    pending = decoder.unconsumed_tail
                if decoder.unused_data:
                    trailing = True
                    break
    except zlib.error as error:
        raise SystemExit(f"{path.name}: invalid gzip data: {error}") from error
    if not decoder.eof:
        raise SystemExit(f"{path.name}: truncated gzip stream")
    if size < 16 * 1024 * 1024:
        raise SystemExit(f"Firmware image too small: {path}")
    if efi:
        verify_efi_partition_type(path, header)
    else:
        verify_bios_boot_sector(path, header)
    if trailing:
        if not fwtool.is_file():
            raise SystemExit(f"{path.name}: fwtool required to validate appended metadata")
        result = subprocess.run(
            [str(fwtool), "-i", "-", str(path)], capture_output=True, check=False
        )
        if result.returncode:
            # x86 images may carry a signature without device metadata.
            signature = subprocess.run(
                [str(fwtool), "-s", "-", str(path)], capture_output=True, check=False
            )
            if signature.returncode or not signature.stdout:
                raise SystemExit(f"{path.name}: invalid fwtool trailer: {signature.stderr.decode(errors='replace')}")
            return
        try:
            metadata = json.loads(result.stdout)
        except (ValueError, UnicodeDecodeError) as error:
            raise SystemExit(f"{path.name}: invalid metadata JSON") from error
        if not isinstance(metadata, dict) or not metadata.get("supported_devices"):
            raise SystemExit(f"{path.name}: metadata missing supported_devices")


def version_key(version):
    match = PACKAGE_VERSION.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid package version: {version}")
    return tuple(map(int, match[1].split("."))), int(match[2] or 0)


def minimum_core_versions():
    recipes = Path(__file__).resolve().parents[1] / "packages"
    minimum = {}
    for name in CORE_PACKAGES:
        recipe = (recipes / name / "Makefile").read_text(encoding="utf-8")
        version = re.search(r"^PKG_VERSION:=(\S+)$", recipe, re.MULTILINE)[1]
        release = re.search(r"^PKG_RELEASE:=(\d+)$", recipe, re.MULTILINE)[1]
        minimum[name] = f"{version}-r{release}"
    return minimum


def verify(target):
    fwtool = target.resolve().parents[3] / "staging_dir/host/bin/fwtool"
    images = sorted(target.glob("*combined*.img.gz"))
    bios_profiles = {path.name.removesuffix("-combined.img.gz") for path in images
                     if path.name.endswith("-combined.img.gz")}
    efi_profiles = {path.name.removesuffix("-combined-efi.img.gz") for path in images
                     if path.name.endswith("-combined-efi.img.gz")}
    if not any(profile.endswith("-squashfs") for profile in bios_profiles | efi_profiles):
        raise SystemExit("SquashFS combined firmware images missing")
    for profiles, counterparts, mode in (
        (efi_profiles, bios_profiles, "BIOS"), (bios_profiles, efi_profiles, "UEFI")
    ):
        missing = profiles - counterparts
        if missing:
            raise SystemExit(f"{mode} firmware image missing for {sorted(missing)}")
    for path in images:
        verify_image(path, fwtool)

    required = {
        "base-files", "busybox", "netifd", "dnsmasq-full", "odhcp6c",
        "odhcpd-ipv6only", "ppp", "ppp-mod-pppoe", "kmod-pppoe", "luci-mod-network",
        "luci-proto-ipv6", "luci-proto-ppp", "luci-app-firewall", "luci-compat",
        "luci-app-filemanager", "luci-app-ddns", "luci-app-upnp", "luci-app-wol", "luci-app-ttyd",
        "luci-app-openclash", "luci-app-passwall", "xray-core", "sing-box",
        "luci-app-bypass", "bypasscore", "naiveproxy", "v2ray-geoip", "v2ray-geosite",
        "luci-theme-edge", "luci-theme-vantage", "luci-theme-bootstrap",
        "luci-lua-runtime", "ucode-mod-lua",
        "luci-app-ssr-plus",
        "firewall4", "kmod-nft-tproxy", "kmod-nft-socket", "kmod-nft-nat",
        "ip-full", "kmod-tun", "kmod-vmxnet3",
        *CORE_PACKAGES,
    }
    excluded = {
        "firewall", "dnsmasq", "dnsmasq-dhcpv6", "odhcpd", "mihomo", "mihomo-meta", "mihomo-alpha", "clash-meta",
        "luci-app-nikki", "nikki", "luci-theme-argon",
        "luci-app-clashoo", "clashoo", "luci-i18n-clashoo-zh-cn",
        "luci-app-passwall2", "luci-app-homeproxy", "autosamba", "luci-app-samba",
        "luci-app-samba4", "samba36-server", "samba4-server", "luci-app-ksmbd",
        "ksmbd-server", "luci-app-nfs", "nfs-kernel-server", "luci-app-vsftpd", "vsftpd", "vsftpd-tls",
    }
    manifests = sorted(target.glob("*.manifest"))
    if not manifests:
        raise SystemExit("Firmware package manifest missing")
    minimum_versions = minimum_core_versions()
    for path in manifests:
        packages = {line.split()[0]: line.split()[-1]
                    for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}
        missing = required - packages.keys()
        if missing:
            raise SystemExit(f"{path.name}: missing packages: {sorted(missing)}")
        unexpected = excluded & packages.keys()
        if unexpected:
            raise SystemExit(f"{path.name}: unexpected packages: {sorted(unexpected)}")
        for name, minimum in minimum_versions.items():
            if version_key(packages[name]) < version_key(minimum):
                raise SystemExit(f"{path.name}: {name} {packages[name]} is below required {minimum}")
    print(f"Verified {len(images)} compressed BIOS/UEFI images and {len(manifests)} package manifests")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
