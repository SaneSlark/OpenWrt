#!/bin/bash
# Shared build hooks. Source this file from the OpenWrt source directory.

router_configure_feeds() {
  local file="$1"

  # Keep the custom packages in a consistent order when rerunning preprocessing.
  sed -i -E '/^src-git[[:blank:]]+(passwall_packages|passwall2?|helloworld|homeproxy|clashoo|nikki|vantage)[[:blank:]]/d' "$file"
  if [ "$ENABLE_PASSWALL" = "true" ]; then
    # The forks also ship PassWall in LuCI. Install the official app first.
    sed -i '1i src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' "$file"
    echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >> "$file"
  fi
  if [ "$ENABLE_SSR_PLUS" = "true" ]; then
    echo 'src-git helloworld https://github.com/fw876/helloworld.git' >> "$file"
  fi
  cat >> "$file" <<'EOF'
src-git vantage https://github.com/anothaDev/luci-theme-vantage.git;main
EOF
}

router_pre() {
  router_fix_efi_partition_type
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

  local homeproxy="package/custom/luci-app-homeproxy"
  if [ -d "$homeproxy/.git" ]; then
    git -C "$homeproxy" pull --ff-only
  else
    git clone --depth 1 --single-branch -b master \
      https://github.com/immortalwrt/homeproxy.git "$homeproxy"
  fi

  if [ "$ENABLE_THEME_EDGE" = "true" ]; then
    local theme="package/custom/luci-theme-edge"
    rm -rf "$theme"
    git clone --depth 1 --single-branch -b master https://github.com/kiddin9/luci-theme-edge.git "$theme"
    git -C "$theme" apply "${WORKDIR}/patches/luci-theme-edge-luci.patch"
  fi
}

router_fix_efi_partition_type() {
  local makefile="target/linux/x86/image/Makefile"
  local original='$(if $(filter $(1),efi),GUID="$(IMG_PART_DISKGUID)") $(SCRIPT_DIR)/gen_image_generic.sh'
  local fixed='$(if $(filter $(1),efi),GUID="$(IMG_PART_DISKGUID)" KERNELPARTTYPE=ef) $(SCRIPT_DIR)/gen_image_generic.sh'

  if grep -Fq "$fixed" "$makefile"; then
    return 0
  fi
  # The first GPT partition contains FAT and EFI/BOOT/BOOTX64.EFI.
  # ptgen maps ef to the EFI System Partition GUID without changing its PARTUUID.
  if ! grep -Fq "$original" "$makefile"; then
    echo "x86 image generation changed; could not set the EFI partition type." >&2
    return 1
  fi
  sed -i 's/efi),GUID="$(IMG_PART_DISKGUID)") $(SCRIPT_DIR)\/gen_image_generic\.sh/efi),GUID="$(IMG_PART_DISKGUID)" KERNELPARTTYPE=ef) $(SCRIPT_DIR)\/gen_image_generic.sh/' "$makefile"
  grep -Fq "$fixed" "$makefile"
}

router_post() {
  router_fix_host_tools
  if [ "${FIRMWARE_VARIANT:-}" = "openwrt" ] && [ -L package/feeds/luci/luci-app-weechat ]; then
    # The unused 25.12.6 app forms a dependency cycle with its two core variants.
    rm -f package/feeds/luci/luci-app-weechat
  fi
  mkdir -p files/etc/uci-defaults
  cp "${WORKDIR}/scripts/uci-defaults/97-router-network" files/etc/uci-defaults/
  chmod +x files/etc/uci-defaults/97-router-network
  python3 "${WORKDIR}/scripts/openclash-core.py" "$PWD"
}

router_use_release_packages() {
  local name dest
  for name in "$@"; do
    dest="package/custom/$name"
    mkdir -p "$dest"
    cp -a "${WORKDIR}/packages/$name/." "$dest/"
    # Preserve the upstream standalone services alongside the new binaries.
    if [ "$name" = xray-core ] || [ "$name" = sing-box ]; then
      if [ -d "feeds/packages/net/$name/files" ]; then
        cp -a "feeds/packages/net/$name/files" "$dest/"
      fi
    fi
    if [ "$name" = naiveproxy ]; then
      cp -a feeds/passwall_packages/naiveproxy/files "$dest/"
    fi
    # Leave one package recipe visible to OpenWrt's package scanner.
    rm -f package/feeds/*/"$name"
  done
}

router_fix_host_tools() {
  local makefile="package/custom/luci-app-openclash/Makefile"
  # OpenClash invokes po2lmo directly rather than through luci.mk.
  # The 24.10 luci-base host package supplies the translation compiler.
  if ! grep -q 'PKG_BUILD_DEPENDS.*luci-base/host' "$makefile"; then
    sed -i '/^include.*package\.mk/i PKG_BUILD_DEPENDS+=luci-base/host' "$makefile"
  fi
}
