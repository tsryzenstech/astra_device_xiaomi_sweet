#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
# The bootloader must be unlocked.
#
#   ./flash-all.sh          update an existing astraOS install (keeps /data)
#   ./flash-all.sh --wipe   first install: also erases userdata (ALL your data)
#   --stock-boot            start boot.img from the stock bootloader instead of U-Boot
#
# With u-boot.img (sm7150-mainline's U-Boot for sweet) next to this script,
# U-Boot goes to boot and starts astraOS from userdata.img (the start of
# userdata); without it, boot.img is started by the stock bootloader.
set -e
cd "$(dirname "$0")"

command -v fastboot >/dev/null 2>&1 || { echo "fastboot not found (install Android platform-tools)"; exit 1; }

product=$(fastboot getvar product 2>&1 | awk -F': *' '/^product:/ {print $2}')
case "$product" in
    sweet|sweetin) ;;
    *) echo "This build is for the Redmi Note 10 Pro (sweet); connected device reports '$product'."; exit 1 ;;
esac

sha256sum -c SHA256SUMS >/dev/null 2>&1 || { echo "Image checksums do not match, re-download the package."; exit 1; }

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
# The stock overlays do not fit the mainline device tree: erase them.
fastboot erase dtbo
uboot=0
[ -f u-boot.img ] && uboot=1
case " $* " in *" --stock-boot "*) uboot=0 ;; esac
if [ "$uboot" = 1 ]; then
    echo "Flashing U-Boot to boot..."
    fastboot flash boot u-boot.img
else
    fastboot flash boot boot.img
fi
fastboot flash super super.img

wipe=0
case " $* " in *" --wipe "*) wipe=1 ;; esac
# With U-Boot, userdata starts with the EFI partition. --wipe flashes the
# version that also clears where /data starts (the phone formats it on the
# first boot): erasing the whole partition takes longer than USB waits.
if [ "$uboot" = 1 ]; then
    if [ "$wipe" = 1 ]; then
        echo "Erasing metadata, flashing the EFI partition and clearing /data..."
        fastboot erase metadata
        fastboot flash userdata userdata-wipe.img
    else
        echo "Flashing the EFI partition at the start of userdata..."
        fastboot flash userdata userdata.img
    fi
elif [ "$wipe" = 1 ]; then
    echo "Erasing userdata and metadata..."
    fastboot erase metadata
    fastboot erase userdata
fi

fastboot reboot
echo "Done. The first boot formats /data and can take a little longer."
