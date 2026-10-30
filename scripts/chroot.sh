#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Runs build steps inside an Alpine aarch64 chroot, for hosts without Docker
# (e.g. WSL). Needs root; on non-arm64 hosts also qemu-user-static + binfmt.
#
#   sudo scripts/chroot.sh setup              create cache/chroot
#   sudo scripts/chroot.sh build [steps...]   run ./build.sh inside it
#   sudo scripts/chroot.sh shell              interactive shell
#
# Tip: the kernel builds much faster cross-compiled on the host:
#   CROSS_COMPILE=aarch64-linux-gnu- ./build.sh kernel
set -euo pipefail
DEVICE_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$DEVICE_DIR/board.conf"
ROOT=$DEVICE_DIR/cache/chroot

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

setup() {
    local arch mirror tmp index apk
    arch=$(uname -m)
    mirror="$ALPINE_MIRROR/$ALPINE_BRANCH"
    tmp=$(mktemp -d)
    index=$(curl -fsSL "$mirror/main/$arch/")
    apk=$(echo "$index" | grep -o 'apk-tools-static-[^"]*\.apk' | head -1)
    curl -fsSL "$mirror/main/$arch/$apk" | tar -xz -C "$tmp" 2>/dev/null
    mkdir -p "$ROOT"
    "$tmp/sbin/apk.static" --arch aarch64 --root "$ROOT" --initdb --allow-untrusted -U \
        -X "$mirror/main" -X "$mirror/community" \
        add alpine-base $(grep -v '^#' "$DEVICE_DIR/scripts/build-deps.txt")
    printf '%s\n' "$mirror/main" "$mirror/community" > "$ROOT/etc/apk/repositories"
    ln -sf /usr/bin/samu "$ROOT/usr/bin/ninja"
    cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
    rm -rf "$tmp"
    echo "chroot ready: $ROOT"
}

enter() {
    local astra
    mkdir -p "$ROOT/work/device" "$ROOT/work/astra"
    for fs in proc sys dev; do
        mountpoint -q "$ROOT/$fs" || mount --rbind "/$fs" "$ROOT/$fs"
    done
    mountpoint -q "$ROOT/work/device" || mount --bind "$DEVICE_DIR" "$ROOT/work/device"
    astra=${ASTRA_SRC:-$DEVICE_DIR/../astra}
    [ -d "$astra/core/init" ] && { mountpoint -q "$ROOT/work/astra" || mount --bind "$astra" "$ROOT/work/astra"; }
    trap 'umount -R "$ROOT/work/device" "$ROOT/work/astra" "$ROOT/proc" "$ROOT/sys" "$ROOT/dev" 2>/dev/null || true' EXIT
    # Older builds copied astraOS init over the chroot's /bin/busybox (and
    # so /bin/sh): put busybox back.
    if ! "$ROOT/bin/busybox" --help 2>&1 | grep -q BusyBox; then
        echo "chroot: repairing /bin/busybox"
        chroot "$ROOT" /sbin/apk fix --reinstall busybox >/dev/null 2>&1 || true
        "$ROOT/bin/busybox" --help 2>&1 | grep -q BusyBox || echo "chroot: could not repair busybox, run: sudo scripts/chroot.sh setup" >&2
    fi
    # Build dependencies added since the chroot was set up.
    chroot "$ROOT" /sbin/apk add --quiet $(grep -v '^#' "$DEVICE_DIR/scripts/build-deps.txt") >/dev/null 2>&1 ||
        echo "chroot: could not update the build dependencies (offline?)" >&2
    chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin TERM="${TERM:-xterm}" \
        ASTRA_SRC=$( [ -d "$ROOT/work/astra/core" ] && echo /work/astra ) JOBS="${JOBS:-$(nproc)}" "$@"
}

case "${1:-}" in
    setup) setup ;;
    build) shift; enter /bin/bash -c "cd /work/device && ./build.sh $*" ;;
    shell) enter /bin/bash -l ;;
    *) sed -n '3,14p' "$0"; exit 2 ;;
esac
