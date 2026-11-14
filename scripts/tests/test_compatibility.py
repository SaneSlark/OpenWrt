"""Regression checks for gzip validation and firewall/backend conflicts."""
import gzip
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("firmware", SCRIPTS / "verify-firmware.py")
firmware = importlib.util.module_from_spec(spec)
spec.loader.exec_module(firmware)


class ImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / "combined.img.gz"
        self.archive = gzip.compress(b"\0" * (16 * 1024 * 1024))
        self.image.write_bytes(self.archive)

    def test_complete_gzip(self):
        firmware.verify_image(self.image, self.root / "missing-fwtool")

    def test_truncated_gzip(self):
        self.image.write_bytes(self.archive[:-4])
        with self.assertRaisesRegex(SystemExit, "truncated"):
            firmware.verify_image(self.image, self.root / "missing-fwtool")

    def test_corrupt_crc(self):
        data = bytearray(self.archive)
        data[-8] ^= 1
        self.image.write_bytes(data)
        with self.assertRaisesRegex(SystemExit, "invalid gzip"):
            firmware.verify_image(self.image, self.root / "missing-fwtool")

    def test_unverified_trailer_rejected(self):
        self.image.write_bytes(self.archive + b"invalid trailer")
        with self.assertRaisesRegex(SystemExit, "fwtool required"):
            firmware.verify_image(self.image, self.root / "missing-fwtool")

    def test_signed_image(self):
        self.image.write_bytes(self.archive + b"signature")
        fwtool = self.root / "fwtool"
        fwtool.touch()
        responses = [
            subprocess.CompletedProcess([], 1, b"", b"no metadata"),
            subprocess.CompletedProcess([], 0, b"signature", b""),
        ]
        with patch.object(firmware.subprocess, "run", side_effect=responses):
            firmware.verify_image(self.image, fwtool)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "openwrt/bin/targets/x86/64"
        self.root.mkdir(parents=True)
        for name in ("combined.img.gz", "combined-efi.img.gz"):
            (self.root / name).touch()
        self.packages = {
            "base-files", "busybox", "netifd", "dnsmasq-full", "odhcp6c",
            "odhcpd-ipv6only", "ppp-mod-pppoe", "luci-mod-network",
            "luci-proto-ipv6", "luci-app-firewall", "luci-compat",
            "luci-app-openclash", "luci-app-passwall2", "luci-app-ssr-plus",
            "xray-core", "sing-box", "luci-theme-edge",
            "luci-theme-bootstrap", "luci-lua-runtime",
        }

    def verify(self, extra):
        (self.root / "generic.manifest").write_text(
            "".join(f"{name} - 1\n" for name in sorted(self.packages | extra)),
            encoding="utf-8",
        )
        with patch.object(firmware, "verify_image"):
            firmware.verify(self.root)

    def test_nftables_profile(self):
        self.verify({"firewall4", "kmod-nft-tproxy", "kmod-nft-socket", "kmod-nft-nat"})

    def test_iptables_profile(self):
        self.verify({"firewall", "ipset", "iptables-mod-tproxy", "ip6tables-mod-nat", "kmod-ipt-nat"})

    def test_both_firewalls_rejected(self):
        with self.assertRaisesRegex(SystemExit, "exactly one"):
            self.verify({"firewall", "firewall4"})

    def test_missing_tproxy_rejected(self):
        with self.assertRaisesRegex(SystemExit, "missing proxy backend"):
            self.verify({"firewall4", "kmod-nft-socket", "kmod-nft-nat"})

    def test_conflicting_dhcp_rejected(self):
        with self.assertRaisesRegex(SystemExit, "conflicting DNS"):
            self.verify({"firewall4", "kmod-nft-tproxy", "kmod-nft-socket", "kmod-nft-nat", "dnsmasq"})


if __name__ == "__main__":
    unittest.main()
