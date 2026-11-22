#!/bin/bash
# Shared build hooks. Source this file from the OpenWrt source directory.

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
