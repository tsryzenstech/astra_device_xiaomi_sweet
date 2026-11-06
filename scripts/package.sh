#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bundles the images and the fastboot flashing scripts into a zip.
source "$(dirname "$0")/common.sh"
need zip

# Only images that passed scripts/verify.py get packaged.
[ "$OUT/verify.txt" -nt "$IMAGES/super.img" ] && grep -qx 'RESULT: PASS' "$OUT/verify.txt" ||
    die "these images did not pass the verification: run ./build.sh verify"

# The astraOS version the phone reports (26.0, or 26.0-rev3 for a pre-release).
version=$(grep '^ro.astra.version=' "$SYSTEM_ROOT/system/build.prop" | cut -d= -f2)
name="astraOS-${version:-dev}-${DEVICE}"
pkg=$OUT/$name
rm -rf "$pkg" "$pkg.zip"
mkdir -p "$pkg"
cp "$IMAGES"/{boot.img,boot-debug.img,boot-rescue.img,userdata.img,userdata-wipe.img,userdata-diag.img,vbmeta.img,super.img,SHA256SUMS} "$pkg/"
cp "$DEVICE_DIR"/flash/* "$OUT/verify.txt" "$pkg/"
cp "$OUT/u-boot/u-boot.img" "$pkg/"
(cd "$pkg" && sha256sum u-boot.img >> SHA256SUMS)
chmod +x "$pkg/flash-all.sh" "$pkg/flash-diag.sh"
(cd "$OUT" && zip -qr "$name.zip" "$name")
log "package: $OUT/$name.zip"
