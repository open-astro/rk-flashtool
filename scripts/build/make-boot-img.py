#!/usr/bin/env python3
"""Create an Android boot image (v0) for Rockchip U-Boot.

Packages a kernel Image and DTB into the format stock Rockchip U-Boot expects:
  - Android boot header (v0) with ANDROID! magic
  - ARM64 kernel Image
  - No ramdisk
  - Raw DTB in the "second" field

Uses the same load addresses as the stock ASIAIR Plus boot image.
"""

import argparse
import hashlib
import math
import os
import struct
import sys

PAGE_SIZE = 2048
KERNEL_ADDR = 0x10008000
RAMDISK_ADDR = 0x00000000
SECOND_ADDR = 0x10f00000
TAGS_ADDR = 0x10000100


def page_align(size):
    return math.ceil(size / PAGE_SIZE) * PAGE_SIZE


def build_boot_img(kernel_path, dtb_path, output_path, cmdline=""):
    kernel = open(kernel_path, "rb").read()
    dtb = open(dtb_path, "rb").read()

    kernel_size = len(kernel)
    ramdisk_size = 0
    second_size = len(dtb)

    # Build header (1 page)
    header = bytearray(PAGE_SIZE)
    struct.pack_into("8s", header, 0, b"ANDROID!")
    struct.pack_into("<I", header, 8, kernel_size)
    struct.pack_into("<I", header, 12, KERNEL_ADDR)
    struct.pack_into("<I", header, 16, ramdisk_size)
    struct.pack_into("<I", header, 20, RAMDISK_ADDR)
    struct.pack_into("<I", header, 24, second_size)
    struct.pack_into("<I", header, 28, SECOND_ADDR)
    struct.pack_into("<I", header, 32, TAGS_ADDR)
    struct.pack_into("<I", header, 36, PAGE_SIZE)
    struct.pack_into("<I", header, 40, 0)  # header version 0
    struct.pack_into("<I", header, 44, 0)  # os_version

    # cmdline at offset 64 (512 bytes max)
    cmdline_bytes = cmdline.encode("ascii")[:511]
    struct.pack_into(f"{len(cmdline_bytes)}s", header, 64, cmdline_bytes)

    # SHA1 id at offset 0x240
    sha = hashlib.sha1()
    sha.update(kernel)
    sha.update(struct.pack("<I", kernel_size))
    sha.update(struct.pack("<I", ramdisk_size))
    sha.update(dtb)
    sha.update(struct.pack("<I", second_size))
    digest = sha.digest()
    header[0x240:0x240 + len(digest)] = digest

    # Assemble image
    kernel_padded = kernel + b"\x00" * (page_align(kernel_size) - kernel_size)
    dtb_padded = dtb + b"\x00" * (page_align(second_size) - second_size)

    with open(output_path, "wb") as f:
        f.write(header)
        f.write(kernel_padded)
        # no ramdisk
        f.write(dtb_padded)

    total = PAGE_SIZE + len(kernel_padded) + len(dtb_padded)
    print(f"Kernel: {kernel_size} bytes ({kernel_size/1024/1024:.1f} MB)")
    print(f"DTB:    {second_size} bytes ({second_size/1024:.1f} KB)")
    print(f"Output: {total} bytes ({total/1024/1024:.1f} MB)")
    print(f"Wrote:  {output_path}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Create Android boot image for Rockchip U-Boot")
    p.add_argument("--kernel", required=True, help="Path to ARM64 kernel Image")
    p.add_argument("--dtb", required=True, help="Path to device tree blob")
    p.add_argument("--cmdline", default="", help="Kernel command line")
    p.add_argument("-o", "--output", required=True, help="Output boot image path")
    args = p.parse_args()

    build_boot_img(args.kernel, args.dtb, args.output, args.cmdline)
