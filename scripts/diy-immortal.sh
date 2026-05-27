#!/bin/bash
set -e

# ===========================================================
# ImmortalWrt x86_64 自定义脚本
# STAGE=pre  : 添加自定义 feeds 和主题包
# STAGE=post : 复制 .config 后调整默认配置
# ===========================================================

WORKDIR="${GITHUB_WORKSPACE:-$PWD}"
OPENWRT_DIR="${WORKDIR}/openwrt"
STAGE="${STAGE:-pre}"

# ===== 自定义区域：需要不同插件时改这里 =====
DEFAULT_THEME="edge"
LAN_IP="192.168.2.1"
LAN_NETMASK="255.255.255.0"
HOSTNAME="ImmortalWrt"
TIMEZONE="CST-8"
ZONENAME="Asia/Shanghai"

ENABLE_THEME_EDGE="true"
ENABLE_PASSWALL2="true"
ENABLE_HOMEPROXY="true"
ENABLE_SSR_PLUS="true"
ENABLE_SSR_PLUS_LEGACY_EXTRAS="true"
ENABLE_NIKKI="true"
ENABLE_HYSTERIA="true"
ENABLE_NAIVEPROXY="true"
ENABLE_FILETRANSFER="true"
ENABLE_VLMCSD="true"
ENABLE_KCPTUN="true"
# ============================================

app_feed() {
  local enabled="$1"
  local line="$2"
  local file="$3"

  [ "$enabled" = "true" ] || return 0
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

configure_feeds() {
  local file="$1"

  # 保持自定义 feeds 的确定性顺序，重复包以第一个出现的 feed 为准。
  sed -i \
    -e '\#src-git helloworld https://github.com/fw876/helloworld.git#d' \
    -e '\#src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main#d' \
    -e '\#src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main#d' \
    -e '\#src-git homeproxy https://github.com/immortalwrt/homeproxy.git;master#d' \
    -e '\#src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main#d' \
    "$file"

  app_feed "$ENABLE_PASSWALL2" "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main" "$file"
  app_feed "$ENABLE_PASSWALL2" "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main" "$file"
  app_feed "$ENABLE_SSR_PLUS" "src-git helloworld https://github.com/fw876/helloworld.git" "$file"
  app_feed "$ENABLE_HOMEPROXY" "src-git homeproxy https://github.com/immortalwrt/homeproxy.git;master" "$file"
  app_feed "$ENABLE_NIKKI" "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main" "$file"
}

clone_update() {
  local repo="$1"
  local dest="$2"
  local branch="$3"

  rm -rf "$dest"
  if [ -n "$branch" ]; then
    git clone --depth 1 -b "$branch" "$repo" "$dest"
  else
    git clone --depth 1 "$repo" "$dest"
  fi
}

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

patch_hysteria() {
  local dir makefile

  for dir in package/feeds/*/hysteria feeds/*/hysteria; do
    [ -d "$dir" ] || continue
    makefile="$dir/Makefile"
    cat > "$makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=hysteria
PKG_VERSION:=2.8.2
PKG_RELEASE:=1

PKG_SOURCE:=hysteria-linux-amd64
PKG_SOURCE_URL:=https://github.com/apernet/hysteria/releases/download/app/v$(PKG_VERSION)/
PKG_HASH:=b11bf0fb5f84a3f5c6baff3696e899539e68af4cee868c9203cfb896784ad3b0

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Aperture Internet Laboratory

include $(INCLUDE_DIR)/package.mk

define Package/hysteria
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A feature-packed network utility optimized for networks of poor quality
  URL:=https://github.com/apernet/hysteria
  DEPENDS:=@TARGET_x86_64 +ca-bundle
endef

define Package/hysteria/description
  Hysteria is a feature-packed network utility optimized for networks of poor quality.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR)/hysteria
endef

define Build/Compile
endef

define Package/hysteria/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/hysteria $(1)/usr/bin/hysteria
endef

$(eval $(call BuildPackage,hysteria))
EOF
    echo "Patched $makefile to package official prebuilt hysteria-linux-amd64."
  done
}

pre_stage() {
  cd "$OPENWRT_DIR"

  configure_feeds feeds.conf.default
  mkdir -p package/custom

  if [ "$ENABLE_THEME_EDGE" = "true" ]; then
    clone_update "https://github.com/kiddin9/luci-theme-edge.git" "package/custom/luci-theme-edge" "master"
  fi
}

post_stage() {
  cd "$OPENWRT_DIR"

  module_paths
  patch_hysteria

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
  [ "$ENABLE_PASSWALL2" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-passwall2/d;/CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn/d' .config || true
  [ "$ENABLE_HOMEPROXY" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-homeproxy/d;/CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn/d' .config || true
  [ "$ENABLE_NIKKI" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-nikki/d;/CONFIG_PACKAGE_nikki/d;/CONFIG_PACKAGE_luci-i18n-nikki-zh-cn/d' .config || true
  [ "$ENABLE_HYSTERIA" = "true" ] || sed -i '/CONFIG_PACKAGE_hysteria=y/d;/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Hysteria=y/d' .config || true
  [ "$ENABLE_NAIVEPROXY" = "true" ] || sed -i '/CONFIG_PACKAGE_naiveproxy=y/d;/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_NaiveProxy=y/d' .config || true
  [ "$ENABLE_FILETRANSFER" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-filetransfer=y/d;/CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y/d' .config || true
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
