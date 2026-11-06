#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Flashes the developer version of astraOS on a Redmi Note 10 Pro (sweet) in
# fastboot mode. It erases all the data on the phone. It is the normal system,
# with a root shell on the USB serial port and the kernel log kept in /data/diag.
set -e
cd "$(dirname "$0")"

command -v fastboot >/dev/null 2>&1 || { echo "fastboot not found (install Android platform-tools)"; exit 1; }

product=$(fastboot getvar product 2>&1 | awk -F': *' '/^product:/ {print $2}')
case "$product" in
    sweet|sweetin) ;;
    *) echo "This build is for the Redmi Note 10 Pro (sweet); connected device reports '$product'."; exit 1 ;;
esac

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
fastboot erase dtbo
fastboot flash boot u-boot.img
fastboot flash super super.img
fastboot erase metadata
fastboot flash userdata userdata-diag.img
fastboot reboot
echo
echo "Done. Leave the phone connected."
