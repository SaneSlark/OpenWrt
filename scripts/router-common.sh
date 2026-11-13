#!/bin/bash
# Shared build hooks. Source this file from the OpenWrt source directory.

router_pre() {
  # Keep the upstream package tree out of package/ to avoid duplicate scanning.
  if [ -d .openclash-source/.git ]; then
    git -C .openclash-source pull --ff-only
  else
    git clone --depth 1 --single-branch -b master \
      https://github.com/vernesong/OpenClash.git .openclash-source
  fi
  mkdir -p package/custom
  mkdir -p package/custom/luci-app-openclash
  cp -a .openclash-source/luci-app-openclash/. package/custom/luci-app-openclash/
}

router_post() {
  router_fix_host_tools
  mkdir -p files/etc/uci-defaults
  cp "${WORKDIR}/scripts/uci-defaults/97-router-network" files/etc/uci-defaults/
  chmod +x files/etc/uci-defaults/97-router-network
  python3 "${WORKDIR}/scripts/openclash-core.py" "$PWD"
}

router_fix_host_tools() {
  local makefile="package/custom/luci-app-openclash/Makefile"

  # OpenClash uses po2lmo in Build/Prepare without luci.mk's implicit dependency.
  # The 24.10 luci-base host package supplies the translation compiler.
  if ! grep -q 'PKG_BUILD_DEPENDS.*luci-base/host' "$makefile"; then
    sed -i '/^include.*package\.mk/i PKG_BUILD_DEPENDS+=luci-base/host' "$makefile"
  fi

  # upx/host is a feed host package, installed in hostpkg rather than host.
  for makefile in package/feeds/*/mihomo/Makefile feeds/*/mihomo/Makefile feeds/*/net/mihomo/Makefile; do
    [ -f "$makefile" ] || continue
    if grep -Fq '$(STAGING_DIR_HOST)/bin/upx' "$makefile"; then
      sed -i 's#$(STAGING_DIR_HOST)/bin/upx#$(STAGING_DIR_HOSTPKG)/bin/upx#g' "$makefile"
      echo "Fixed UPX host package path in $makefile."
    fi
  done
}
