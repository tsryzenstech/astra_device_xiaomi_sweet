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
JOBS=${JOBS:-$(nproc)}

mkdir -p "$OUT" "$CACHE" "$SRC" 2>/dev/null || true

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool (see README, Building)"
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

# True inside the Alpine aarch64 build environment (Docker image or chroot).
in_build_env() {
    [ -f /etc/alpine-release ] && [ "$(uname -m)" = aarch64 ]
}
