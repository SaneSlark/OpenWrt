include $(TOPDIR)/rules.mk

PKG_NAME:=mihomo
PKG_VERSION:=1.19.34
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_SOURCE:=mihomo-linux-amd64-compatible-v$(PKG_VERSION).gz
PKG_SOURCE_URL:=https://github.com/MetaCubeX/mihomo/releases/download/v$(PKG_VERSION)
PKG_HASH:=2763f5b414527f7baf6dc57e3f82f3ab561eedf34bfd7c2f2cde1f7e592efe06

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/mihomo
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mihomo proxy core
  URL:=https://github.com/MetaCubeX/mihomo
  DEPENDS:=@x86_64 +ca-bundle
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	gzip -dc $(DL_DIR)/$(PKG_SOURCE) > $(PKG_BUILD_DIR)/mihomo
endef

define Build/Compile
endef

define Package/mihomo/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mihomo $(1)/usr/bin/mihomo
endef

$(eval $(call BuildPackage,mihomo))
