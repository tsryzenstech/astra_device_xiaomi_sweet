#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds llama.cpp's llama-server for Cloudy, the on-device assistant: astrad
# starts it on 127.0.0.1 with the model the user downloaded in Cloudy.
source "$(dirname "$0")/common.sh"
need cmake ninja git

LLAMA_TAG=${LLAMA_TAG:-b11418}      # a llama.cpp release tag (github.com/ggml-org/llama.cpp/releases)
src="$SRC/llama.cpp"
if [ ! -d "$src/.git" ]; then
    log "llama.cpp: fetching $LLAMA_TAG"
    git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$src"
fi
build="$OUT/llama-build"
log "llama.cpp: building llama-server (Cortex-A76/A55: armv8.2-a with dotprod)"
cmake -S "$src" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=ON
cmake --build "$build" --target llama-server -j "$JOBS"
mkdir -p "$OUT/astra-install/system/bin"
install -m 0755 "$build/bin/llama-server" "$OUT/astra-install/system/bin/llama-server"
log "llama.cpp: installed system/bin/llama-server"
