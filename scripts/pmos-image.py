#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Helpers for the postmarketOS image (scripts/build-pmos.sh), as a normal
user (no mounts):

  pmos-image.py boot-offset <raw image>     byte offset of the boot (first) partition
  pmos-image.py part <raw image> <n>        "<offset> <size>" in bytes of partition n (1, 2)
  pmos-image.py sparse <raw image> <out>    Android sparse image, for fastboot
"""
import struct
import sys

BLOCK = 4096


def partition(path, n):
    """(offset, size) in bytes of the GPT's partition n (from 1), with 4096-
    or 512-byte sectors."""
    with open(path, "rb") as f:
        for ss in (4096, 512):
            f.seek(ss)
            hdr = f.read(92)
            if hdr[:8] != b"EFI PART":
                continue
            entries_lba, = struct.unpack("<Q", hdr[72:80])
            entry_size, = struct.unpack("<I", hdr[84:88])
            f.seek(entries_lba * ss + (n - 1) * entry_size)
            first, last = struct.unpack("<QQ", f.read(entry_size)[32:48])
            return first * ss, (last - first + 1) * ss
    sys.exit("no GPT in " + path)


def boot_offset(path):
    return partition(path, 1)[0]


def sparse(path, out):
    """Raw image -> Android sparse image: zero blocks are left out
    ("don't care"), everything else is stored as raw chunks."""
    chunks = []  # (kind, nblocks, file offset)
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        nblocks = (size + BLOCK - 1) // BLOCK
        f.seek(0)
        zero = bytes(BLOCK)
        run_kind, run_start, run_len = None, 0, 0
        for i in range(nblocks):
            data = f.read(BLOCK)
            kind = "skip" if data.ljust(BLOCK, b"\0") == zero else "raw"
            # Raw chunks of at most 16 MiB: fastboot splits by chunk.
            if kind == run_kind and not (kind == "raw" and run_len >= 4096):
                run_len += 1
                continue
            if run_kind:
                chunks.append((run_kind, run_start, run_len))
            run_kind, run_start, run_len = kind, i, 1
        if run_kind:
            chunks.append((run_kind, run_start, run_len))

        with open(out, "wb") as o:
            o.write(struct.pack("<IHHHHIIII", 0xED26FF3A, 1, 0, 28, 12, BLOCK, nblocks, len(chunks), 0))
            for kind, start, n in chunks:
                if kind == "raw":
                    o.write(struct.pack("<HHII", 0xCAC1, 0, n, 12 + n * BLOCK))
                    f.seek(start * BLOCK)
                    data = f.read(n * BLOCK)
                    o.write(data.ljust(n * BLOCK, b"\0"))
                else:
                    o.write(struct.pack("<HHII", 0xCAC3, 0, n, 12))
    print(f"{out}: {nblocks} blocks, {len(chunks)} chunks")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "boot-offset":
        print(boot_offset(sys.argv[2]))
    elif len(sys.argv) == 4 and sys.argv[1] == "part":
        print(*partition(sys.argv[2], int(sys.argv[3])))
    elif len(sys.argv) == 4 and sys.argv[1] == "sparse":
        sparse(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
