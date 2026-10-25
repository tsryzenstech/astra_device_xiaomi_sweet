#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Writes an empty Android DTBO image (dt_table_header with zero entries)."""
import struct
import sys

DT_TABLE_MAGIC = 0xD7B7AB1E
HEADER_SIZE = 32
ENTRY_SIZE = 32
PAGE_SIZE = 4096


def main(path):
    # magic, total_size, header_size, dt_entry_size, dt_entry_count,
    # dt_entries_offset, page_size, version (all big endian)
    header = struct.pack(">8I", DT_TABLE_MAGIC, HEADER_SIZE, HEADER_SIZE, ENTRY_SIZE, 0, HEADER_SIZE, PAGE_SIZE, 0)
    with open(path, "wb") as f:
        f.write(header.ljust(PAGE_SIZE, b"\0"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: empty_dtbo.py <output>")
    main(sys.argv[1])
