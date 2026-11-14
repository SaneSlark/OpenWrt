#!/bin/bash
# Run inside the source tree after make defconfig, before an expensive build.
set -eu
required=(
  IPV6 KERNEL_IPV6 GRUB_IMAGES GRUB_EFI_IMAGES
  TARGET_ROOTFS_SQUASHFS
  PACKAGE_luci-app-openclash PACKAGE_luci-app-passwall2
  PACKAGE_luci-app-ssr-plus PACKAGE_xray-core PACKAGE_sing-box
  PACKAGE_luci-app-filemanager
  PACKAGE_luci-compat PACKAGE_luci-mod-network PACKAGE_luci-app-firewall
  PACKAGE_luci-theme-edge PACKAGE_luci-theme-bootstrap PACKAGE_luci-lua-runtime
  PACKAGE_luci-proto-ipv6 PACKAGE_luci-proto-ppp
  PACKAGE_ppp-mod-pppoe PACKAGE_odhcp6c PACKAGE_odhcpd-ipv6only
  PACKAGE_dnsmasq-full PACKAGE_dnsmasq_full_dhcp PACKAGE_dnsmasq_full_dhcpv6
  PACKAGE_dnsmasq_full_dnssec PACKAGE_kmod-tun PACKAGE_ip-full
)
failed=0
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
for package in dnsmasq dnsmasq-dhcpv6 odhcpd; do
  if grep -qxF "CONFIG_PACKAGE_${package}=y" .config; then
    echo "Conflicting DHCP/DNS package: $package" >&2
    failed=1
  fi
done
if grep -qxF 'CONFIG_PACKAGE_firewall4=y' .config; then
  backend=Nftables
  dns_set=nftset
  if grep -qxF 'CONFIG_PACKAGE_firewall=y' .config; then
    echo "Conflicting firewall and firewall4 packages" >&2
    failed=1
  fi
else
  backend=Iptables
  dns_set=ipset
  grep -qxF 'CONFIG_PACKAGE_firewall=y' .config || failed=1
fi
for app in passwall2 ssr-plus; do
  grep -qxF "CONFIG_PACKAGE_luci-app-${app}_${backend}_Transparent_Proxy=y" .config || {
    echo "$app backend does not match $backend" >&2
    failed=1
  }
done
if [ "$backend" = Nftables ]; then
  required_backend=(kmod-nft-tproxy kmod-nft-socket kmod-nft-nat)
else
  required_backend=(ipset iptables-mod-tproxy ip6tables-mod-nat kmod-ipt-nat)
fi
for package in "${required_backend[@]}"; do
  grep -qxF "CONFIG_PACKAGE_${package}=y" .config || {
    echo "Missing transparent proxy dependency: $package" >&2
    failed=1
  }
done
grep -qxF "CONFIG_PACKAGE_dnsmasq_full_${dns_set}=y" .config || failed=1
test -s files/etc/openclash/core/clash_meta || failed=1
[ "$failed" = 0 ] || exit 1
echo "Router, IPv6, DNS/DHCP and proxy configuration verified ($backend)."
