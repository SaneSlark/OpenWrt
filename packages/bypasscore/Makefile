include $(TOPDIR)/rules.mk

PKG_NAME:=bypasscore
PKG_VERSION:=1.5.5
PKG_RELEASE:=1
PKG_LICENSE:=MIT

PKG_SOURCE:=bypasscore-$(PKG_VERSION)-openwrt-x86_64.tar.gz
PKG_SOURCE_URL:=https://github.com/kinmeic/BypassCore/releases/download/v$(PKG_VERSION)
PKG_SOURCE_URL_FILE:=bypasscore-openwrt-x86_64.tar.gz
PKG_HASH:=faf7132644df5d86aa37f702ac1c4a7e006f65bbcf11f48ccdc0faf13d6464ea

include $(INCLUDE_DIR)/package.mk

# The upstream OpenWrt executable is already packed with UPX.
RSTRIP:=:

define Package/bypasscore
  SECTION:=net
  CATEGORY:=Network
  TITLE:=BypassCore routing engine
  URL:=https://github.com/kinmeic/BypassCore
  DEPENDS:=@x86_64 +ca-bundle
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) bypasscore-openwrt-x86_64
endef

define Build/Compile
endef

define Package/bypasscore/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bypasscore-openwrt-x86_64 $(1)/usr/bin/bypasscore
endef

$(eval $(call BuildPackage,bypasscore))
