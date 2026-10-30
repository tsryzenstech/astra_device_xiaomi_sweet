#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds the mainline kernel: Image.gz, the sweet device tree and modules.
#
# Native on arm64. On other hosts set CROSS_COMPILE (e.g. aarch64-linux-gnu-).
source "$(dirname "$0")/common.sh"
need make gcc bc bison flex

KSRC=$SRC/linux
KOUT=$OUT/kernel

if [ "$KERNEL_SOURCE" = postmarketos ]; then
    # postmarketOS's kernel package: /boot/vmlinuz is an EFI zboot image
    # (a zstd compressed Image inside a PE wrapper), which the Android
    # bootloader cannot start, so unpack the Image as postmarketOS does.
    need curl tar zstd python3 sha256sum
    pkg=$CACHE/$(basename "$PMOS_KERNEL_URL")
    if ! echo "$PMOS_KERNEL_SHA256  $pkg" | sha256sum -c --status 2>/dev/null; then
        log "kernel: downloading $(basename "$PMOS_KERNEL_URL")"
        mkdir -p "$CACHE"
        curl -fL --retry 3 -o "$pkg.part" "$PMOS_KERNEL_URL"
        echo "$PMOS_KERNEL_SHA256  $pkg.part" | sha256sum -c --status || die "kernel package checksum mismatch"
        mv "$pkg.part" "$pkg"
    fi
    rm -rf "$KOUT" "$OUT/modules" "$OUT/pmos-kernel"
    mkdir -p "$OUT/pmos-kernel" "$KOUT/arch/arm64/boot/dts/qcom" "$KOUT/include/config" "$OUT/modules/lib/modules"
    # An apk is several gzip streams in a row: -i reads past each end.
    tar -xzif "$pkg" -C "$OUT/pmos-kernel" 2>/dev/null || true
    P=$OUT/pmos-kernel
    [ -f "$P/boot/vmlinuz" ] || die "no /boot/vmlinuz in the kernel package"
    python3 - "$P/boot/vmlinuz" "$P/Image.zst" <<'EOF'
import struct, sys
b = open(sys.argv[1], "rb").read()
if b[:2] != b"MZ" or b[4:8] != b"zimg":
    sys.exit("vmlinuz is not an EFI zboot image")
off, size = struct.unpack("<II", b[8:16])
if not b[24:32].startswith(b"zstd"):
    sys.exit("zboot payload is not zstd")
open(sys.argv[2], "wb").write(b[off:off + size])
EOF
    zstd -dqf "$P/Image.zst" -o "$P/Image"
    python3 - "$P/Image" <<'EOF'
import sys
if open(sys.argv[1], "rb").read(64)[0x38:0x3c] != b"ARMd":
    sys.exit("the unpacked kernel is not an arm64 Image")
EOF
    gzip -9n < "$P/Image" > "$KOUT/arch/arm64/boot/Image.gz"
    cp "$P/boot/dtbs/$KERNEL_DTB" "$KOUT/arch/arm64/boot/dts/$KERNEL_DTB"
    cp "$P/boot/config" "$KOUT/.config"
    release=$(ls "$P/usr/lib/modules")
    echo "$release" > "$KOUT/include/config/kernel.release"
    cp -a "$P/usr/lib/modules/$release" "$OUT/modules/lib/modules/"
    rm -f "$OUT"/modules/lib/modules/*/build "$OUT"/modules/lib/modules/*/source
    for opt in SCSI_UFS_QCOM PHY_QCOM_QMP_UFS BLK_DEV_DM DEVTMPFS EXT4_FS DRM_MSM; do
        grep -q "^CONFIG_${opt}=y" "$KOUT/.config" || die "the postmarketOS kernel lacks CONFIG_${opt}=y"
    done
    log "kernel: postmarketOS $release ready ($(stat -c %s "$P/Image") bytes)"
    exit 0
fi

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
# simpledrm takes card0 at boot and leaves the MSM display on card1.
grep -q "^CONFIG_DRM_SIMPLEDRM=y" "$KOUT/.config" && die "CONFIG_DRM_SIMPLEDRM must be off (check kernel/astra.config)"

log "kernel: building"
kmake Image.gz dtbs modules

log "kernel: installing modules"
rm -rf "$OUT/modules"
kmake INSTALL_MOD_PATH="$OUT/modules" INSTALL_MOD_STRIP=1 modules_install
rm -f "$OUT"/modules/lib/modules/*/build "$OUT"/modules/lib/modules/*/source

[ -f "$KOUT/arch/arm64/boot/dts/$KERNEL_DTB" ] || die "device tree $KERNEL_DTB was not built"
log "kernel: $(kernel_release) ready"
