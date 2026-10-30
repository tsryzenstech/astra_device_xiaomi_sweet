#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds u-boot.img: astraOS's U-Boot (a fork of sm7150-mainline's, silent,
# without logos) wrapped in an Android boot image for the stock bootloader.
# It goes to the boot partition and starts astraOS from userdata.img.
#
# Native on arm64. On other hosts set CROSS_COMPILE (e.g. aarch64-linux-gnu-).
source "$(dirname "$0")/common.sh"
need git make gcc bison flex python3 mkbootimg gzip

# Every package ships u-boot.img; UBOOT_REPO= builds one without it.
if [ -z "$UBOOT_REPO" ]; then
    warn "u-boot: UBOOT_REPO is empty: no u-boot.img"
    exit 0
fi
git ls-remote --exit-code "$UBOOT_REPO" "$UBOOT_REF" >/dev/null 2>&1 ||
    die "u-boot: $UBOOT_REPO ($UBOOT_REF) is not reachable"
src=$SRC/u-boot
log "u-boot: $UBOOT_REPO ($UBOOT_REF)"
git_fetch "$UBOOT_REPO" "$UBOOT_REF" "$src"

build=$OUT/u-boot-build
umake() { make -C "$src" O="$build" ${CROSS_COMPILE:+CROSS_COMPILE=$CROSS_COMPILE} "$@"; }
umake qcom_defconfig qcom-phone.config tauchgang.config astra.config >/dev/null
umake -j"$JOBS" CONFIG_DEFAULT_DEVICE_TREE="$UBOOT_DTB" >/dev/null

# The stock bootloader loads U-Boot like a kernel: gzipped, with the device
# tree appended, in a header v0 boot image.
dtb=$build/dts/upstream/src/arm64/$UBOOT_DTB.dtb
[ -f "$dtb" ] || die "U-Boot device tree $UBOOT_DTB was not built"
gzip -9n < "$build/u-boot-nodtb.bin" > "$build/u-boot-nodtb.bin.gz"
cat "$build/u-boot-nodtb.bin.gz" "$dtb" > "$build/uboot-dtb"
mkdir -p "$OUT/u-boot"
mkbootimg --base 0x0 --kernel_offset 0x00008000 --pagesize 4096 \
    --kernel "$build/uboot-dtb" --output "$OUT/u-boot/u-boot.img"
log "u-boot: $OUT/u-boot/u-boot.img"
