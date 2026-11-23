#!/bin/bash
set -e

# ===========================================================
# OpenWrt x86_64 + LEDE 自定义脚本
# STAGE=pre  : 添加额外 feeds、主题和插件
# STAGE=post : 复制 .config 后调整默认配置
# ===========================================================

WORKDIR="${GITHUB_WORKSPACE:-$PWD}"
OPENWRT_DIR="${WORKDIR}/openwrt"
STAGE="${STAGE:-pre}"
source "${WORKDIR}/scripts/router-common.sh"

# ====== 自定义区域 ======
DEFAULT_THEME="edge"
LUCI_FEED_BRANCH="openwrt-24.10"
KCPTUN_PACKAGE_BRANCHES="openwrt-24.10"
LAN_IP="192.168.2.1"
LAN_NETMASK="255.255.255.0"
HOSTNAME="OpenWrt"
TIMEZONE="CST-8"
ZONENAME="Asia/Shanghai"

ENABLE_THEME_EDGE="true"
# LEDE 方案包含 OpenClash、Bypass、SSR-Plus 和 PassWall。
ENABLE_FILETRANSFER="true"
ENABLE_VLMCSD="true"
ENABLE_SSR_PLUS="true"
ENABLE_SSR_PLUS_LEGACY_EXTRAS="true"
ENABLE_PASSWALL="true"
ENABLE_HYSTERIA="true"
ENABLE_KCPTUN="true"
ENABLE_NAIVEPROXY="true"
ENABLE_SINGBOX="true"
ENABLE_TUIC_CLIENT="true"
ENABLE_PASSWALL_LEGACY_EXTRAS="true"
# ====================================================================

configure_feeds() {
  local file="$1"

  # Retain the original 24.10 LuCI compatibility baseline for Edge.
  sed -i -E "s#^src-git luci .*\$#src-git luci https://github.com/coolsnowwolf/luci.git;${LUCI_FEED_BRANCH}#" "$file"
  grep -Eq '^src-git luci ' "$file" || echo "src-git luci https://github.com/coolsnowwolf/luci.git;${LUCI_FEED_BRANCH}" >> "$file"

  router_configure_feeds "$file"
}

