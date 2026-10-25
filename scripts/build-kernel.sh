#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds the mainline kernel: Image.gz, the sweet device tree and modules.
#
# Native on arm64. On other hosts set CROSS_COMPILE (e.g. aarch64-linux-gnu-).
source "$(dirname "$0")/common.sh"
need make gcc bc bison flex

KSRC=$SRC/linux
KOUT=$OUT/kernel
[ -d "$KSRC" ] || die "kernel sources missing, run ./build.sh fetch"
mkdir -p "$KOUT"

kmake() {
    make -C "$KSRC" O="$KOUT" ARCH=arm64 ${CROSS_COMPILE:+CROSS_COMPILE=$CROSS_COMPILE} -j"$JOBS" "$@"
}

log "kernel: configuring ($KERNEL_CONFIGS + astra.config)"
# shellcheck disable=SC2086
kmake $KERNEL_CONFIGS
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$KOUT" "$KOUT/.config" "$DEVICE_DIR/kernel/astra.config" >/dev/null
kmake olddefconfig

# Options the first stage cannot live without must not end up as modules.
for opt in SCSI_UFS_QCOM PHY_QCOM_QMP_UFS BLK_DEV_DM DEVTMPFS EXT4_FS; do
    grep -q "^CONFIG_${opt}=y" "$KOUT/.config" || die "CONFIG_${opt} must be built in (check kernel/astra.config)"
done

log "kernel: building"
kmake Image.gz dtbs modules

log "kernel: installing modules"
rm -rf "$OUT/modules"
kmake INSTALL_MOD_PATH="$OUT/modules" INSTALL_MOD_STRIP=1 modules_install
rm -f "$OUT"/modules/lib/modules/*/build "$OUT"/modules/lib/modules/*/source

[ -f "$KOUT/arch/arm64/boot/dts/$KERNEL_DTB" ] || die "device tree $KERNEL_DTB was not built"
log "kernel: $(kernel_release) ready"
