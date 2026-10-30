#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
# The bootloader must be unlocked.
#
#   ./flash-all.sh
#
# As postmarketOS installs on this phone: U-Boot goes to boot, and the whole
# system (postmarketOS with astraOS) to userdata. This ERASES EVERYTHING on
# the phone, user data included.
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
echo "Flashing U-Boot to boot..."
fastboot flash boot u-boot.img
echo "Flashing the system to userdata (this takes a few minutes)..."
fastboot flash userdata userdata.img
fastboot reboot
echo "Done. The first boot grows the system to the whole userdata partition."
