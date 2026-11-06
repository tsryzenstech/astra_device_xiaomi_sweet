#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds what brings the modem up, and Wi-Fi with it, which Alpine does not
# package: rmtfs (the modem's file systems) and tqftpserv (its firmware files).
source "$(dirname "$0")/common.sh"
need git gcc make

log "rmtfs: $RMTFS_REPO ($RMTFS_REF)"
git_fetch "$RMTFS_REPO" "$RMTFS_REF" "$SRC/rmtfs"
# The generated QMI code is in the repository: qmic is not needed.
touch "$SRC/rmtfs"/qmi_rmtfs.c "$SRC/rmtfs"/qmi_rmtfs.h
make -C "$SRC/rmtfs" -j"$JOBS" rmtfs

log "tqftpserv: $TQFTPSERV_REPO ($TQFTPSERV_REF)"
git_fetch "$TQFTPSERV_REPO" "$TQFTPSERV_REF" "$SRC/tqftpserv"
(
    cd "$SRC/tqftpserv"
    gcc -O2 -Wall -DHAVE_XZ -DHAVE_ZSTD -o tqftpserv translate.c tqftpserv.c xz-decompress.c zstd-decompress.c \
        -lqrtr -llzma -lzstd
)

rm -rf "$OUT/qcom-install"
mkdir -p "$OUT/qcom-install/system/bin"
install -m 0755 "$SRC/rmtfs/rmtfs" "$SRC/tqftpserv/tqftpserv" "$OUT/qcom-install/system/bin/"
log "qcom tools: installed rmtfs and tqftpserv"
