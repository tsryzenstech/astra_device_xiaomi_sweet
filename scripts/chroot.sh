#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Runs build steps inside an Alpine aarch64 chroot, for hosts without Docker
# (e.g. WSL). Needs root; on non-arm64 hosts also qemu-user-static + binfmt.
# build.sh calls it for the Alpine steps (fetch uboot astra llama).
#
#   sudo scripts/chroot.sh setup              create cache/chroot (again)
#   sudo scripts/chroot.sh build [steps...]   run ./build.sh inside it
#   sudo scripts/chroot.sh shell              interactive shell
#
# The chroot follows ALPINE_BRANCH (the Alpine release postmarketOS is
# based on): one of another release is made again.
set -euo pipefail
DEVICE_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$DEVICE_DIR/board.conf"
ROOT=$DEVICE_DIR/cache/chroot

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

# Mounts inside the chroot, deepest first.
chroot_mounts() {
    awk -v root="$ROOT/" 'index($2, root) == 1 { print $2 }' /proc/mounts | sort -r
}

unmount() {
    local m
    # Slaves first: unmounting the chroot's copies of /dev, /proc and /sys
    # must not propagate to the real ones.
    for m in proc sys dev; do
        mountpoint -q "$ROOT/$m" && mount --make-rslave "$ROOT/$m" 2>/dev/null
    done
    # Everything left inside the chroot (also from earlier, interrupted
    # builds); lazily, so a busy one does not stay behind.
    chroot_mounts | while read -r m; do
        umount -l "$m" 2>/dev/null || true
    done
}

# The chroot exists and runs the Alpine release of ALPINE_BRANCH.
current() {
    [ -f "$ROOT/etc/alpine-release" ] && [ "$(cut -d. -f1,2 "$ROOT/etc/alpine-release")" = "${ALPINE_BRANCH#v}" ]
}

setup() {
    local arch mirror tmp index apk
    if [ -d "$ROOT" ]; then
        echo "chroot: replacing $ROOT (Alpine $(cat "$ROOT/etc/alpine-release" 2>/dev/null || echo ?), building needs $ALPINE_BRANCH)"
        unmount
        # Never delete through a mount that is still there.
        if [ -n "$(chroot_mounts)" ]; then
            echo "chroot: these mounts inside $ROOT could not be removed:" >&2
            chroot_mounts >&2
            exit 1
        fi
        rm -rf "$ROOT"
    fi
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
        mountpoint -q "$ROOT/$fs" || { mount --rbind "/$fs" "$ROOT/$fs" && mount --make-rslave "$ROOT/$fs"; }
    done
    mountpoint -q "$ROOT/work/device" || mount --bind "$DEVICE_DIR" "$ROOT/work/device"
    astra=${ASTRA_SRC:-$DEVICE_DIR/../astra}
    [ -d "$astra/core/init" ] && { mountpoint -q "$ROOT/work/astra" || mount --bind "$astra" "$ROOT/work/astra"; }
    # Unmount, and give the build output back to the user who ran sudo
    # (the pmos and package steps run as that user).
    trap 'unmount; [ -n "${SUDO_UID:-}" ] && chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$DEVICE_DIR/out" "$DEVICE_DIR/cache/src" 2>/dev/null; true' EXIT
    # Build dependencies added since the chroot was set up.
    chroot "$ROOT" /sbin/apk add --quiet $(grep -v '^#' "$DEVICE_DIR/scripts/build-deps.txt") >/dev/null 2>&1 ||
        echo "chroot: could not update the build dependencies (offline?)" >&2
    # The source trees belong to the user who runs the build, not to root:
    # git must still work in them (safe.directory).
    chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin TERM="${TERM:-xterm}" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' \
        ASTRA_VERSION_SUFFIX="${ASTRA_VERSION_SUFFIX:-}" \
        ASTRA_SRC=$( [ -d "$ROOT/work/astra/core" ] && echo /work/astra ) JOBS="${JOBS:-$(nproc)}" "$@"
}

case "${1:-}" in
    setup) setup ;;
    build) shift; current || setup; enter /bin/bash -c "cd /work/device && ./build.sh $*" ;;
    shell) enter /bin/bash -l ;;
    *) sed -n '3,14p' "$0"; exit 2 ;;
esac
