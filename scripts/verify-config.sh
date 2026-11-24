#!/bin/bash
# Run inside the source tree after make defconfig, before an expensive build.
set -eu
required=(
  IPV6 KERNEL_IPV6 GRUB_IMAGES GRUB_EFI_IMAGES
  TARGET_ROOTFS_SQUASHFS
  PACKAGE_luci-app-openclash PACKAGE_luci-app-passwall PACKAGE_luci-app-homeproxy
  PACKAGE_luci-i18n-homeproxy-zh-cn PACKAGE_ucode-mod-digest
  PACKAGE_naiveproxy PACKAGE_v2ray-geoip PACKAGE_v2ray-geosite
  PACKAGE_luci-app-ssr-plus PACKAGE_xray-core PACKAGE_sing-box PACKAGE_hysteria PACKAGE_tuic-client
  PACKAGE_luci-app-ssr-plus_INCLUDE_Mihomo PACKAGE_mihomo
  PACKAGE_luci-app-filemanager
  PACKAGE_luci-compat PACKAGE_luci-mod-network PACKAGE_luci-app-firewall
  PACKAGE_luci-theme-edge PACKAGE_luci-theme-vantage PACKAGE_luci-theme-bootstrap
  PACKAGE_luci-lua-runtime PACKAGE_ucode-mod-lua
  PACKAGE_luci-proto-ipv6 PACKAGE_luci-proto-ppp
  PACKAGE_ppp PACKAGE_ppp-mod-pppoe PACKAGE_kmod-pppoe PACKAGE_odhcp6c PACKAGE_odhcpd-ipv6only
  PACKAGE_dnsmasq-full PACKAGE_dnsmasq_full_dhcp PACKAGE_dnsmasq_full_dhcpv6
  PACKAGE_dnsmasq_full_dnssec PACKAGE_dnsmasq_full_nftset PACKAGE_kmod-tun PACKAGE_ip-full
  PACKAGE_firewall4 PACKAGE_kmod-nft-tproxy PACKAGE_kmod-nft-socket PACKAGE_kmod-nft-nat
  PACKAGE_kmod-vmxnet3
)
excluded=(
  firewall dnsmasq dnsmasq-dhcpv6 odhcpd mihomo-meta mihomo-alpha clash-meta
  luci-app-nikki nikki luci-theme-argon
  luci-app-bypass bypasscore luci-i18n-bypass-zh-cn
  luci-app-clashoo clashoo luci-i18n-clashoo-zh-cn
  luci-app-passwall2 autosamba luci-app-samba luci-app-samba4 samba36-server samba4-server
  luci-app-ksmbd ksmbd-server luci-app-nfs nfs-kernel-server luci-app-vsftpd vsftpd vsftpd-tls
)
failed=0
if [ "${FIRMWARE_VARIANT:-}" = "openwrt" ]; then
  for feed in helloworld passwall passwall_packages vantage; do
    if grep -qE "^CONFIG_FEED_${feed}=[ym]$" .config; then
      echo "Build-only feed must not be listed in official APK repositories: $feed" >&2
      failed=1
    fi
  done
fi
# A missing Kconfig symbol is silently discarded by defconfig. Check every
# explicitly requested package and package option, including optional apps.
if [ -n "${CONFIG_FILE:-}" ]; then
  requested="${GITHUB_WORKSPACE:-$PWD}/$CONFIG_FILE"
  test -f "$requested"
  while IFS= read -r selection; do
    if ! grep -qxF "$selection" .config; then
      echo "Requested package/option was dropped by defconfig: $selection" >&2
      failed=1
    fi
  done < <(grep -E '^CONFIG_PACKAGE_[A-Za-z0-9_-]+=y$' "$requested")
fi
if grep -qxF 'CONFIG_BUSYBOX_CUSTOM=y' .config; then
  required+=(BUSYBOX_CONFIG_UDHCPC)
else
  required+=(BUSYBOX_DEFAULT_UDHCPC)
fi
for option in "${required[@]}"; do
  if ! grep -qxF "CONFIG_${option}=y" .config; then
    echo "Missing required router option: CONFIG_${option}=y" >&2
    failed=1
  fi
done
for package in "${excluded[@]}"; do
  if grep -qxF "CONFIG_PACKAGE_${package}=y" .config; then
    echo "Unexpected package in the router configuration: $package" >&2
    failed=1
  fi
done
for app in passwall ssr-plus; do
  grep -qxF "CONFIG_PACKAGE_luci-app-${app}_Nftables_Transparent_Proxy=y" .config || {
    echo "$app requires the nftables backend" >&2
    failed=1
  }
done
if grep -qxF 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Http_Proxy=y' .config &&
   ! grep -qxF 'CONFIG_PACKAGE_3proxy=y' .config; then
  echo "SSR-Plus HTTP proxy requires 3proxy to be built into the firmware." >&2
  failed=1
fi
test -s files/etc/openclash/core/clash_meta || failed=1
[ "$failed" = 0 ] || exit 1
echo "Router, IPv6, DNS/DHCP and nftables proxy configuration verified."
