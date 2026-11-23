include $(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=1.14.4
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_SOURCE:=sing-box-$(PKG_VERSION)-linux-amd64-musl.tar.gz
PKG_SOURCE_URL:=https://github.com/SagerNet/sing-box/releases/download/v$(PKG_VERSION)
PKG_HASH:=8f7c5f0651238850d96a0e488e5473cd77ec1a0098f63942e943f475a12057ca
PKG_BUILD_DIR:=$(BUILD_DIR)/sing-box-$(PKG_VERSION)-linux-amd64-musl

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/sing-box
  SECTION:=net
  CATEGORY:=Network
  TITLE:=sing-box universal proxy platform
  URL:=https://sing-box.sagernet.org/
  DEPENDS:=@x86_64 +ca-bundle +kmod-inet-diag +kmod-netlink-diag +kmod-tun
  USERID:=sing-box=5566:sing-box=5566
endef

define Build/Compile
endef

define Package/sing-box/conffiles
/etc/config/sing-box
/etc/sing-box/
endef

define Package/sing-box/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sing-box $(1)/usr/bin/sing-box
	set -e; if [ -f ./files/sing-box.init ]; then \
		$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/config $(1)/etc/sing-box; \
		$(INSTALL_BIN) ./files/sing-box.init $(1)/etc/init.d/sing-box; \
		$(INSTALL_CONF) ./files/sing-box.conf $(1)/etc/config/sing-box; \
		$(INSTALL_DATA) ./config.json $(1)/etc/sing-box/config.json; \
	fi
endef

$(eval $(call BuildPackage,sing-box))
