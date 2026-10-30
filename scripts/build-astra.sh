#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds the astraOS system code for the device (aarch64, musl).
source "$(dirname "$0")/common.sh"
need cmake ninja

ASRC=$(astra_source)
[ -f "$ASRC/CMakeLists.txt" ] || die "astraOS sources not found at $ASRC"
BUILD=$OUT/astra-build

log "astra: configuring $ASRC"
cmake -S "$ASRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DASTRA_BUILD_TYPE=userdebug \
    -DASTRA_STATIC_INIT=ON \
    -DASTRA_BUILD_TESTS=OFF

log "astra: building"
cmake --build "$BUILD" -j "$JOBS"

rm -rf "$OUT/astra-install"
DESTDIR="$OUT/astra-install" cmake --install "$BUILD" --prefix / >/dev/null

log "astra: installed to $OUT/astra-install"