patch_packages() {
  local dir makefile src dst

  for makefile in package/feeds/*/mosdns/Makefile feeds/*/net/mosdns/Makefile; do
    [ -f "$makefile" ] || continue
    if grep -q '^GO_PKG:=github.com/IrineSistiana/mosdns$' "$makefile"; then
      sed -i 's#^GO_PKG:=github.com/IrineSistiana/mosdns$#GO_PKG:=github.com/IrineSistiana/mosdns/v5#' "$makefile"
      echo "Fixed mosdns GO_PKG module path in $makefile."
    fi
  done

  src="feeds/helloworld/shadowsocksr-libev"
  dst="package/custom/shadowsocksr-libev"
  if [ -d "$src" ]; then
    rm -rf package/feeds/*/shadowsocksr-libev "$dst"
    mkdir -p package/custom
    cp -a "$src" "$dst"
    echo "Using helloworld bundled shadowsocksr-libev source."
  fi

}

disable_nas_defaults() {
  # LEDE can select file-sharing servers through target defaults.
  sed -i -E ':again; s/(^|[[:blank:]])(autosamba|luci-app-vsftpd|vsftpd)([[:blank:]]|$)/\1\3/; t again' \
    include/target.mk target/linux/x86/Makefile
}

kcptun_package() {
  local tmp_dir="package/custom/openwrt-packages-kcptun"
  local dst_dir="package/custom/kcptun"
  local branch

  rm -rf "$tmp_dir" "$dst_dir"
  for branch in $KCPTUN_PACKAGE_BRANCHES; do
    rm -rf "$tmp_dir"
    git clone --depth 1 --filter=blob:none --sparse -b "$branch" https://github.com/openwrt/packages.git "$tmp_dir"
    git -C "$tmp_dir" sparse-checkout set net/kcptun
    if [ -d "$tmp_dir/net/kcptun" ]; then
      mv "$tmp_dir/net/kcptun" "$dst_dir"
      break
    fi
  done
  if [ ! -d "$dst_dir" ]; then
    echo "Failed to fetch kcptun package from openwrt/packages stable branches." >&2
    return 1
  fi
  rm -rf "$tmp_dir"
  sed -i 's#^include ../../lang/golang/golang-package.mk#include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#' "$dst_dir/Makefile"
}

luci_runtime() {
  local pkg

  for pkg in \
    CONFIG_PACKAGE_luci-base=y \
    CONFIG_PACKAGE_luci-mod-admin-full=y \
    CONFIG_PACKAGE_luci-compat=y \
    CONFIG_PACKAGE_luci-theme-bootstrap=y \
    CONFIG_PACKAGE_uhttpd=y \
    CONFIG_PACKAGE_uhttpd-mod-ubus=y \
    CONFIG_PACKAGE_rpcd=y \
    CONFIG_PACKAGE_rpcd-mod-file=y \
    CONFIG_PACKAGE_rpcd-mod-iwinfo=y \
    CONFIG_PACKAGE_rpcd-mod-luci=y \
    CONFIG_PACKAGE_libustream-openssl=y
  do
    grep -qxF "$pkg" .config || echo "$pkg" >> .config
  done
}

system_defaults() {
  sed -i "s#192.168.1.1#${LAN_IP}#g" package/base-files/files/bin/config_generate || true
  sed -i "s#255.255.255.0#${LAN_NETMASK}#g" package/base-files/files/bin/config_generate || true
  sed -i "s#hostname='OpenWrt'#hostname='${HOSTNAME}'#g" package/base-files/files/bin/config_generate || true
  sed -i "s#hostname='LEDE'#hostname='${HOSTNAME}'#g" package/base-files/files/bin/config_generate || true
  sed -i "s#timezone='UTC'#timezone='${TIMEZONE}'#g" package/base-files/files/bin/config_generate || true
  sed -i "s#zonename='UTC'#zonename='${ZONENAME}'#g" package/base-files/files/bin/config_generate || true

  mkdir -p files/etc/uci-defaults
  cat > files/etc/uci-defaults/10-default-hostname <<EOF
#!/bin/sh
uci -q set system.@system[0].hostname='${HOSTNAME}'
uci -q commit system
hostname '${HOSTNAME}'
exit 0
EOF
  chmod +x files/etc/uci-defaults/10-default-hostname
}

luci_defaults() {
  mkdir -p files/etc/uci-defaults

  if grep -Eq '^CONFIG_PACKAGE_luci-theme-(bootstrap|edge)=y' .config 2>/dev/null; then
    cat > files/etc/uci-defaults/99-default-theme <<EOF
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}'
uci commit luci
exit 0
EOF
    chmod +x files/etc/uci-defaults/99-default-theme
  fi

  cat > files/etc/uci-defaults/98-default-language <<'EOF'
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci commit luci
exit 0
EOF
  chmod +x files/etc/uci-defaults/98-default-language
}

disabled_packages() {
  [ "$ENABLE_FILETRANSFER" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-filemanager=y/d;/CONFIG_PACKAGE_luci-i18n-filemanager-zh-cn=y/d' .config || true
  [ "$ENABLE_VLMCSD" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-vlmcsd=y/d;/CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y/d' .config || true
  [ "$ENABLE_SSR_PLUS" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-ssr-plus/d;/CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn/d;/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_/d' .config || true
  if [ "$ENABLE_SSR_PLUS_LEGACY_EXTRAS" != "true" ]; then
    sed -i \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Mihomo=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Mihomo_Client=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Simple_Obfs=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Redsocks2=y/d' \
      -e '/CONFIG_PACKAGE_mihomo=y/d' \
      -e '/CONFIG_PACKAGE_mosdns=y/d' \
      .config || true
  fi
  [ "$ENABLE_PASSWALL" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-passwall\([=_ ]\)/d;/CONFIG_PACKAGE_luci-i18n-passwall-zh-cn/d' .config || true
  [ "$ENABLE_HYSTERIA" = "true" ] || sed -i '/CONFIG_PACKAGE_hysteria=y/d;/CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y/d' .config || true
  if [ "$ENABLE_NAIVEPROXY" != "true" ]; then
    sed -i '/CONFIG_PACKAGE_naiveproxy=y/d;/CONFIG_PACKAGE_luci-app-passwall_INCLUDE_NaiveProxy=y/d' .config || true
  fi
  if [ "$ENABLE_SINGBOX" != "true" ]; then
    sed -i \
      -e '/CONFIG_PACKAGE_sing-box/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox/d' \
      -e '/CONFIG_SING_BOX_BUILD_/d' \
      .config || true
    cat >> .config <<'EOF'
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox is not set
# CONFIG_PACKAGE_sing-box is not set
EOF
  fi
  if [ "$ENABLE_TUIC_CLIENT" != "true" ]; then
    sed -i '/CONFIG_PACKAGE_tuic-client=y/d' .config || true
  fi
  if [ "$ENABLE_PASSWALL_LEGACY_EXTRAS" != "true" ]; then
    sed -i \
      -e 's/^\(CONFIG_PACKAGE_luci-app-passwall_INCLUDE_\(Haproxy\|Shadowsocks_Rust_Client\|Shadowsocks_Rust_Server\|Simple_Obfs\|V2ray_Plugin\)\)=y$/# \1 is not set/' \
      -e '/CONFIG_PACKAGE_haproxy=y/d' \
      -e '/CONFIG_PACKAGE_shadowsocks-rust-/d' \
      -e '/CONFIG_PACKAGE_simple-obfs-/d' \
      -e '/CONFIG_PACKAGE_v2ray-plugin=y/d' \
      .config || true
  fi
  [ "$ENABLE_THEME_EDGE" = "true" ] || sed -i '/luci-theme-edge/d' .config || true
}

pre_stage() {
  cd "$OPENWRT_DIR"

  disable_nas_defaults
  configure_feeds feeds.conf.default
  # elfutils regenerates its parser in maintainer mode. Its generators and
  # their installed data must be ready before a parallel tools build starts.
  bash "${WORKDIR}/scripts/lede-host-tools.sh"
  gettext_gnulib
  router_pre

  if [ "$ENABLE_KCPTUN" = "true" ]; then
    kcptun_package
  fi
}

gettext_gnulib() {
  # Match the gnulib baseline used with gettext 0.22.5 in OpenWrt 24.10.
  # Scope it to gettext: newer LEDE host tools still need their own gnulib.
  local revision="c99c8d491850dc3a6e0b8604a2729d8bc5c0eff1"
  local dest=".gettext-gnulib"
  local makefile="package/libs/gettext-full/Makefile"
  local version
  version="$(sed -n 's/^PKG_VERSION:=//p' "$makefile")"
  if [ -z "$version" ]; then
    echo "Could not read the gettext version from $makefile." >&2
    return 1
  fi
  if [ "$version" != "0.22.5" ]; then
    echo "Using upstream gnulib for gettext $version."
    return 0
  fi
  if [ ! -d "$dest/.git" ]; then
    git init "$dest"
    git -C "$dest" remote add origin https://github.com/coreutils/gnulib.git
  fi
  git -C "$dest" fetch --depth 1 origin "$revision"
  git -C "$dest" checkout --detach FETCH_HEAD
  test "$(git -C "$dest" rev-parse HEAD)" = "$revision"
  # Remove the earlier partial fix when reusing an existing checkout.
  rm -f package/libs/gettext-full/patches/901-gettext-gnulib-exitfail.patch
  sed -i 's#^export GNULIB_SRCDIR:=.*#export GNULIB_SRCDIR:=$(TOPDIR)/.gettext-gnulib#' "$makefile"
  grep -qxF 'export GNULIB_SRCDIR:=$(TOPDIR)/.gettext-gnulib' "$makefile"
}

post_stage() {
  cd "$OPENWRT_DIR"

  router_post
  router_use_release_packages hysteria tuic-client naiveproxy

  patch_packages
  system_defaults
  disabled_packages
  luci_defaults
  luci_runtime
}

case "$STAGE" in
  pre) pre_stage ;;
  post) post_stage ;;
  *)
    echo "Unknown STAGE: $STAGE"
    exit 1
    ;;
esac
