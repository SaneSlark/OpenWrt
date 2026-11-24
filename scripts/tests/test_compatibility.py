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
        self.disk = bytearray(16 * 1024 * 1024)
        self.disk[0] = 0xEB
        self.disk[446] = 0x80
        self.disk[510:512] = b"\x55\xaa"
        self.archive = gzip.compress(self.disk)
        self.image.write_bytes(self.archive)

    def test_complete_gzip(self):
        firmware.verify_image(self.image, self.root / "missing-fwtool")

    def test_bios_boot_sector_required(self):
        for offset, reason in ((510, "MBR signature"), (0, "boot code"), (446, "not active")):
            with self.subTest(reason=reason), self.assertRaisesRegex(SystemExit, reason):
                header = self.disk[:512]
                header[offset] = 0
                firmware.verify_bios_boot_sector(self.image, header)

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
        for name in ("generic-squashfs-combined.img.gz", "generic-squashfs-combined-efi.img.gz"):
            (self.root / name).touch()
        self.packages = {
            "base-files", "busybox", "netifd", "dnsmasq-full", "odhcp6c",
            "odhcpd-ipv6only", "ppp", "ppp-mod-pppoe", "kmod-pppoe", "luci-mod-network",
            "luci-proto-ipv6", "luci-proto-ppp", "luci-app-firewall", "luci-compat",
            "luci-app-filemanager", "luci-app-ddns", "luci-app-upnp", "luci-app-wol", "luci-app-ttyd",
            "luci-app-openclash", "luci-app-passwall", "luci-app-ssr-plus",
            "luci-app-homeproxy", "luci-i18n-homeproxy-zh-cn", "ucode-mod-digest",
            "v2ray-geoip", "v2ray-geosite",
            "xray-core", "sing-box", "luci-theme-edge", "luci-theme-vantage", "luci-theme-bootstrap",
            "luci-lua-runtime", "ucode-mod-lua",
            "firewall4", "kmod-nft-tproxy", "kmod-nft-socket", "kmod-nft-nat",
            "ip-full", "kmod-tun", "kmod-vmxnet3",
        }
        self.versions = {
            "xray-core": "26.11.9-r2",
            "sing-box": "1.14.4-r1",
            "hysteria": "2.14.0-r1",
            "tuic-client": "1.8.11-r1",
            "naiveproxy": "154.0.8037.49-5",
            "mihomo": "1.19.34-r1",
        }
        self.packages.update(self.versions)

    def verify(self, extra, *, official=False):
        (self.root / "generic.manifest").write_text(
            "".join(f"{name} - {self.versions.get(name, '1')}\n" for name in sorted(self.packages | extra)),
            encoding="utf-8",
        )
        with patch.object(firmware, "verify_image"):
            firmware.verify(self.root, official=official)

    def test_nftables_profile(self):
        self.verify(set())

    def test_official_apk_repositories_match_firmware_release(self):
        etc = self.root.parents[3] / "build_dir/target-x86_64_musl/root-x86/etc"
        repos = etc / "apk/repositories.d"
        repos.mkdir(parents=True)
        (etc / "openwrt_release").write_text("DISTRIB_RELEASE='25.12.6'\n", encoding="utf-8")
        base = "https://downloads.openwrt.org/releases/25.12.6"
        feeds = [
            f"{base}/targets/x86/64/packages/packages.adb",
            *(f"{base}/packages/x86_64/{feed}/packages.adb"
              for feed in ("base", "luci", "packages", "routing", "telephony", "video")),
        ]
        distfeeds = repos / "distfeeds.list"
        distfeeds.write_text("\n".join(feeds), encoding="utf-8")
        self.verify(set(), official=True)
        for invalid in (
            f"{base}/packages/x86_64/passwall/packages.adb",
            feeds[1].replace("25.12.6", "25.12.5"),
        ):
            with self.subTest(invalid=invalid), self.assertRaisesRegex(SystemExit, "Unexpected APK repositories"):
                distfeeds.write_text("\n".join([*feeds, invalid]), encoding="utf-8")
                self.verify(set(), official=True)

    def test_stale_proxy_core_rejected(self):
        self.versions["sing-box"] = "1.12.25-r1"
        with self.assertRaisesRegex(SystemExit, "sing-box.*below required"):
            self.verify(set())

    def test_ssr_plus_mihomo_core_required(self):
        self.packages.remove("mihomo")
        with self.assertRaisesRegex(SystemExit, "missing packages.*mihomo"):
            self.verify(set())

    def test_homeproxy_required(self):
        self.packages.remove("luci-app-homeproxy")
        with self.assertRaisesRegex(SystemExit, "missing packages.*luci-app-homeproxy"):
            self.verify(set())

    def test_stale_naiveproxy_release_rejected(self):
        self.versions["naiveproxy"] = "154.0.8037.49-r4"
        with self.assertRaisesRegex(SystemExit, "naiveproxy.*below required"):
            self.verify(set())

    def test_each_filesystem_needs_both_boot_images(self):
        (self.root / "generic-ext4-combined.img.gz").touch()
        with self.assertRaisesRegex(SystemExit, "UEFI firmware image missing.*ext4"):
            self.verify(set())

    def test_firmware_needs_pppoe_ui_file_manager_and_esxi_driver(self):
        for package in ("luci-proto-ppp", "luci-app-filemanager", "kmod-vmxnet3"):
            with self.subTest(package=package), patch.object(self, "packages", self.packages - {package}):
                with self.assertRaisesRegex(SystemExit, f"missing packages.*{package}"):
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
        for package in ("luci-app-clashoo", "clashoo", "luci-app-passwall2",
                        "samba4-server", "vsftpd", "mihomo-alpha", "mihomo-meta",
                        "luci-app-nikki", "nikki", "luci-theme-argon",
                        "luci-app-bypass", "bypasscore", "luci-i18n-bypass-zh-cn"):
            with self.subTest(package=package), self.assertRaisesRegex(SystemExit, f"unexpected packages.*{package}"):
                self.verify({package})


if __name__ == "__main__":
    unittest.main()
