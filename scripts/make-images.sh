#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Creates the flashable images: boot, vbmeta and super (system, vendor, product).
source "$(dirname "$0")/common.sh"
need mke2fs mkbootimg lpmake avbtool python3

KOUT=$OUT/kernel/arch/arm64/boot

mkext4() {
    local name=$1 dir=$2 size
    size=$(image_size_mb "$dir")
    log "images: $name.img (${size} MiB)"
    rm -f "$IMAGES/$name.img"
    # Read-only partitions: no journal, deterministic timestamps.
    E2FSPROGS_FAKE_TIME=1700000000 mke2fs -q -t ext4 -b 4096 -L "$name" -O ^has_journal \
        -E root_owner=0:0 -d "$dir" "$IMAGES/$name.img" "${size}M"
}

mkext4 system "$SYSTEM_ROOT"
mkext4 vendor "$VENDOR_ROOT"
mkext4 product "$PRODUCT_ROOT"

mkboot() {   # mkboot <file> <cmdline>
    log "images: $1"
    mkbootimg \
        --header_version "$BOOT_HEADER_VERSION" \
        --kernel "$KOUT/Image.gz" \
        --ramdisk "$OUT/ramdisk.cpio.gz" \
        --dtb "$KOUT/dts/$KERNEL_DTB" \
        --cmdline "$2" \
        --base "$BOOT_BASE" \
        --kernel_offset "$BOOT_KERNEL_OFFSET" \
        --ramdisk_offset "$BOOT_RAMDISK_OFFSET" \
        --tags_offset "$BOOT_TAGS_OFFSET" \
        --dtb_offset "$BOOT_DTB_OFFSET" \
        --pagesize "$BOOT_PAGESIZE" \
        --os_version "$BOOT_OS_VERSION" \
        --os_patch_level "$BOOT_OS_PATCH_LEVEL" \
        --output "$IMAGES/$1"
}
# The bootloader puts the device tree BOOT_DTB_OFFSET - BOOT_KERNEL_OFFSET
# after the kernel: a bigger (uncompressed) kernel overwrites it, and the
# phone hangs on a grey screen before printing anything.
ksize=$(gzip -dc "$KOUT/Image.gz" | wc -c)
room=$(( BOOT_DTB_OFFSET - BOOT_KERNEL_OFFSET ))
[ "$ksize" -lt "$room" ] || die "the kernel is $ksize bytes, more than the $room bytes before the device tree"
mkboot boot.img "$BOOT_CMDLINE"
# For bring-up, started with `fastboot boot` (never flashed):
#  - boot-debug.img prints every kernel message on the screen;
#  - boot-rescue.img also stops in the first stage with the USB rescue shell,
#    to read dmesg and the previous boot's log in /sys/fs/pstore.
DEBUG_CMDLINE="$BOOT_CMDLINE loglevel=7 ignore_loglevel"
mkboot boot-debug.img "$DEBUG_CMDLINE"
mkboot boot-rescue.img "$DEBUG_CMDLINE astra.rescue"

# No dtbo.img: the stock overlays target the downstream kernel, and the
# bootloader refuses to boot (back to fastboot) when a valid dtbo table has
# no entry for the board. The flash scripts erase dtbo, which it skips.

# esp.img, for the cache partition, when U-Boot (sm7150-mainline) is
# flashed to boot instead of boot.img: U-Boot starts the same kernel and
# ramdisk from a FAT partition, either \EFI\BOOT\BOOTAA64.EFI (a unified
# kernel image with the command line) or extlinux/extlinux.conf.
log "images: esp.img (for U-Boot)"
esp=$OUT/esp
rm -rf "$esp" && mkdir -p "$esp/EFI/BOOT" "$esp/extlinux" "$esp/dtbs/qcom"
gzip -dc "$KOUT/Image.gz" > "$esp/Image"
cp "$OUT/ramdisk.cpio.gz" "$esp/initramfs"
cp "$KOUT/dts/$KERNEL_DTB" "$esp/dtbs/$KERNEL_DTB"
cat > "$esp/extlinux/extlinux.conf" <<EOF
default astraOS
timeout 1
label astraOS
    kernel /Image
    initrd /initramfs
    fdt /dtbs/$KERNEL_DTB
    append $BOOT_CMDLINE
EOF
if command -v ukify >/dev/null; then
    ukify build --linux "$esp/Image" --initrd "$esp/initramfs" --cmdline "$BOOT_CMDLINE" \
        --uname "$(kernel_release)" --output "$esp/EFI/BOOT/BOOTAA64.EFI" >/dev/null
else
    warn "ukify missing: esp.img only has extlinux.conf"
fi
esp_mb=$(( $(du -sm "$esp" | cut -f1) + 16 ))
rm -f "$IMAGES/esp.img"
mkfs.vfat -C -n ASTRABOOT "$IMAGES/esp.img" $(( esp_mb * 1024 )) >/dev/null
mcopy -s -i "$IMAGES/esp.img" "$esp"/* ::/

log "images: vbmeta.img (verification disabled)"
avbtool make_vbmeta_image --flags 3 --padding_size 4096 --output "$IMAGES/vbmeta.img"

log "images: super.img"
args=(--metadata-size "$SUPER_METADATA_SIZE" --super-name super --metadata-slots "$SUPER_METADATA_SLOTS"
      --device "super:$SUPER_SIZE" --group "$SUPER_GROUP:$SUPER_GROUP_SIZE" --sparse --output "$IMAGES/super.img")
for p in $SUPER_PARTITIONS; do
    args+=(--partition "$p:readonly:$(stat -c %s "$IMAGES/$p.img"):$SUPER_GROUP" --image "$p=$IMAGES/$p.img")
done
lpmake "${args[@]}" >/dev/null

(cd "$IMAGES" && sha256sum boot.img boot-debug.img boot-rescue.img esp.img vbmeta.img super.img > SHA256SUMS)
log "images: done ($IMAGES)"
