#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shared helpers for the build scripts.
set -euo pipefail

DEVICE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../board.conf
source "$DEVICE_DIR/board.conf"

OUT=${OUT:-$DEVICE_DIR/out}
CACHE=${CACHE:-$DEVICE_DIR/cache}
SRC=$CACHE/src
STAGE=$OUT/stage            # Alpine packages as installed by apk
SYSTEM_ROOT=$OUT/system     # contents of system.img (system-as-root)
VENDOR_ROOT=$OUT/vendor     # contents of vendor.img
PRODUCT_ROOT=$OUT/product   # contents of product.img
RAMDISK=$OUT/ramdisk
IMAGES=$OUT/images
JOBS=${JOBS:-$(nproc)}

mkdir -p "$OUT" "$CACHE" "$SRC" "$IMAGES"

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool (run inside the build container, see README)"
    done
}

# git_fetch <url> <ref> <dir>: shallow clone or update a source tree.
git_fetch() {
    local url=$1 ref=$2 dir=$3
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch --depth 1 origin "$ref"
        git -C "$dir" checkout -q FETCH_HEAD
    else
        git clone --depth 1 --branch "$ref" "$url" "$dir"
    fi
}

astra_source() {
    if [ -n "$ASTRA_SRC" ]; then
        echo "$ASTRA_SRC"
    elif [ -d "$DEVICE_DIR/../astra/core/init" ]; then
        # Checked out next to this repository (the usual development setup).
        (cd "$DEVICE_DIR/../astra" && pwd)
    else
        echo "$SRC/astra"
    fi
}

kernel_release() {
    cat "$OUT/kernel/include/config/kernel.release"
}

# Size in MiB of a directory plus headroom, rounded up to 4 MiB.
image_size_mb() {
    local kb
    kb=$(du -sk "$1" | cut -f1)
    echo $(( (kb / 1024 + IMAGE_HEADROOM_MB + kb / 1024 / 8 + 3) / 4 * 4 ))
}
