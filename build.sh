#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds a flashable astraOS for the Xiaomi Redmi Note 10 Pro (sweet).
#
#   ./build.sh [step...]            in the Alpine chroot of scripts/chroot.sh
#                                   (asks for sudo)
#   ./build.sh --docker [step...]   in the Docker build image
#
# Steps (default: all): fetch kernel uboot astra llama qcom rootfs images verify package
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
[ "${steps[0]}" = all ] && steps=(fetch kernel uboot astra llama qcom rootfs images verify package)

case "${steps[0]}" in
    clean) rm -rf out 2>/dev/null || sudo rm -rf out; exit 0 ;;
    distclean) rm -rf out cache 2>/dev/null || sudo rm -rf out cache; exit 0 ;;
esac

# Everything runs in Alpine aarch64, the libraries the phone gets.
if ! in_build_env; then
    if [ "$docker" = 1 ]; then
        image=astra-build-sweet
        docker build --platform linux/arm64 -t "$image" .
        mounts=(-v "$PWD:/work/device")
        env=(-e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" -e "ASTRA_VERSION_SUFFIX=${ASTRA_VERSION_SUFFIX:-}"
             -e "GITHUB_ACTIONS=${GITHUB_ACTIONS:-}")
        if [ -d ../astra/core/init ]; then
            mounts+=(-v "$(cd ../astra && pwd):/work/astra")
            env+=(-e ASTRA_SRC=/work/astra)
        fi
        exec docker run --rm --platform linux/arm64 "${mounts[@]}" "${env[@]}" -w /work/device "$image" \
            sh -c './build.sh "$@"; s=$?; chown -R "$HOST_UID:$HOST_GID" out cache; exit $s' build "${steps[@]}"
    fi
    exec sudo scripts/chroot.sh build "${steps[@]}"
fi

run() { bash "scripts/$1.sh"; }

for step in "${steps[@]}"; do
    case "$step" in
        fetch) run fetch ;;
        kernel) run build-kernel ;;
        uboot) run build-uboot ;;
        astra) run build-astra ;;
        llama) run build-llama ;;
        qcom) run build-qcom-tools ;;
        rootfs) run build-rootfs ;;
        images) run make-images ;;
        verify) run verify ;;
        package) run package ;;
        *) die "unknown step: $step" ;;
    esac
done
