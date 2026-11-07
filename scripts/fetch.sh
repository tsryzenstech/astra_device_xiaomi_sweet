#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Downloads the sources: astraOS, the SM7150 mainline kernel and the device firmware.
source "$(dirname "$0")/common.sh"
need git

if [ -z "$ASTRA_SRC" ] && [ ! -d "$DEVICE_DIR/../astra/core/init" ]; then
    log "astraOS: $ASTRA_REPO ($ASTRA_REF)"
    git_fetch "$ASTRA_REPO" "$ASTRA_REF" "$SRC/astra"
else
    log "astraOS: using local checkout $(astra_source)"
fi

if [ "$KERNEL_SOURCE" = source ]; then
    log "kernel: $KERNEL_REPO ($KERNEL_REF)"
    git_fetch "$KERNEL_REPO" "$KERNEL_REF" "$SRC/linux"
else
    log "kernel: $KERNEL_PACKAGE"
fi

log "firmware: $FIRMWARE_REPO ($FIRMWARE_REF)"
git_fetch "$FIRMWARE_REPO" "$FIRMWARE_REF" "$SRC/firmware"

log "amplifier calibration"
need curl sha256sum
if ! echo "$AW_ACF_SHA256  $SRC/aw88261_acf.bin" | sha256sum -c --status 2>/dev/null; then
    curl -fsSL "$AW_ACF_URL" -o "$SRC/aw88261_acf.bin" || die "cannot download the amplifiers' calibration file"
    echo "$AW_ACF_SHA256  $SRC/aw88261_acf.bin" | sha256sum -c --status || die "the amplifiers' calibration file does not match its checksum"
fi
