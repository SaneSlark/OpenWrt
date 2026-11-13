#!/usr/bin/env python3
"""Reject missing images, damaged gzip files, or incomplete target manifests."""
import gzip
from pathlib import Path
import sys


def verify(target):
    images = sorted(target.glob("*combined*.img.gz"))
    if not any("combined-efi.img.gz" in path.name for path in images):
        raise SystemExit("UEFI firmware image missing")
    if not any("combined.img.gz" in path.name for path in images):
        raise SystemExit("BIOS firmware image missing")
    for path in images:
        size = 0
        with gzip.open(path, "rb") as stream:
            while chunk := stream.read(1024 * 1024):
                size += len(chunk)
        if size < 16 * 1024 * 1024:
            raise SystemExit(f"Firmware image too small: {path}")

    required = {
        "base-files", "busybox", "netifd", "dnsmasq-full", "odhcp6c",
        "odhcpd-ipv6only", "ppp-mod-pppoe", "luci-mod-network",
        "luci-proto-ipv6", "luci-app-firewall", "luci-compat",
        "luci-app-openclash", "luci-app-passwall2", "xray-core", "sing-box",
        "luci-theme-edge", "luci-theme-bootstrap", "luci-lua-runtime",
    }
    manifests = sorted(target.glob("*.manifest"))
    if not manifests:
        raise SystemExit("Firmware package manifest missing")
    for path in manifests:
        packages = {line.split()[0] for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}
        missing = required - packages
        if missing:
            raise SystemExit(f"{path.name}: missing packages: {sorted(missing)}")
        if not {"firewall", "firewall4"} & packages:
            raise SystemExit(f"{path.name}: firewall missing")
        if {"dnsmasq", "dnsmasq-dhcpv6", "odhcpd"} & packages:
            raise SystemExit(f"{path.name}: conflicting DNS/DHCP packages")
    print(f"Verified {len(images)} compressed BIOS/UEFI images and {len(manifests)} package manifests")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
