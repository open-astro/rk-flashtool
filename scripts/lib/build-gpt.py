#!/usr/bin/env python3
"""Build a new GPT (primary + backup) from an existing GPT with modified partition boundaries."""

import struct
import sys
import zlib

SECTOR = 512
GPT_HEADER_SIZE = 92
NUM_ENTRIES = 128
ENTRY_SIZE = 128
ENTRY_ARRAY_SECTORS = (NUM_ENTRIES * ENTRY_SIZE) // SECTOR  # 32 sectors

def parse_args():
    args = {'partitions': {}}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == '--source' and i + 1 < len(sys.argv):
            args['source'] = sys.argv[i + 1]; i += 2
        elif sys.argv[i] == '--output' and i + 1 < len(sys.argv):
            args['output'] = sys.argv[i + 1]; i += 2
        elif sys.argv[i] == '--disk-sectors' and i + 1 < len(sys.argv):
            args['disk_sectors'] = int(sys.argv[i + 1]); i += 2
        elif sys.argv[i] == '--partition' and i + 1 < len(sys.argv):
            parts = sys.argv[i + 1].split(':')
            num, start, end = int(parts[0]), int(parts[1]), int(parts[2])
            args['partitions'][num] = (start, end)
            i += 2
        else:
            print(f"Unknown argument: {sys.argv[i]}", file=sys.stderr)
            sys.exit(1)
    return args

def gpt_crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF

def build_gpt(source_path, output_path, disk_sectors, partition_mods):
    with open(source_path, 'rb') as f:
        source = f.read()

    mbr = bytearray(source[:SECTOR])
    entries = bytearray(source[2 * SECTOR : (2 + ENTRY_ARRAY_SECTORS) * SECTOR])

    # Modify partition entries (1-based index)
    for part_num, (start_lba, end_lba) in partition_mods.items():
        offset = (part_num - 1) * ENTRY_SIZE
        struct.pack_into('<Q', entries, offset + 32, start_lba)
        struct.pack_into('<Q', entries, offset + 40, end_lba)

    entries_crc = gpt_crc32(bytes(entries))
    last_usable = disk_sectors - 34

    # Update protective MBR to cover the whole disk
    struct.pack_into('<I', mbr, 446 + 12, 1)           # start_sect
    struct.pack_into('<I', mbr, 446 + 16, min(disk_sectors - 1, 0xFFFFFFFF))  # nr_sects

    # Build primary header
    hdr = bytearray(SECTOR)
    source_hdr = source[SECTOR : SECTOR + GPT_HEADER_SIZE]
    disk_guid = source_hdr[56:72]

    struct.pack_into('<Q', hdr, 0, 0x5452415020494645)  # signature
    struct.pack_into('<I', hdr, 8, 0x00010000)          # revision
    struct.pack_into('<I', hdr, 12, GPT_HEADER_SIZE)    # header_size
    struct.pack_into('<I', hdr, 16, 0)                  # header_crc32 (zeroed for calc)
    struct.pack_into('<I', hdr, 20, 0)                  # reserved
    struct.pack_into('<Q', hdr, 24, 1)                  # my_lba
    struct.pack_into('<Q', hdr, 32, disk_sectors - 1)   # alternate_lba
    struct.pack_into('<Q', hdr, 40, 34)                 # first_usable_lba
    struct.pack_into('<Q', hdr, 48, last_usable)        # last_usable_lba
    hdr[56:72] = disk_guid
    struct.pack_into('<Q', hdr, 72, 2)                  # partition_entry_lba
    struct.pack_into('<I', hdr, 80, NUM_ENTRIES)
    struct.pack_into('<I', hdr, 84, ENTRY_SIZE)
    struct.pack_into('<I', hdr, 88, entries_crc)

    hdr_crc = gpt_crc32(bytes(hdr[:GPT_HEADER_SIZE]))
    struct.pack_into('<I', hdr, 16, hdr_crc)

    # Build backup header
    backup_hdr = bytearray(hdr)
    struct.pack_into('<I', backup_hdr, 16, 0)               # zero crc for recalc
    struct.pack_into('<Q', backup_hdr, 24, disk_sectors - 1) # my_lba
    struct.pack_into('<Q', backup_hdr, 32, 1)                # alternate_lba
    struct.pack_into('<Q', backup_hdr, 72, disk_sectors - 33) # partition_entry_lba
    backup_hdr_crc = gpt_crc32(bytes(backup_hdr[:GPT_HEADER_SIZE]))
    struct.pack_into('<I', backup_hdr, 16, backup_hdr_crc)

    # Write output: primary (34 sectors) + backup (33 sectors)
    with open(output_path, 'wb') as f:
        f.write(bytes(mbr))
        f.write(bytes(hdr))
        f.write(bytes(entries))
        # Backup: entries first, then header
        f.write(bytes(entries))
        f.write(bytes(backup_hdr))

    primary_sectors = 1 + 1 + ENTRY_ARRAY_SECTORS  # MBR + header + entries = 34
    backup_sectors = ENTRY_ARRAY_SECTORS + 1         # entries + header = 33
    total = primary_sectors + backup_sectors

    # Print partition summary
    print(f"GPT built: {total} sectors ({total * SECTOR} bytes)")
    print(f"Disk: {disk_sectors} sectors ({disk_sectors * SECTOR / (1024**3):.1f} GB)")
    print(f"Usable: sectors 34 - {last_usable}")
    print()
    for i in range(NUM_ENTRIES):
        off = i * ENTRY_SIZE
        type_guid = entries[off:off+16]
        if type_guid == b'\x00' * 16:
            break
        start = struct.unpack_from('<Q', entries, off + 32)[0]
        end = struct.unpack_from('<Q', entries, off + 40)[0]
        name_raw = entries[off + 56 : off + 128]
        name = name_raw.decode('utf-16le', errors='ignore').rstrip('\x00')
        size_mb = (end - start + 1) * SECTOR / (1024**2)
        size_str = f"{size_mb/1024:.1f} GB" if size_mb >= 1024 else f"{size_mb:.0f} MB"
        mod = " (modified)" if (i + 1) in partition_mods else ""
        print(f"  p{i+1}: {name:<12} sectors {start}-{end} ({size_str}){mod}")

if __name__ == '__main__':
    args = parse_args()
    for req in ('source', 'output', 'disk_sectors'):
        if req not in args:
            print(f"Missing --{req.replace('_', '-')}", file=sys.stderr)
            sys.exit(1)
    build_gpt(args['source'], args['output'], args['disk_sectors'], args['partitions'])
