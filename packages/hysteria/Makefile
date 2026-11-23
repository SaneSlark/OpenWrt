include $(TOPDIR)/rules.mk

PKG_NAME:=hysteria
PKG_VERSION:=2.14.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_SOURCE:=hysteria-$(PKG_VERSION)-linux-amd64
PKG_SOURCE_URL:=https://github.com/HyNetworks/hysteria/releases/download/app/v$(PKG_VERSION)
PKG_SOURCE_URL_FILE:=hysteria-linux-amd64
PKG_HASH:=fc25edff9948708cb00a4ff01f3bccde677660aca050133bb1ad46c6860362d2

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/hysteria
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Hysteria QUIC proxy
  URL:=https://github.com/HyNetworks/hysteria
  DEPENDS:=@x86_64 +ca-bundle
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/hysteria/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(DL_DIR)/$(PKG_SOURCE) $(1)/usr/bin/hysteria
endef

$(eval $(call BuildPackage,hysteria))
