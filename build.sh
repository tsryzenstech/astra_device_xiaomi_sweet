#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds a flashable astraOS for the Xiaomi Redmi Note 10 Pro (sweet).
#
#   ./build.sh [step...]            run inside the build environment
#   ./build.sh --docker [step...]   run the steps inside the Docker build image
#
# Steps (default: all): fetch kernel astra rootfs images package
# Other: clean (removes out/), distclean (also removes cache/)
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--docker" ]; then
    shift
    image=astra-build-sweet
    docker build --platform linux/arm64 -t "$image" .
    mounts=(-v "$PWD:/work/device")
    env=()
    if [ -d ../astra/core/init ]; then
        mounts+=(-v "$(cd ../astra && pwd):/work/astra")
        env+=(-e ASTRA_SRC=/work/astra)
    fi
    exec docker run --rm --platform linux/arm64 "${mounts[@]}" "${env[@]}" \
        -w /work/device "$image" ./build.sh "$@"
fi

steps=("$@")
[ ${#steps[@]} -eq 0 ] && steps=(all)

run() { bash "scripts/$1.sh"; }

for step in "${steps[@]}"; do
    case "$step" in
        all)
            for s in fetch build-kernel build-astra build-rootfs make-images package; do run "$s"; done ;;
        fetch) run fetch ;;
        kernel) run build-kernel ;;
        astra) run build-astra ;;
        rootfs) run build-rootfs ;;
        images) run make-images ;;
        package) run package ;;
        clean) rm -rf out ;;
        distclean) rm -rf out cache ;;
        *) echo "unknown step: $step" >&2; exit 2 ;;
    esac
done
