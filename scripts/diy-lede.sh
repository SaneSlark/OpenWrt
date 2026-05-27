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
# LEDE 方案仅保留较稳定的两类代理插件：
# - SSR-Plus
# - Passwall2
# 其他较新的代理应用不在此方案默认启用。
ENABLE_FILETRANSFER="true"
ENABLE_VLMCSD="true"
ENABLE_SSR_PLUS="true"
ENABLE_SSR_PLUS_LEGACY_EXTRAS="true"
ENABLE_PASSWALL2="true"
ENABLE_HYSTERIA="true"
ENABLE_KCPTUN="true"
ENABLE_NAIVEPROXY="true"
ENABLE_SINGBOX="true"
ENABLE_TUIC_CLIENT="true"
ENABLE_PASSWALL2_LEGACY_EXTRAS="true"
# ====================================================================

app_feed() {
  local enabled="$1"
  local line="$2"
  local file="$3"

  [ "$enabled" = "true" ] || return 0
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

configure_feeds() {
  local file="$1"

  # Pin LuCI to 24.10 so LuCI apps and custom packages use the same stable base.
  sed -i -E "s#^src-git luci .*\$#src-git luci https://github.com/coolsnowwolf/luci.git;${LUCI_FEED_BRANCH}#" "$file"
  grep -Eq '^src-git luci ' "$file" || echo "src-git luci https://github.com/coolsnowwolf/luci.git;${LUCI_FEED_BRANCH}" >> "$file"

  # Keep custom feeds in a deterministic order; the first feed wins on duplicate packages.
  sed -i \
    -e '\#src-git helloworld https://github.com/fw876/helloworld.git#d' \
    -e '\#src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main#d' \
    -e '\#src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main#d' \
    "$file"

  app_feed "$ENABLE_PASSWALL2" "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main" "$file"
  app_feed "$ENABLE_PASSWALL2" "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main" "$file"
  app_feed "$ENABLE_SSR_PLUS" "src-git helloworld https://github.com/fw876/helloworld.git" "$file"
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

patch_packages() {
  local dir makefile src dst

  for makefile in package/feeds/*/mosdns/Makefile feeds/*/net/mosdns/Makefile; do
    [ -f "$makefile" ] || continue
    if grep -q '^GO_PKG:=github.com/IrineSistiana/mosdns$' "$makefile"; then
      sed -i 's#^GO_PKG:=github.com/IrineSistiana/mosdns$#GO_PKG:=github.com/IrineSistiana/mosdns/v5#' "$makefile"
      echo "Fixed mosdns GO_PKG module path in $makefile."
    fi
  done

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

  src="feeds/helloworld/shadowsocksr-libev"
  dst="package/custom/shadowsocksr-libev"
  if [ -d "$src" ]; then
    rm -rf package/feeds/*/shadowsocksr-libev "$dst"
    mkdir -p package/custom
    cp -a "$src" "$dst"
    echo "Using helloworld bundled shadowsocksr-libev source."
  fi

  for makefile in package/feeds/*/xray-core/Makefile feeds/*/xray-core/Makefile; do
    [ -f "$makefile" ] || continue
    cat > "$makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=25.2.21
PKG_RELEASE:=1

PKG_SOURCE:=xray-core-$(PKG_VERSION)-linux-64.zip
PKG_SOURCE_URL:=https://github.com/XTLS/Xray-core/releases/download/v$(PKG_VERSION)/
PKG_SOURCE_URL_FILE:=Xray-linux-64.zip
PKG_HASH:=3e90f0bbb5bbb2b397f46fec96b0eb4a240448bf8d282666da2f80cbaaa24fe7

PKG_MAINTAINER:=Tianling Shen <cnsztl@immortalwrt.org>
PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/xray-core
  TITLE:=A platform for building proxies to bypass network restrictions
  SECTION:=net
  CATEGORY:=Network
  URL:=https://xtls.github.io
  DEPENDS:=@TARGET_x86_64 +ca-bundle
endef

define Package/xray-core/description
  Xray helps you to build your own computer network.
endef

define Package/xray-core/conffiles
/etc/xray/
/etc/config/xray
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	unzip -q -d $(PKG_BUILD_DIR) $(DL_DIR)/$(PKG_SOURCE)
endef

define Build/Compile
endef

define Package/xray-core/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/xray $(1)/usr/bin/xray
	$(INSTALL_DIR) $(1)/usr/share/xray
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/geoip.dat $(1)/usr/share/xray/geoip.dat
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/geosite.dat $(1)/usr/share/xray/geosite.dat
endef

$(eval $(call BuildPackage,xray-core))
EOF
    echo "Patched $makefile to package official prebuilt Xray-linux-64.zip."
  done
}

disable_autosamba() {
  # LEDE x86 selects autosamba by default; remove it when samba4 is selected.
  if grep -Eq '^(CONFIG_PACKAGE_luci-app-samba4|CONFIG_PACKAGE_samba4-server)=y' .config 2>/dev/null || [ "$STAGE" = "pre" ]; then
    sed -i -E 's/(^|[[:space:]])autosamba([[:space:]]|$)/ /g' target/linux/x86/Makefile 2>/dev/null || true
    rm -rf package/lean/autosamba
    if [ -f .config ]; then
      sed -i \
        -e '/CONFIG_DEFAULT_autosamba/d' \
        -e '/CONFIG_PACKAGE_autosamba/d' \
        -e '/CONFIG_PACKAGE_autosamba_INCLUDE_/d' \
        .config || true
      cat >> .config <<'EOF'
# CONFIG_DEFAULT_autosamba is not set
# CONFIG_PACKAGE_autosamba is not set
EOF
    fi
    echo "Disabled LEDE autosamba default package for samba4 builds."
  fi
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
  [ "$ENABLE_FILETRANSFER" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-filetransfer=y/d;/CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y/d' .config || true
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
  [ "$ENABLE_PASSWALL2" = "true" ] || sed -i '/CONFIG_PACKAGE_luci-app-passwall2/d;/CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn/d' .config || true
  [ "$ENABLE_HYSTERIA" = "true" ] || sed -i '/CONFIG_PACKAGE_hysteria=y/d;/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Hysteria=y/d' .config || true
  if [ "$ENABLE_NAIVEPROXY" != "true" ]; then
    sed -i '/CONFIG_PACKAGE_naiveproxy=y/d;/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_NaiveProxy=y/d' .config || true
  fi
  if [ "$ENABLE_SINGBOX" != "true" ]; then
    sed -i \
      -e '/CONFIG_PACKAGE_sing-box/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_SingBox/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_/d' \
      -e '/CONFIG_SING_BOX_BUILD_/d' \
      .config || true
    cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox is not set
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set
# CONFIG_PACKAGE_sing-box is not set
EOF
  fi
  if [ "$ENABLE_TUIC_CLIENT" != "true" ]; then
    sed -i '/CONFIG_PACKAGE_tuic-client=y/d;/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_tuic_client=y/d' .config || true
  fi
  if [ "$ENABLE_PASSWALL2_LEGACY_EXTRAS" != "true" ]; then
    sed -i \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Haproxy=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Client=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Server=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Simple_Obfs=y/d' \
      -e '/CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_V2ray_Plugin=y/d' \
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

  disable_autosamba
  configure_feeds feeds.conf.default

  mkdir -p package/custom

  if [ "$ENABLE_KCPTUN" = "true" ]; then
    kcptun_package
  fi

  if [ "$ENABLE_THEME_EDGE" = "true" ]; then
    clone_update "https://github.com/kiddin9/luci-theme-edge.git" "package/custom/luci-theme-edge" "master"
  fi
}

post_stage() {
  cd "$OPENWRT_DIR"

  patch_packages
  system_defaults
  disabled_packages
  disable_autosamba
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
