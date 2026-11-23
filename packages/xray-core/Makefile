include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=26.11.9
PKG_RELEASE:=1
PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_SOURCE:=Xray-linux-64-$(PKG_VERSION).zip
PKG_SOURCE_URL:=https://github.com/XTLS/Xray-core/releases/download/v$(PKG_VERSION)
PKG_SOURCE_URL_FILE:=Xray-linux-64.zip
PKG_HASH:=b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/xray-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Xray proxy platform
  URL:=https://github.com/XTLS/Xray-core
  DEPENDS:=@x86_64 +ca-bundle
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	unzip -oq $(DL_DIR)/$(PKG_SOURCE) xray LICENSE -d $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/xray-core/conffiles
/etc/xray/
/etc/config/xray
endef

define Package/xray-core/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/xray $(1)/usr/bin/xray
	set -e; if [ -f ./files/xray.init ]; then \
		$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/config $(1)/etc/xray; \
		$(INSTALL_BIN) ./files/xray.init $(1)/etc/init.d/xray; \
		$(INSTALL_CONF) ./files/xray.conf $(1)/etc/config/xray; \
		$(INSTALL_DATA) ./files/config.json.example $(1)/etc/xray/; \
		$(if $(wildcard ./files/vpoint_*.json),$(INSTALL_DATA) ./files/vpoint_*.json $(1)/etc/xray/,true); \
	fi
endef

$(eval $(call BuildPackage,xray-core))
