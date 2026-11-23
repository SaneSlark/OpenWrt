include $(TOPDIR)/rules.mk

PKG_NAME:=naiveproxy
PKG_VERSION:=154.0.8037.49
PKG_RELEASE:=5
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE
PKG_SOURCE:=naiveproxy-v$(PKG_VERSION)-$(PKG_RELEASE)-openwrt-x86_64.tar.xz
PKG_SOURCE_URL:=https://github.com/klzgrad/naiveproxy/releases/download/v$(PKG_VERSION)-$(PKG_RELEASE)
PKG_HASH:=1eaf0fdbc1ae5d253502b6095221d6a745ac23241faa83c9afb0a1ad76b9ddfa
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE:.tar.xz=)

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/naiveproxy
  SECTION:=net
  CATEGORY:=Network
  TITLE:=NaiveProxy
  URL:=https://github.com/klzgrad/naiveproxy
  DEPENDS:=@x86_64 @USE_MUSL +ca-bundle +libatomic
endef

define Build/Compile
endef

define Package/naiveproxy/conffiles
/etc/config/naiveproxy
endef

define Package/naiveproxy/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/naive $(1)/usr/bin/naive
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d
	$(INSTALL_CONF) ./files/naiveproxy.config $(1)/etc/config/naiveproxy
	$(INSTALL_BIN) ./files/naiveproxy.init $(1)/etc/init.d/naiveproxy
endef

$(eval $(call BuildPackage,naiveproxy))
