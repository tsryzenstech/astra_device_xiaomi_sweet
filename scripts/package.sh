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
chmod +x "$pkg/flash-all.sh"
(cd "$OUT" && zip -qr "$name.zip" "$name")
log "package: $OUT/$name.zip"
