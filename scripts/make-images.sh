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

# userdata.img, for booting through U-Boot (sm7150-mainline's, flashed to
# boot instead of boot.img, as postmarketOS does on SM7150 phones). U-Boot
# maps the userdata partition as a disk and starts \EFI\BOOT\BOOTAA64.EFI
# from its EFI partition: a unified kernel image with the same kernel,
# ramdisk and command line as boot.img. GPT and FAT use the storage's 4096
# byte sectors, or U-Boot ignores them. init maps what follows as /data.
log "images: userdata.img (for U-Boot)"
need ukify mkfs.vfat mcopy
esp=$OUT/esp
rm -rf "$esp" && mkdir -p "$esp/EFI/BOOT" "$esp/dtb/$(dirname "$KERNEL_DTB")"
# U-Boot passes Linux the device tree it finds in /dtb/<fdtfile> on the EFI
# partition (fdtfile = qcom/sm7150-xiaomi-sweet.dtb), else its own, built
# from other sources: the kernel's own device tree must be there.
cp "$KOUT/dts/$KERNEL_DTB" "$esp/dtb/$KERNEL_DTB"
gzip -dc "$KOUT/Image.gz" > "$OUT/Image"
ukify build --linux "$OUT/Image" --initrd "$OUT/ramdisk.cpio.gz" --cmdline "$BOOT_CMDLINE" \
    --uname "$(kernel_release)" --output "$esp/EFI/BOOT/BOOTAA64.EFI" >/dev/null
rm -f "$OUT/esp.fat"
mkfs.vfat -C -S "$STORAGE_SECTOR_SIZE" -s 1 -F 16 -n ASTRAESP "$OUT/esp.fat" $(( 64 * 1024 )) >/dev/null
mcopy -s -i "$OUT/esp.fat" "$esp"/* ::/
python3 "$DEVICE_DIR/scripts/mkuserdata.py" "$OUT/esp.fat" "$IMAGES/userdata.img" "$STORAGE_SECTOR_SIZE"
# userdata-wipe.img (flash-all --wipe): one more MiB of zeros clears the old
# filesystem's signature where /data starts, so init formats /data. Erasing
# the whole of userdata instead takes longer than fastboot over USB waits.
cp "$IMAGES/userdata.img" "$IMAGES/userdata-wipe.img"
truncate -s +1M "$IMAGES/userdata-wipe.img"
rm -f "$IMAGES/esp.img"

log "images: vbmeta.img (verification disabled)"
avbtool make_vbmeta_image --flags 3 --padding_size 4096 --output "$IMAGES/vbmeta.img"

log "images: super.img"
args=(--metadata-size "$SUPER_METADATA_SIZE" --super-name super --metadata-slots "$SUPER_METADATA_SLOTS"
      --device "super:$SUPER_SIZE" --group "$SUPER_GROUP:$SUPER_GROUP_SIZE" --sparse --output "$IMAGES/super.img")
for p in $SUPER_PARTITIONS; do
    args+=(--partition "$p:readonly:$(stat -c %s "$IMAGES/$p.img"):$SUPER_GROUP" --image "$p=$IMAGES/$p.img")
done
lpmake "${args[@]}" >/dev/null

(cd "$IMAGES" && sha256sum boot.img boot-debug.img boot-rescue.img userdata.img userdata-wipe.img vbmeta.img super.img > SHA256SUMS)
log "images: done ($IMAGES)"
