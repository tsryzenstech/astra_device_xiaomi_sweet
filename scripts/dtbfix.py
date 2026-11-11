#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Corrects the kernel's device tree: two interconnect references, the amplifiers
and the flash LED.

The speaker amplifiers are AW88263S, which is what the tree says, and what no driver
binds to. The aw88261 driver handles them (it knows their chip id, 0x2032) but only
binds to "awinic,aw88261". That name, with one zero more, has the same length.

sm7150.dtsi names endpoints on providers that do not own them, and the number
then means another endpoint of that provider:

  QUP1 (i2c6-i2c11, spi, uart)   &aggre1_noc MASTER_QUP_1   = MASTER_TSIF
  SD card (sdhc_2)               &aggre2_noc MASTER_SDCC_2  = MASTER_CRYPTO_CORE_0

QUP1 therefore never votes for the "QUP0" bus clock manager, which both QUP
wrappers need. It works while the bootloader's votes last, or while QUP0 happens
to be in use. Once all drivers have loaded, sync_state drops those votes, and the
first access to a QUP1 register stops the CPU on the bus: on sweet, the first
touch (the touchscreen is on i2c7) froze the whole phone until the watchdog reset.

The flash LED (the torch) is described for all of Xiaomi's SM7150 phones, and each
of them then turns its controller on, except sweet: "disabled" becomes "okay". The
four bytes that frees become a NOP, which a device tree may hold between properties.

Nothing moves, so the tree keeps its size. Running it twice changes nothing.

  dtbfix.py FILE     corrects the file in place
"""
import struct
import sys

BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9

AGGRE1_NOC = "interconnect@16e0000"
AGGRE2_NOC = "interconnect@1700000"
MASTER_QUP_1 = 2   # in aggre2_noc's numbering; in aggre1_noc's it is MASTER_TSIF
MASTER_SDCC_2 = 4  # in aggre1_noc's numbering; in aggre2_noc's it is MASTER_CRYPTO_CORE_0
QUP1_WRAPPER = "geniqup@ac0000"
SD_CARD = "mmc@8804000"
AMP_OLD = b"awinic,aw88263s\0"
AMP_NEW = b"awinic,aw88261\0\0"
FLASH_LED = "led-controller@d300"
DISABLED = b"disabled\0"
OKAY = b"okay\0"


def properties(blob):
    """Yields (node path, property name, offset of the value, its length)."""
    magic, _, off_struct, off_strings = struct.unpack_from(">IIII", blob, 0)
    if magic != 0xd00dfeed:
        raise ValueError("not a device tree")
    pos, path = off_struct, []
    while True:
        token = struct.unpack_from(">I", blob, pos)[0]
        pos += 4
        if token == BEGIN_NODE:
            end = blob.index(b"\0", pos)
            path.append(blob[pos:end].decode())
            pos = (end + 4) & ~3
        elif token == END_NODE:
            path.pop()
        elif token == PROP:
            length, name_off = struct.unpack_from(">II", blob, pos)
            pos += 8
            name_end = blob.index(b"\0", off_strings + name_off)
            yield "/".join(path), blob[off_strings + name_off:name_end].decode(), pos, length
            pos = (pos + length + 3) & ~3
        elif token == END:
            return
        elif token != NOP:
            raise ValueError("bad token %#x at %#x" % (token, pos - 4))


def provider_phandles(blob):
    found = {}
    for path, name, off, length in properties(blob):
        node = path.rsplit("/", 1)[-1]
        if name == "phandle" and length == 4 and node in (AGGRE1_NOC, AGGRE2_NOC):
            found[node] = struct.unpack_from(">I", blob, off)[0]
    if len(found) != 2:
        raise ValueError("the interconnect providers are not in this device tree")
    return found[AGGRE1_NOC], found[AGGRE2_NOC]


def references(blob):
    """Yields (node path, offset of the provider cell, provider, endpoint)."""
    for path, name, off, length in properties(blob):
        if name == "interconnects":
            # #interconnect-cells = <2>: provider, endpoint, tag.
            for cell in range(off, off + length - 8, 12):
                provider, endpoint = struct.unpack_from(">II", blob, cell)
                yield path, cell, provider, endpoint


def wrong(blob):
    """The references to correct: (node path, offset of provider cell, right provider)."""
    aggre1, aggre2 = provider_phandles(blob)
    out = []
    for path, cell, provider, endpoint in references(blob):
        parts = path.split("/")
        if QUP1_WRAPPER in parts and provider == aggre1 and endpoint == MASTER_QUP_1:
            out.append((path, cell, aggre2))
        elif SD_CARD in parts and provider == aggre2 and endpoint == MASTER_SDCC_2:
            out.append((path, cell, aggre1))
    return out


def qup1_votes(blob):
    """How many QUP1 references name the right endpoint of the right provider."""
    _, aggre2 = provider_phandles(blob)
    return sum(1 for path, _, provider, endpoint in references(blob)
               if QUP1_WRAPPER in path.split("/") and provider == aggre2 and endpoint == MASTER_QUP_1)


def amplifiers(blob):
    """Offsets of the amplifiers' compatible strings, and how many are already right."""
    old, right = [], 0
    for _, name, off, length in properties(blob):
        if name == "compatible":
            value = bytes(blob[off:off + length])
            if value == AMP_OLD:
                old.append(off)
            elif value == AMP_NEW:
                right += 1
    return old, right


def flash_led(blob):
    """The flash LED controller's status: (offset of its value, the value), or None."""
    for path, name, off, length in properties(blob):
        if name == "status" and path.rsplit("/", 1)[-1] == FLASH_LED:
            return off, bytes(blob[off:off + length])
    return None


def enable_flash_led(blob):
    """Turns the flash LED controller on. True when the tree changed."""
    found = flash_led(blob)
    if not found or found[1] != DISABLED:
        return False
    off = found[0]
    # A property is its length, its name and its value padded to four bytes:
    # 9 bytes took 12, 5 take 8, and a NOP stands where the last four were.
    struct.pack_into(">I", blob, off - 8, len(OKAY))
    blob[off:off + 8] = OKAY.ljust(8, b"\0")
    struct.pack_into(">I", blob, off + 8, NOP)
    return True


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        original = f.read()
    blob = bytearray(original)
    fixes = wrong(blob)
    for _, cell, provider in fixes:
        struct.pack_into(">I", blob, cell, provider)
    for off in amplifiers(blob)[0]:
        blob[off:off + len(AMP_NEW)] = AMP_NEW
    enable_flash_led(blob)
    old, right = amplifiers(blob)
    flash = flash_led(blob)
    if wrong(blob) or not qup1_votes(blob) or old or not right or not flash or flash[1] != OKAY:
        sys.exit("dtbfix: the device tree is not as expected")
    if blob != original:
        with open(sys.argv[1], "wb") as f:
            f.write(blob)
    print("dtbfix: %d references corrected, %d QUP1 references right, %d amplifiers, the flash LED on"
          % (len(fixes), qup1_votes(blob), right))


if __name__ == "__main__":
    main()
