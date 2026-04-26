#!/usr/bin/env python3
"""Create a Rockchip RSCE resource image containing a single DTB.

Reverse-engineered from stock ASIAIR Plus boot image.

RSCE layout (512-byte blocks):
  Block 0:    Header — magic "RSCE", entry count, table offset/size
  Block 1-3:  Entry table — "ENTR" tag, filename, hash, data pointer
  Block 4+:   DTB data
"""

import hashlib
import math
import struct
import sys


BLOCK = 512


def build_rsce(dtb_path, output_path):
    dtb = open(dtb_path, "rb").read()
    dtb_size = len(dtb)

    # Header (block 0)
    header = bytearray(BLOCK)
    header[0:4] = b"RSCE"
    # version=0, c_version=0
    header[8] = 1    # entry count
    header[9] = 1    # table offset (block 1)
    header[10] = 1   # entry size (1 block = 512 bytes)

    # Entry (block 1) — matches stock format
    entry = bytearray(BLOCK)
    entry[0:4] = b"ENTR"
    name = b"rk-kernel.dtb"
    entry[4:4+len(name)] = name

    # Hash of DTB at offset 0xe0 (20 bytes, matching stock)
    dtb_hash = hashlib.sha1(dtb).digest()
    entry[0xe0:0xe0+20] = dtb_hash

    # Data pointer at offset 0x100
    data_block = 4  # DTB starts at block 4 (offset 0x800), matching stock
    struct.pack_into("<I", entry, 0x100, 0x14)  # unknown field, matches stock
    struct.pack_into("<I", entry, 0x104, data_block)
    struct.pack_into("<I", entry, 0x108, dtb_size)

    # Padding blocks (2-3) between entry table and data
    pad = bytearray(BLOCK * 2)

    # DTB data (block 4+), padded to block boundary
    dtb_blocks = math.ceil(dtb_size / BLOCK)
    dtb_padded = dtb + b"\x00" * (dtb_blocks * BLOCK - dtb_size)

    with open(output_path, "wb") as f:
        f.write(header)
        f.write(entry)
        f.write(pad)
        f.write(dtb_padded)

    total = BLOCK + BLOCK + len(pad) + len(dtb_padded)
    print(f"DTB:    {dtb_size} bytes ({dtb_size/1024:.1f} KB)")
    print(f"Output: {total} bytes ({total/1024:.1f} KB)")
    print(f"Wrote:  {output_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <dtb> <output.img>")
        sys.exit(1)
    build_rsce(sys.argv[1], sys.argv[2])
