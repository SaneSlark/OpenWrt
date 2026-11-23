include $(TOPDIR)/rules.mk

PKG_NAME:=tuic-client
PKG_VERSION:=1.8.11
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only
PKG_SOURCE:=tuic-client-$(PKG_VERSION)-x86_64-linux-musl
PKG_SOURCE_URL:=https://github.com/Itsusinn/tuic/releases/download/v$(PKG_VERSION)
PKG_SOURCE_URL_FILE:=tuic-client-x86_64-linux-musl
PKG_HASH:=5f1ddd442f4417479507b4124e3038a738b435860ec633950e390d740f29114a

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/tuic-client
  SECTION:=net
  CATEGORY:=Network
  TITLE:=TUIC proxy client
  URL:=https://github.com/Itsusinn/tuic
  DEPENDS:=@x86_64 +ca-bundle
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/tuic-client/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(DL_DIR)/$(PKG_SOURCE) $(1)/usr/bin/tuic-client
endef

$(eval $(call BuildPackage,tuic-client))
