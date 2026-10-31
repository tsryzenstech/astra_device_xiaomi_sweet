#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bundles the images and the fastboot flashing scripts into a zip:
#   u-boot.img     -> boot      (astraOS's U-Boot)
#   userdata.img   -> userdata  (postmarketOS with astraOS, from the pmos step)
#   vbmeta.img     -> vbmeta    (empty, verification disabled)
source "$(dirname "$0")/common.sh"
need zip python3 sha256sum

[ -f "$OUT/pmos/userdata.img" ] || die "package: no userdata.img, run ./build.sh pmos"
[ -f "$OUT/u-boot/u-boot.img" ] || die "package: no u-boot.img, run ./build.sh uboot"

# The astraOS version the phone reports (26.0, or 26.0-rev3 for a pre-release).
version=$(sed -n 's/^ro.astra.version=//p' "$OUT/astra-install/system/build.prop" 2>/dev/null)
version=${version:-dev}
name="astraOS-${version}-${DEVICE}"
pkg=$OUT/$name
rm -rf "$pkg" "$pkg.zip"
mkdir -p "$pkg"
cp "$OUT/u-boot/u-boot.img" "$OUT/pmos/userdata.img" "$pkg/"
python3 "$DEVICE_DIR/scripts/mkvbmeta.py" "$pkg/vbmeta.img"
cp "$DEVICE_DIR"/flash/* "$pkg/"
chmod +x "$pkg/flash-all.sh"
(cd "$pkg" && sha256sum u-boot.img userdata.img vbmeta.img > SHA256SUMS)
(cd "$OUT" && zip -qr "$name.zip" "$name")
log "package: $OUT/$name.zip"
