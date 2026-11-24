#!/usr/bin/env python3
"""
Build a boot.img that the stock ASIAIR Plus (RK3568) U-Boot will load.

Stock p3 layout (decoded from 20260423_p3_boot.bin):
  Android boot image header v0, page 2048, kernel at 0x10008000,
  no ramdisk, empty cmdline, and the "second" stage holding a Rockchip
  RSCE resource image with rk-kernel.dtb (+ logo.bmp, logo_kernel.bmp).
  U-Boot loads the DTB from the resource image and takes bootargs from
  its /chosen node.

Usage:
  mkbootimg-asiair.py --kernel Image --dtb board.dtb [--logos-from stock_p3.bin] -o boot.img
  mkbootimg-asiair.py --selftest stock_p3.bin   # rebuild stock image, compare bytes
"""
import argparse
import hashlib
import struct
import sys

PAGE = 2048
BLK = 512
KERNEL_ADDR = 0x10008000
SECOND_ADDR = 0x10F00000
TAGS_ADDR = 0x10000100


def pad(data, align):
    return data + b"\0" * (-len(data) % align)


def build_resource(entries):
    """entries: list of (name, bytes). Returns an RSCE image."""
    n = len(entries)
    # header: magic, ptn_ver u16, idx_ver u16, hdr_blks u8, tbl_off u8,
    # entry_blks u8, (1 pad byte), entry_num u32
    hdr = struct.pack("<4sHHBBBxI", b"RSCE", 0, 0, 1, 1, 1, n)
    out = pad(hdr, BLK)
    table = b""
    blob = b""
    off = 1 + n  # first content block after header + table
    for name, data in entries:
        # Rockchip resource_tool entry: tag, name[220], hash[32], hash_size,
        # content_offset (blocks), content_size. Hash is SHA-1 of the content.
        e = struct.pack("<4s220s32sIII", b"ENTR", name.encode(), hashlib.sha1(data).digest(),
                        20, off + len(blob) // BLK, len(data))
        table += pad(e, BLK)
        blob += pad(data, BLK)
    return out + table + blob


def parse_resource(res):
    n = struct.unpack_from("<I", res, 12)[0]
    out = []
    for i in range(n):
        e = res[(1 + i) * BLK:(2 + i) * BLK]
        name = e[4:224].split(b"\0")[0].decode()
        start, size = struct.unpack_from("<II", e, 260)
        out.append((name, res[start * BLK:start * BLK + size]))
    return out


def parse_bootimg(img):
    assert img[:8] == b"ANDROID!", "not an Android boot image"
    ks, _, rs, ra, ss = struct.unpack_from("<5I", img, 8)
    ko = PAGE
    ro = ko + len(pad(b"\0" * ks, PAGE))
    so = ro + len(pad(b"\0" * rs, PAGE))
    return img[ko:ko + ks], img[ro:ro + rs], ra, img[so:so + ss]


def build_bootimg(kernel, second, cmdline=b"", ramdisk=b"", ramdisk_addr=0):
    sha = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    hdr = struct.pack(
        "<8s10I16s512s32s1024s",
        b"ANDROID!",
        len(kernel), KERNEL_ADDR,
        len(ramdisk), ramdisk_addr if ramdisk else 0,
        len(second), SECOND_ADDR,
        TAGS_ADDR, PAGE,
        0, 0,  # header_version, os_version
        b"", cmdline, sha.digest(), b"",
    )
    out = pad(hdr, PAGE) + pad(kernel, PAGE)
    if ramdisk:
        out += pad(ramdisk, PAGE)
    return out + pad(second, PAGE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel")
    ap.add_argument("--dtb")
    ap.add_argument("--raw-dtb", action="store_true",
                    help="put the DTB directly in the second slot instead of an RSCE resource image "
                         "(the layout of the 6.18.43 image proven to boot on hardware)")
    ap.add_argument("--ramdisk", help="optional initramfs (omit to boot straight to root=)")
    ap.add_argument("--ramdisk-addr", type=lambda x: int(x, 0), default=0x0A200000)
    ap.add_argument("--logos-from", help="stock p3 dump to copy logo.bmp/logo_kernel.bmp from")
    ap.add_argument("--max-size", type=int, default=64 * 1024 * 1024, help="partition size")
    ap.add_argument("-o", "--output")
    ap.add_argument("--selftest", metavar="STOCK_P3")
    a = ap.parse_args()

    if a.selftest:
        stock = open(a.selftest, "rb").read()
        kernel, ramdisk, raddr, second = parse_bootimg(stock)
        if second[:4] == b"RSCE":
            res = parse_resource(second)
            print("resource entries:", [(n, len(d)) for n, d in res])
            second = build_resource(res)
        else:
            print("second slot: raw %s (%d bytes)" % ("DTB" if second[:4] == b"\xd0\x0d\xfe\xed" else "data", len(second)))
        print("ramdisk: %d bytes @ %#x" % (len(ramdisk), raddr))
        rebuilt = build_bootimg(kernel, second, ramdisk=ramdisk, ramdisk_addr=raddr)
        same = stock[:len(rebuilt)] == rebuilt
        tail_zero = stock[len(rebuilt):].strip(b"\0") == b""
        print("rebuilt %d bytes; identical=%s; rest of partition zero=%s" % (len(rebuilt), same, tail_zero))
        if not same:
            for i, (x, y) in enumerate(zip(stock, rebuilt)):
                if x != y:
                    print("first difference at byte", i)
                    break
        sys.exit(0 if same else 1)

    if not (a.kernel and a.dtb and a.output):
        ap.error("--kernel, --dtb and -o are required")
    kernel = open(a.kernel, "rb").read()
    dtb = open(a.dtb, "rb").read()
    assert kernel[56:60] == b"ARM\x64", "kernel is not an arm64 Image"
    assert dtb[:4] == b"\xd0\x0d\xfe\xed", "dtb is not a flattened device tree"
    ramdisk = open(a.ramdisk, "rb").read() if a.ramdisk else b""
    if a.raw_dtb:
        entries = [("raw dtb", dtb)]
        second = dtb
    else:
        entries = [("rk-kernel.dtb", dtb)]
        if a.logos_from:
            second = parse_bootimg(open(a.logos_from, "rb").read())[3]
            entries += [(n, d) for n, d in parse_resource(second) if n.endswith(".bmp")]
        second = build_resource(entries)
    img = build_bootimg(kernel, second, ramdisk=ramdisk, ramdisk_addr=a.ramdisk_addr)
    if len(img) > a.max_size:
        sys.exit("boot.img is %d bytes, larger than the %d byte partition" % (len(img), a.max_size))
    open(a.output, "wb").write(img)
    print("wrote %s: %d bytes (%.1f MB of %.0f MB), second: %s, ramdisk: %d bytes" % (
        a.output, len(img), len(img) / 2**20, a.max_size / 2**20, [n for n, _ in entries], len(ramdisk)))


if __name__ == "__main__":
    main()
