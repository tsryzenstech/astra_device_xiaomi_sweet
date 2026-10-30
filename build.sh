#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds a flashable astraOS for the Xiaomi Redmi Note 10 Pro (sweet):
# postmarketOS (now named Nura) with astraOS on it.
#
#   ./build.sh [step...]            run as your user (asks for sudo when needed)
#   ./build.sh --docker [step...]   the Alpine steps in the Docker build image
#
# Steps (default: all): fetch uboot astra llama pmos package
#   fetch uboot astra llama   in the Alpine aarch64 build environment (the
#                             chroot of scripts/chroot.sh, or Docker)
#   pmos package              on the build machine as your user (pmbootstrap)
# Other: clean (removes out/), distclean (also removes cache/)
set -euo pipefail
cd "$(dirname "$0")"
source scripts/common.sh

docker=0
if [ "${1:-}" = "--docker" ]; then
    docker=1
    shift
fi
steps=("$@")
[ ${#steps[@]} -eq 0 ] && steps=(all)
[ "${steps[0]}" = all ] && steps=(fetch uboot astra llama pmos package)

run() { bash "scripts/$1.sh"; }

# Steps that build for the phone run in Alpine aarch64 (same libraries as
# postmarketOS): here when already inside it, else in Docker or the chroot.
alpine_steps() {
    [ $# -eq 0 ] && return 0
    if in_build_env; then
        for s in "$@"; do
            case "$s" in
                uboot) run build-uboot ;;
                astra) run build-astra ;;
                llama) run build-llama ;;
                *) run "$s" ;;
            esac
        done
    elif [ "$docker" = 1 ]; then
        image=astra-build-sweet
        docker build --platform linux/arm64 -t "$image" .
        mounts=(-v "$PWD:/work/device")
        env=(-e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)")
        if [ -d ../astra/core/init ]; then
            mounts+=(-v "$(cd ../astra && pwd):/work/astra")
            env+=(-e ASTRA_SRC=/work/astra)
        fi
        docker run --rm --platform linux/arm64 "${mounts[@]}" "${env[@]}" -w /work/device "$image" \
            sh -c './build.sh "$@"; s=$?; chown -R "$HOST_UID:$HOST_GID" out cache; exit $s' build "$@"
    else
        sudo scripts/chroot.sh build "$@"
    fi
}

pending=()
for step in "${steps[@]}"; do
    case "$step" in
        fetch|uboot|astra|llama) pending+=("$step") ;;
        pmos|package)
            alpine_steps "${pending[@]}"
            pending=()
            if in_build_env; then
                die "the $step step runs on the build machine, not in the build environment"
            elif [ "$step" = pmos ]; then
                run build-pmos
            else
                run package
            fi ;;
        clean) rm -rf out 2>/dev/null || sudo rm -rf out ;;
        distclean) rm -rf out cache 2>/dev/null || sudo rm -rf out cache ;;
        *) echo "unknown step: $step" >&2; exit 2 ;;
    esac
done
alpine_steps "${pending[@]}"
