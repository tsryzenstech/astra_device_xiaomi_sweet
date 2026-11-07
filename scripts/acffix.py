#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Sets the speaker amplifiers' I2S format in their calibration file to the one the
sound card sends.

The calibration (from the stock ROM) puts the AW88263S amplifiers in 32 bit slots at
64 fs, which is what the stock audio stack sent them. Mainline's sm8250 sound card
drives the primary MI2S bit clock at a fixed 1.536 MHz: 32 fs, 16 bit slots. With the
calibration's format the amplifier locks its PLL on that clock but reads the data
wrong: it never switches on (status 0x0011 instead of 0x0311) and the speaker is
silent. Tried on the phone: with I2SCTRL (0x06) set to 16 bit at 32 fs the amplifiers
start and the speaker plays.

I2SCTRL (0x06) changes in every profile: I2SFS and I2SBCK (bits 7:4), and CHSEL
(bits 11:10) to the mix of both channels, as on the phone when it played: the card
links one amplifier, which must play whatever the stream has.

The aw88261 driver also, after each start, "force sets" bits of 0x62 and 0x64-0x68,
which are boost registers of the AW88261 and not those of this chip: the boost stops
and the amplifier with it (status 0x0000 while playing). It does so only when the two
efuse registers it reads (0x79, 0x7d) combine to zero, and they are combined with AND
unless the calibration sets 0x14 with bit 3. Here they are 0xfc00 and 0x0000: zero with
AND, not with OR. So each profile's 0x50 entry, which the driver always skips (it
writes its own VSNTM1 there), becomes 0x14 = 0x0008. On this chip 0x14 is PVDD,
read-only. Tried on the phone: with only those boost registers restored, the
amplifier runs.

Everything else stays as calibrated. The checksums the driver checks are made again.
Running it twice changes nothing.

  acffix.py FILE      corrects the file in place
"""
import struct
import sys

ACF_ID = 0x0A15F908
I2SCTRL = 0x06
FORMAT_MASK = 0x0CF0       # CHSEL (11:10), I2SFS (7:6) and I2SBCK (5:4)
FORMAT_16BIT_32FS = 0x0C00 # both channels mixed, 16 bit, 32 fs
# The file fetch.sh downloads (AW_ACF_SHA256), corrected: what the phone played with.
FIXED_SHA256 = "febb32de4a8446883421580930e346f853d47b78afeec57a470596970945bb5f"
SKIPPED = 0x50             # VSNTM1: the driver never writes the file's value; replaced by...
OR_CHECK = (0x14, 0x0008)  # ...the driver's DBGCTRL with EF_DBMD: its efuse check by OR


def crc8(data):
    """The kernel's crc8 with aw88395's table: crc8_populate_lsb(..., 0x8C), start 0."""
    table = []
    for i in range(256):
        c = i
        for _ in range(8):
            c = (c >> 1) ^ 0x8C if c & 1 else c >> 1
        table.append(c)
    crc = 0
    for b in data:
        crc = table[(crc ^ b) & 0xFF]
    return crc


def entries(blob):
    """(offset of the entry, offset of its data, data size) for each profile."""
    ident, = struct.unpack_from("<I", blob, 0)
    if ident != ACF_ID:
        raise ValueError("not an Awinic calibration file")
    ddt_size, ddt_num, hdr_off, _ = struct.unpack_from("<4I", blob, 52)
    each = ddt_size // ddt_num
    for i in range(ddt_num):
        e = hdr_off + i * each
        size, off = struct.unpack_from("<II", blob, e + 32)
        yield e, off, size


def registers(blob, off, size):
    """(offset of each register's value, register, value) in one profile's data.

    The data starts with the number of registers, 32 bit, then pairs of 16 bit."""
    length, = struct.unpack_from("<I", blob, off + 16)
    start = off + size - length
    count, = struct.unpack_from("<I", blob, start)
    if 4 + 4 * count != length:
        raise ValueError("a profile's register count does not match its length")
    for p in range(start + 4, start + length - 3, 4):
        reg, val = struct.unpack_from("<HH", blob, p)
        yield p + 2, reg & 0xFF, val


def formats(blob):
    return [val & FORMAT_MASK for e, off, size in entries(blob)
            for _, reg, val in registers(blob, off, size) if reg == I2SCTRL]


def or_checks(blob):
    return sum(1 for e, off, size in entries(blob)
               for _, reg, val in registers(blob, off, size) if (reg, val) == OR_CHECK)


def fix(blob):
    for e, off, size in entries(blob):
        for at, reg, val in registers(blob, off, size):
            if reg == I2SCTRL:
                struct.pack_into("<H", blob, at, (val & ~FORMAT_MASK) | FORMAT_16BIT_32FS)
            elif reg == SKIPPED:
                # The register's half keeps its high byte, as the file has it.
                old, = struct.unpack_from("<H", blob, at - 2)
                struct.pack_into("<HH", blob, at - 2, (old & 0xFF00) | OR_CHECK[0], OR_CHECK[1])
        # The bin's own sum: every byte after the sum itself, header and data.
        struct.pack_into("<I", blob, off, sum(blob[off + 4:off + size]))
        # The entry's crc of its whole data.
        struct.pack_into("<I", blob, e + 40, crc8(blob[off:off + size]))


def valid(blob):
    for e, off, size in entries(blob):
        if struct.unpack_from("<I", blob, off)[0] != sum(blob[off + 4:off + size]):
            return False
        if struct.unpack_from("<I", blob, e + 40)[0] != crc8(blob[off:off + size]):
            return False
    return True


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        original = f.read()
    if not valid(original):
        sys.exit("acffix: the file's checksums do not match its contents")
    blob = bytearray(original)
    fix(blob)
    found = formats(blob)
    if not found or any(f != FORMAT_16BIT_32FS for f in found) or or_checks(blob) != len(found) or not valid(blob):
        sys.exit("acffix: the file is not as expected")
    if blob != original:
        with open(sys.argv[1], "wb") as f:
            f.write(blob)
    print("acffix: %d profiles at 16 bit, 32 fs, both channels, efuse check by OR" % len(found))


if __name__ == "__main__":
    main()
