#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Downloads the astraOS sources (the kernel, firmware and the rest of the
# system come from postmarketOS in the pmos step).
source "$(dirname "$0")/common.sh"
need git

if [ -z "$ASTRA_SRC" ] && [ ! -d "$DEVICE_DIR/../astra/core/init" ]; then
    log "astraOS: $ASTRA_REPO ($ASTRA_REF)"
    git_fetch "$ASTRA_REPO" "$ASTRA_REF" "$SRC/astra"
else
    log "astraOS: using local checkout $(astra_source)"
fi
