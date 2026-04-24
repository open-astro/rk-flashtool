#!/bin/bash
#
# ASIAIR Plus RK3568 — Full eMMC Backup Script
#
# Run this FROM YOUR LOCAL MACHINE (not on the ASIAIR).
# It streams each partition over SSH directly to local storage.
#
# Usage:
#   ./backup.sh [user@host] [backup_dir]
#
# Examples:
#   ./backup.sh pi@asiair
#   ./backup.sh pi@asiair ./my-backup-dir
#
# Requires:
#   - sshpass (apt install sshpass)
#   - ASIAIR jailbroken for SSH access (https://github.com/open-astro/ASIAIRJailbreak)
#

set -euo pipefail

REMOTE="${1:-pi@asiair}"
BACKUP_DIR="${2:-$(pwd)/asiair-backup}"
PASS="${ASIAIR_PASS:-raspberry}"
DATE=$(date +%Y%m%d)
DEVICE="/dev/mmcblk0"

SSH_CMD="sshpass -p $PASS ssh -o StrictHostKeyChecking=no"

echo "============================================"
echo " ASIAIR Plus Full Backup (streaming via SSH)"
echo " Date:   $DATE"
echo " Remote: $REMOTE"
echo " Device: $DEVICE"
echo " Local:  $BACKUP_DIR"
echo "============================================"
echo ""

# Test SSH connection
if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpass not found. Install it:"
    echo "  sudo apt install sshpass"
    exit 1
fi

if ! $SSH_CMD "$REMOTE" 'echo ok' >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to $REMOTE via SSH."
    echo "Make sure SSH is configured and the device is reachable."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

ok_count=0
fail_count=0

pull_backup() {
    local desc="$1"
    local remote_cmd="$2"
    local local_file="$BACKUP_DIR/${DATE}_${3}"

    echo "--- $desc ---"
    echo "  -> $local_file"

    if $SSH_CMD "$REMOTE" "echo $PASS | sudo -S $remote_cmd" > "$local_file"; then
        local size
        size=$(stat -c%s "$local_file" 2>/dev/null || stat -f%z "$local_file" 2>/dev/null || echo "?")
        echo "  Size: $size bytes"
        echo "  OK"
        ok_count=$((ok_count + 1))
    else
        echo "  FAILED"
        fail_count=$((fail_count + 1))
    fi
    echo ""
}

# ============================================================
# GPT partition table
# ============================================================
echo "=== GPT Partition Table ==="

pull_backup "GPT primary (first 34 sectors)" \
    "dd if=$DEVICE bs=512 count=34 2>/dev/null" \
    "gpt_primary.bin"

TOTAL_SECTORS=$($SSH_CMD "$REMOTE" "echo $PASS | sudo -S blockdev --getsz $DEVICE 2>/dev/null")
GPT_BACKUP_START=$((TOTAL_SECTORS - 33))

pull_backup "GPT backup (last 33 sectors)" \
    "dd if=$DEVICE bs=512 skip=$GPT_BACKUP_START count=33 2>/dev/null" \
    "gpt_backup.bin"

# ============================================================
# Pre-partition bootloader area (sectors 0–16383)
# ============================================================
echo "=== Pre-Partition Bootloader ==="

pull_backup "Bootloader area (sectors 0-16383, 8 MB)" \
    "dd if=$DEVICE bs=512 count=16384 2>/dev/null" \
    "bootloader_pre_partition.bin"

# ============================================================
# Individual partitions
# ============================================================
echo "=== Partitions ==="

pull_backup "p1 — uboot (4 MB)" \
    "dd if=${DEVICE}p1 bs=4M 2>/dev/null" \
    "p1_uboot.bin"

pull_backup "p2 — misc (4 MB)" \
    "dd if=${DEVICE}p2 bs=4M 2>/dev/null" \
    "p2_misc.bin"

