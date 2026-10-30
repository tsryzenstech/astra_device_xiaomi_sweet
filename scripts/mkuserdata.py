#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Builds userdata.img for booting through U-Boot.

sm7150-mainline's U-Boot maps the userdata partition as a disk and starts the
EFI application it finds there (bootefi bootmgr). userdata.img is the start of
that disk: a GPT whose only partition, "astra_esp", is the EFI system
partition, filled from a FAT image. Everything after the first 128 MiB stays
free: astraOS init maps it as /data.

  mkuserdata.py <esp.fat> <userdata.img> [sector size]

The sector size must be the one of the storage (4096 on UFS): U-Boot only
reads a GPT and a FAT whose sectors match the disk's.
"""
import struct
import sys
import uuid
import zlib

RESERVED = 128 << 20                # bytes before /data
ESP_START = 1 << 20
ESP_TYPE = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b")
ENTRIES, ENTRY_SIZE = 128, 128


def header(sector, my_lba, alt_lba, first, last, entries_lba, disk_guid, entries_crc):
    h = struct.pack("<8sIIIIQQQQ16sQIII", b"EFI PART", 0x00010000, 92, 0, 0,
                    my_lba, alt_lba, first, last, disk_guid.bytes_le,
                    entries_lba, ENTRIES, ENTRY_SIZE, entries_crc)
    h = h[:16] + struct.pack("<I", zlib.crc32(h)) + h[20:]
    return h.ljust(sector, b"\0")


def main():
    esp_path, out_path = sys.argv[1], sys.argv[2]
    sector = int(sys.argv[3]) if len(sys.argv) > 3 else 4096
    esp = open(esp_path, "rb").read()
    if ESP_START + len(esp) > RESERVED - (1 << 20):
        sys.exit("the EFI partition does not fit in the reserved space")
    total = RESERVED // sector
    entry_lbas = ENTRIES * ENTRY_SIZE // sector or 1
    first_usable, last_usable = 2 + entry_lbas, total - 2 - entry_lbas
    esp_first = ESP_START // sector
    esp_last = esp_first + len(esp) // sector - 1

    # Fixed GUIDs keep the image reproducible.
    disk_guid = uuid.uuid5(uuid.NAMESPACE_URL, "astraos:userdata")
    part_guid = uuid.uuid5(uuid.NAMESPACE_URL, "astraos:astra_esp")
    entry = struct.pack("<16s16sQQQ72s", ESP_TYPE.bytes_le, part_guid.bytes_le,
                        esp_first, esp_last, 0, "astra_esp".encode("utf-16-le"))
    entries = entry.ljust(ENTRIES * ENTRY_SIZE, b"\0")
    crc = zlib.crc32(entries)

    img = bytearray(RESERVED)
    # Protective MBR
    size_lba = min(total - 1, 0xFFFFFFFF)
    img[446:462] = struct.pack("<B3sB3sII", 0, b"\x00\x02\x00", 0xEE, b"\xff\xff\xff", 1, size_lba)
    img[510:512] = b"\x55\xaa"
    img[sector:2 * sector] = header(sector, 1, total - 1, first_usable, last_usable, 2, disk_guid, crc)
    img[2 * sector:2 * sector + len(entries)] = entries
    img[ESP_START:ESP_START + len(esp)] = esp
    back_entries = total - 1 - entry_lbas
    img[back_entries * sector:back_entries * sector + len(entries)] = entries
    img[(total - 1) * sector:total * sector] = header(sector, total - 1, 1, first_usable, last_usable,
                                                      back_entries, disk_guid, crc)
    open(out_path, "wb").write(img)


if __name__ == "__main__":
    main()
