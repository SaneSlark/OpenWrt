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
  mkdir -p files/etc/uci-defaults
  cp "${WORKDIR}/scripts/uci-defaults/97-router-network" files/etc/uci-defaults/
  chmod +x files/etc/uci-defaults/97-router-network
  python3 "${WORKDIR}/scripts/openclash-core.py" "$PWD"
}
