#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
# The bootloader must be unlocked.
#
#   ./flash-all.sh          update an existing astraOS install (keeps /data)
#   ./flash-all.sh --wipe   first install: also erases userdata (ALL your data)
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
fastboot flash dtbo dtbo.img
fastboot flash boot boot.img
fastboot flash super super.img

if [ "$1" = "--wipe" ]; then
    echo "Erasing userdata and metadata..."
    fastboot erase metadata
    fastboot erase userdata
fi

fastboot reboot
echo "Done. The first boot formats /data and can take a little longer."
