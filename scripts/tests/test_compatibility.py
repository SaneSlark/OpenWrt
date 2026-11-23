"""Regression checks for firmware images and the installed package set."""
import gzip
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from uuid import UUID

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

    def test_efi_image_partition_type(self):
        image = self.root / "combined-efi.img.gz"
        disk = bytearray(16 * 1024 * 1024)
        disk[512:520] = b"EFI PART"
        disk[584:592] = (2).to_bytes(8, "little")
        disk[1024:1040] = UUID("0fc63daf-8483-4772-8e79-3d69d8477de4").bytes_le
        image.write_bytes(gzip.compress(disk))
        with self.assertRaisesRegex(SystemExit, "not an EFI System Partition"):
            firmware.verify_image(image, self.root / "missing-fwtool")

        disk[1024:1040] = UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
        image.write_bytes(gzip.compress(disk))
        firmware.verify_image(image, self.root / "missing-fwtool")


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
            "luci-app-openclash", "luci-app-passwall", "luci-app-ssr-plus",
            "luci-app-nikki", "nikki", "mihomo-meta", "xray-core", "sing-box",
            "luci-theme-edge", "luci-theme-vantage", "luci-theme-argon", "luci-theme-bootstrap",
            "luci-lua-runtime", "ucode-mod-lua",
            "firewall4", "kmod-nft-tproxy", "kmod-nft-socket", "kmod-nft-nat",
        }

    def verify(self, extra):
        (self.root / "generic.manifest").write_text(
            "".join(f"{name} - 1\n" for name in sorted(self.packages | extra)),
            encoding="utf-8",
        )
        with patch.object(firmware, "verify_image"):
            firmware.verify(self.root)

    def test_nftables_profile(self):
        self.verify(set())

    def test_iptables_profile_rejected(self):
        self.packages.remove("firewall4")
        with self.assertRaisesRegex(SystemExit, "missing packages.*firewall4"):
            self.verify({"firewall"})

    def test_both_firewalls_rejected(self):
        with self.assertRaisesRegex(SystemExit, "unexpected packages.*firewall"):
            self.verify({"firewall"})

    def test_missing_tproxy_rejected(self):
        self.packages.remove("kmod-nft-tproxy")
        with self.assertRaisesRegex(SystemExit, "missing packages.*kmod-nft-tproxy"):
            self.verify(set())

    def test_conflicting_dhcp_rejected(self):
        with self.assertRaisesRegex(SystemExit, "unexpected packages.*dnsmasq"):
            self.verify({"dnsmasq"})

    def test_removed_or_conflicting_apps_rejected(self):
        for package in ("luci-app-clashoo", "clashoo", "luci-app-passwall2", "luci-app-homeproxy",
                        "samba4-server", "vsftpd", "mihomo", "mihomo-alpha"):
            with self.subTest(package=package), self.assertRaisesRegex(SystemExit, f"unexpected packages.*{package}"):
                self.verify({package})


if __name__ == "__main__":
    unittest.main()
