#!/bin/bash
# GPT partition table parser — reads partition start sectors from a GPT backup file.

# Read the start sector (LBA) of a partition from a GPT image.
# Usage: gpt_part_start <gpt_primary.bin> <partition_number>
# Partition numbers are 1-based (p1=1, p7=7, etc.)
gpt_part_start() {
    local gpt_file="$1" part_num="$2"
    local offset=$((1024 + (part_num - 1) * 128 + 32))
    local bytes
    bytes=$(dd if="$gpt_file" bs=1 skip="$offset" count=8 2>/dev/null | od -An -tu1)
    local vals=($bytes)
    local result=0
    local mult=1
    for i in 0 1 2 3 4 5 6 7; do
        result=$((result + ${vals[$i]} * mult))
        mult=$((mult * 256))
    done
    echo "$result"
}

# Read the end sector (LBA) of a partition from a GPT image.
# Usage: gpt_part_end <gpt_primary.bin> <partition_number>
gpt_part_end() {
    local gpt_file="$1" part_num="$2"
    local offset=$((1024 + (part_num - 1) * 128 + 40))
    local bytes
    bytes=$(dd if="$gpt_file" bs=1 skip="$offset" count=8 2>/dev/null | od -An -tu1)
    local vals=($bytes)
    local result=0
    local mult=1
    for i in 0 1 2 3 4 5 6 7; do
        result=$((result + ${vals[$i]} * mult))
        mult=$((mult * 256))
    done
    echo "$result"
}

# Find the most recent GPT primary backup file in a backup directory.
# Usage: find_gpt_backup <backup_dir>
find_gpt_backup() {
    ls -1t "$1"/*_gpt_primary.bin 2>/dev/null | head -1
}
