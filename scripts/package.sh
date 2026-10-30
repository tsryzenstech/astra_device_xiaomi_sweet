#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bundles the images and the fastboot flashing scripts into a zip.
source "$(dirname "$0")/common.sh"
need zip

version=$(grep '^ro.astra.version=' "$SYSTEM_ROOT/system/build.prop" | cut -d= -f2)
name="astraOS-${version:-dev}-${DEVICE}-$(date -u +%Y%m%d)"
pkg=$OUT/$name
rm -rf "$pkg" "$pkg.zip"
mkdir -p "$pkg"
cp "$IMAGES"/{boot.img,boot-debug.img,boot-rescue.img,userdata.img,vbmeta.img,super.img,SHA256SUMS} "$pkg/"
cp "$DEVICE_DIR"/flash/* "$pkg/"
if [ -f "$OUT/u-boot/u-boot.img" ]; then
    cp "$OUT/u-boot/u-boot.img" "$pkg/"
    (cd "$pkg" && sha256sum u-boot.img >> SHA256SUMS)
else
    warn "no u-boot.img (run ./build.sh uboot): the package boots boot.img from the stock bootloader"
fi
chmod +x "$pkg/flash-all.sh"
(cd "$OUT" && zip -qr "$name.zip" "$name")
log "package: $OUT/$name.zip"
