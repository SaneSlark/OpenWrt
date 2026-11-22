#!/bin/bash
set -e

# ===========================================================
# ImmortalWrt 和 OpenWrt 官方源码的 x86_64 自定义脚本
# STAGE=pre  : 添加自定义 feeds 和主题包
# STAGE=post : 复制 .config 后调整默认配置
# ===========================================================

WORKDIR="${GITHUB_WORKSPACE:-$PWD}"
OPENWRT_DIR="${WORKDIR}/openwrt"
STAGE="${STAGE:-pre}"
source "${WORKDIR}/scripts/router-common.sh"

# ===== 自定义区域：需要不同插件时改这里 =====
DEFAULT_THEME="edge"
LAN_IP="192.168.2.1"
LAN_NETMASK="255.255.255.0"
HOSTNAME="${ROUTER_HOSTNAME:-ImmortalWrt}"
TIMEZONE="CST-8"
ZONENAME="Asia/Shanghai"

ENABLE_THEME_EDGE="true"
ENABLE_PASSWALL="true"
ENABLE_SSR_PLUS="true"
ENABLE_SSR_PLUS_LEGACY_EXTRAS="true"
ENABLE_HYSTERIA="true"
ENABLE_NAIVEPROXY="true"
ENABLE_FILETRANSFER="true"
ENABLE_VLMCSD="true"
ENABLE_KCPTUN="true"
# ============================================

module_paths() {
  local makefile

  for makefile in package/feeds/*/mosdns/Makefile feeds/*/net/mosdns/Makefile; do
    [ -f "$makefile" ] || continue
    if grep -q '^GO_PKG:=github.com/IrineSistiana/mosdns$' "$makefile"; then
      sed -i 's#^GO_PKG:=github.com/IrineSistiana/mosdns$#GO_PKG:=github.com/IrineSistiana/mosdns/v5#' "$makefile"
      echo "Fixed mosdns GO_PKG module path in $makefile."
    fi
  done
}

pre_stage() {
  cd "$OPENWRT_DIR"

  router_configure_feeds feeds.conf.default
  router_pre
}

post_stage() {
  cd "$OPENWRT_DIR"

  router_post

  module_paths

  sed -i "s#192.168.1.1#${LAN_IP}#g" package/base-files/files/bin/config_generate || true
  sed -i "s#255.255.255.0#${LAN_NETMASK}#g" package/base-files/files/bin/config_generate || true
  sed -i "s#hostname='OpenWrt'#hostname='${HOSTNAME}'#g" package/base-files/files/bin/config_generate || true
  sed -i "s#hostname='ImmortalWrt'#hostname='${HOSTNAME}'#g" package/base-files/files/bin/config_generate || true
  sed -i "s#timezone='UTC'#timezone='${TIMEZONE}'#g" package/base-files/files/bin/config_generate || true
  sed -i "s#zonename='UTC'#zonename='${ZONENAME}'#g" package/base-files/files/bin/config_generate || true

  if grep -q '^CONFIG_PACKAGE_luci-theme-edge=y' .config 2>/dev/null; then
    mkdir -p files/etc/uci-defaults
    cat > files/etc/uci-defaults/99-default-theme <<EOF
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/${DEFAULT_THEME}'
uci commit luci
exit 0
EOF
    chmod +x files/etc/uci-defaults/99-default-theme
  fi

  mkdir -p files/etc/uci-defaults
  cat > files/etc/uci-defaults/98-default-language <<'EOF'
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci commit luci
exit 0
EOF
  chmod +x files/etc/uci-defaults/98-default-language

  [ "$ENABLE_SSR_PLUS" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-ssr-plus/d;/CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn/d;/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_/d' .config || true
  if [ "$ENABLE_SSR_PLUS_LEGACY_EXTRAS" != "true" ]; then
    sed -i \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Simple_Obfs=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Redsocks2=y/d' \
      .config || true
  fi
  [ "$ENABLE_PASSWALL" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-passwall\([=_ ]\)/d;/CONFIG_PACKAGE_luci-i18n-passwall-zh-cn/d' .config || true
  [ "$ENABLE_HYSTERIA" = "true" ] || sed -i '/CONFIG_PACKAGE_hysteria=y/d;/CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y/d' .config || true
  [ "$ENABLE_NAIVEPROXY" = "true" ] || sed -i '/CONFIG_PACKAGE_naiveproxy=y/d;/CONFIG_PACKAGE_luci-app-passwall_INCLUDE_NaiveProxy=y/d' .config || true
  [ "$ENABLE_FILETRANSFER" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-filemanager=y/d;/CONFIG_PACKAGE_luci-i18n-filemanager-zh-cn=y/d' .config || true
  [ "$ENABLE_VLMCSD" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-vlmcsd=y/d;/CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y/d' .config || true
  [ "$ENABLE_KCPTUN" = "true" ] || sed -i '/CONFIG_PACKAGE_kcptun-client=y/d' .config || true
  [ "$ENABLE_THEME_EDGE" = "true" ] || sed -i '/luci-theme-edge/d' .config || true

  grep -qxF 'CONFIG_PACKAGE_luci-compat=y' .config || echo 'CONFIG_PACKAGE_luci-compat=y' >> .config
}

case "$STAGE" in
  pre) pre_stage ;;
  post) post_stage ;;
  *)
    echo "Unknown STAGE: $STAGE"
    exit 1
    ;;
esac
