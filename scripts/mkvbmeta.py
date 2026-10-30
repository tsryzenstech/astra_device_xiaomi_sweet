#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Writes an empty, unsigned vbmeta image with verification disabled
(what `avbtool make_vbmeta_image --flags 3 --padding_size 4096` makes), so
the stock bootloader starts U-Boot.

  mkvbmeta.py <output>
"""
import struct
import sys

FLAGS = 3  # HASHTREE_DISABLED | VERIFICATION_DISABLED

header = struct.pack(
    ">4sIIQQIQQQQQQQQQQQII48s80s",
    b"AVB0",
    1, 0,          # required libavb version 1.0
    0, 0,          # authentication / auxiliary data block sizes
    0,             # algorithm: NONE
    0, 0, 0, 0,    # hash offset/size, signature offset/size
    0, 0, 0, 0,    # public key offset/size, public key metadata offset/size
    0, 0,          # descriptors offset/size
    0,             # rollback index
    FLAGS,
    0,             # rollback index location
    b"avbtool 1.3.0",
    b"",
)
assert len(header) == 256
with open(sys.argv[1], "wb") as f:
    f.write(header.ljust(4096, b"\0"))