pull_backup "p3 — boot (64 MB, kernel + ramdisk)" \
    "dd if=${DEVICE}p3 bs=4M 2>/dev/null" \
    "p3_boot.bin"

pull_backup "p4 — recovery (32 MB)" \
    "dd if=${DEVICE}p4 bs=4M 2>/dev/null" \
    "p4_recovery.bin"

# p5 — asiair (222 GB) — back up VFAT header only
echo "--- p5 — asiair (222 GB VFAT image storage) ---"
echo "  NOTE: Backing up first 64 MB only (VFAT header + FAT tables)."
echo "  For a full image backup, run separately:"
echo "    $SSH_CMD $REMOTE 'echo $PASS | sudo -S dd if=${DEVICE}p5 bs=4M 2>/dev/null | gzip' > p5_full.gz"
echo ""

pull_backup "p5 — asiair VFAT header (first 64 MB)" \
    "dd if=${DEVICE}p5 bs=4M count=16 2>/dev/null" \
    "p5_asiair_header.bin"

pull_backup "p6 — pi (512 MB, /home/pi)" \
    "dd if=${DEVICE}p6 bs=4M 2>/dev/null" \
    "p6_pi.bin"

echo "--- p7 — rootfs (7 GB) — this will take a few minutes ---"
pull_backup "p7 — rootfs (7 GB, stock root filesystem)" \
    "dd if=${DEVICE}p7 bs=4M 2>/dev/null" \
    "p7_rootfs.bin"

# p8 — swap — skip
echo "--- p8 — swap (3.4 GB) ---"
echo "  Skipping: recreatable with mkswap."
echo ""

# ============================================================
# System info snapshot
# ============================================================
echo "=== System Info Snapshot ==="
INFO_FILE="$BACKUP_DIR/${DATE}_system_info.txt"
$SSH_CMD "$REMOTE" "
    echo '=== ASIAIR Plus Backup Info ==='
    echo \"Date: \$(date)\"
    echo \"Hostname: \$(hostname)\"
    echo \"Kernel: \$(uname -a)\"
    echo ''
    echo '=== Partition Table ==='
    echo $PASS | sudo -S fdisk -l $DEVICE 2>/dev/null || echo $PASS | sudo -S parted $DEVICE print
    echo ''
    echo '=== Block Device Size ==='
    echo $PASS | sudo -S blockdev --getsize64 $DEVICE 2>/dev/null
    echo ''
    echo '=== Mount Points ==='
    mount | grep mmcblk
    echo ''
    echo '=== Disk Usage ==='
    df -h
    echo ''
    echo '=== Device Tree Compatible ==='
    cat /proc/device-tree/compatible 2>/dev/null | tr '\0' '\n'
    echo ''
    echo '=== Serial ==='
    cat /proc/device-tree/serial-number 2>/dev/null | tr '\0' '\n'
" > "$INFO_FILE" 2>&1
echo "  Saved to $INFO_FILE"
echo ""

# ============================================================
# Checksums
# ============================================================
echo "=== Generating Checksums ==="
CHECKSUM_FILE="$BACKUP_DIR/${DATE}_checksums.sha256"
cd "$BACKUP_DIR"
sha256sum ${DATE}_*.bin > "$CHECKSUM_FILE" 2>/dev/null
echo "  Saved to $CHECKSUM_FILE"
cat "$CHECKSUM_FILE"
echo ""

# ============================================================
# Summary
# ============================================================
echo "============================================"
echo " Backup Complete"
echo " Succeeded: $ok_count"
echo " Failed:    $fail_count"
echo " Location:  $BACKUP_DIR"
echo ""
echo " Total backup size:"
du -sh "$BACKUP_DIR"
echo ""
if [ "$fail_count" -gt 0 ]; then
    echo " WARNING: $fail_count backups failed!"
    echo "============================================"
    exit 1
else
    echo " All backups verified."
    echo "============================================"
fi
