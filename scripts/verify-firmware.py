#!/usr/bin/env python3
"""Reject missing images, damaged gzip files, or incomplete target manifests."""
import json
from pathlib import Path
import subprocess
import sys
import zlib


def verify_image(path, fwtool):
    # OpenWrt may append fwtool metadata/signatures after the gzip member.
    # zlib checks the gzip CRC/length while allowing us to inspect that suffix.
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
    size = 0
    trailing = False
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                if decoder.eof:
                    trailing = True
                    break
                pending = chunk
                while pending and not decoder.eof:
                    size += len(decoder.decompress(pending, 1024 * 1024))
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


def verify(target):
    fwtool = target.resolve().parents[3] / "staging_dir/host/bin/fwtool"
    images = sorted(target.glob("*combined*.img.gz"))
    if not any("combined-efi.img.gz" in path.name for path in images):
        raise SystemExit("UEFI firmware image missing")
    if not any("combined.img.gz" in path.name for path in images):
        raise SystemExit("BIOS firmware image missing")
    for path in images:
        verify_image(path, fwtool)

    required = {
        "base-files", "busybox", "netifd", "dnsmasq-full", "odhcp6c",
        "odhcpd-ipv6only", "ppp-mod-pppoe", "luci-mod-network",
        "luci-proto-ipv6", "luci-app-firewall", "luci-compat",
        "luci-app-openclash", "luci-app-passwall2", "xray-core", "sing-box",
        "luci-theme-edge", "luci-theme-bootstrap", "luci-lua-runtime",
        "luci-app-ssr-plus",
    }
    manifests = sorted(target.glob("*.manifest"))
    if not manifests:
        raise SystemExit("Firmware package manifest missing")
    for path in manifests:
        packages = {line.split()[0] for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}
        missing = required - packages
        if missing:
            raise SystemExit(f"{path.name}: missing packages: {sorted(missing)}")
        if len({"firewall", "firewall4"} & packages) != 1:
            raise SystemExit(f"{path.name}: exactly one firewall backend is required")
        backend = ({"kmod-nft-tproxy", "kmod-nft-socket", "kmod-nft-nat"}
                   if "firewall4" in packages else
                   {"ipset", "iptables-mod-tproxy", "ip6tables-mod-nat", "kmod-ipt-nat"})
        if backend - packages:
            raise SystemExit(f"{path.name}: missing proxy backend packages: {sorted(backend - packages)}")
        if {"dnsmasq", "dnsmasq-dhcpv6", "odhcpd"} & packages:
            raise SystemExit(f"{path.name}: conflicting DNS/DHCP packages")
    print(f"Verified {len(images)} compressed BIOS/UEFI images and {len(manifests)} package manifests")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
