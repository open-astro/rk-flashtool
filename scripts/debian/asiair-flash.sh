#!/bin/bash

# Base directory — set to the parent of the rkdeveloptool repo
BASEDIR="${BASEDIR:-$(cd "$(dirname "$0")/../.." && cd .. && pwd)}"
FLASHTOOL="$BASEDIR/rkdeveloptool/rk-flashtool"
OUTDIR="$BASEDIR/asiair-image"
GPTIMG="$BASEDIR/asiair-gpt.img"

# Find the Rockchip USB device for resetting between commands
find_rk_usb() {
    for d in /sys/bus/usb/devices/*/idVendor; do
        if [ "$(cat "$d" 2>/dev/null)" = "2207" ]; then
            echo "$(dirname "$d")"
            return 0
        fi
    done
}

reset_usb() {
    local dev=$(find_rk_usb)
    if [ -n "$dev" ]; then
        local busnum=$(cat "$dev/busnum" 2>/dev/null)
        local devnum=$(cat "$dev/devnum" 2>/dev/null)
        if [ -n "$busnum" ] && [ -n "$devnum" ]; then
            usbreset "$(printf "/dev/bus/usb/%03d/%03d" "$busnum" "$devnum")" >/dev/null 2>&1 || true
        fi
    fi
    sleep 2
}

# Run rk-flashtool with --foreground so it gets the TTY for live progress.
# After timeout, SIGTERM then SIGKILL, followed by USB reset.
flash_write() {
    local label="$1"
    local max_wait="$2"
    shift 2
    echo "  $label..."
    timeout --foreground --signal=TERM --kill-after=5 "$max_wait" "$FLASHTOOL" "$@"
    local rc=$?
    if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
        echo "  $label: done (cleaned up after hang)"
    elif [ $rc -ne 0 ]; then
        echo "  $label: WARNING — exit code $rc"
    fi
    reset_usb
}

echo ""
echo "=== ASIAIR Debian Flash Script ==="
echo ""
echo "WARNING: This will ERASE the stock ASIAIR firmware!"
echo "Make sure you have a full backup before proceeding."
echo "The device must be in Loader mode (hold reset + power on)."
echo ""

# Check device
if ! $FLASHTOOL ld 2>/dev/null | grep -q "Loader"; then
    echo "ERROR: No device found in Loader mode."
    echo "Enter Loader mode: power off, connect USB-C, hold reset, plug 12V, power on, hold 5 sec."
    exit 1
fi
echo "Device found in Loader mode."
echo ""

# =============================================
# 1. Write new GPT partition table
# =============================================
echo "--- Step 1/5: Writing new GPT partition table ---"

TOTAL_SECTORS=$($FLASHTOOL rfi 2>/dev/null | grep "Sectors" | awk '{print $(NF-1)}' | tr -d '\r')
if [ -z "$TOTAL_SECTORS" ] || ! [ "$TOTAL_SECTORS" -gt 1000000 ] 2>/dev/null; then
    echo "ERROR: Could not determine flash size (got: '$TOTAL_SECTORS')."
    exit 1
fi
FLASH_SIZE_GB=$(( TOTAL_SECTORS * 512 / 1024 / 1024 / 1024 ))
echo "Flash size: $TOTAL_SECTORS sectors ($FLASH_SIZE_GB GB)"

BOOT_START=24576
BOOT_SECTORS=524288
ROOTFS_START=$((BOOT_START + BOOT_SECTORS))
SWAP_SECTORS=2097152
LAST_USABLE=$((TOTAL_SECTORS - 34))
SWAP_START=$((LAST_USABLE - SWAP_SECTORS + 1))
ROOTFS_SECTORS=$((SWAP_START - ROOTFS_START))

echo "Partition layout:"
echo "  uboot:  sector 16384, 4 MB"
echo "  boot:   sector $BOOT_START, 256 MB"
echo "  rootfs: sector $ROOTFS_START, $(( ROOTFS_SECTORS * 512 / 1024 / 1024 / 1024 )) GB"
echo "  swap:   sector $SWAP_START, 1 GB"
echo ""

truncate -s $((TOTAL_SECTORS * 512)) "$GPTIMG"

sfdisk "$GPTIMG" << SFDISK_EOF
label: gpt

start=16384,   size=8192,         type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE, name="uboot"
start=$BOOT_START,  size=$BOOT_SECTORS,   type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="boot"
start=$ROOTFS_START, size=$ROOTFS_SECTORS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs"
start=$SWAP_START,  size=$SWAP_SECTORS,   type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name="swap"
SFDISK_EOF

GPTPRIMARY="$BASEDIR/asiair-gpt-primary.img"
GPTBACKUP="$BASEDIR/asiair-gpt-backup.img"
dd if="$GPTIMG" of="$GPTPRIMARY" bs=512 count=34 2>/dev/null
dd if="$GPTIMG" of="$GPTBACKUP" bs=512 skip=$((TOTAL_SECTORS - 33)) count=33 2>/dev/null
rm -f "$GPTIMG"

flash_write "GPT primary" 30 wl 0 "$GPTPRIMARY"
flash_write "GPT backup" 30 wl $((TOTAL_SECTORS - 33)) "$GPTBACKUP"
rm -f "$GPTPRIMARY" "$GPTBACKUP"
echo "GPT written."
echo ""

# =============================================
# 2. Write bootloader
# =============================================
echo "--- Step 2/5: Writing bootloader ---"
flash_write "idbloader (198 KB)" 30 wl 0x40 "$OUTDIR/idbloader.img"
flash_write "u-boot.itb (1 MB)" 30 wl 0x4000 "$OUTDIR/u-boot.itb"
echo "Bootloader written."
echo ""

# =============================================
# 3. Write boot partition
# =============================================
echo "--- Step 3/5: Writing boot partition (256 MB) ---"
flash_write "boot.img" 300 wl $BOOT_START "$OUTDIR/boot.img"
echo "Boot partition written."
echo ""

# =============================================
# 4. Write rootfs partition
# =============================================
ROOTFS_SIZE=$(du -h "$OUTDIR/rootfs.img" | awk '{print $1}')
echo "--- Step 4/5: Writing rootfs partition ($ROOTFS_SIZE) ---"
echo "This is the large write — may take 5-10 minutes over USB."
flash_write "rootfs.img" 900 wl $ROOTFS_START "$OUTDIR/rootfs.img"
echo "Rootfs written."
echo ""

# =============================================
# 5. Reset device
# =============================================
echo "--- Step 5/5: Rebooting device ---"
timeout --foreground --signal=TERM --kill-after=5 10 $FLASHTOOL rd || true
sleep 2

echo ""
echo "=== Flash complete ==="
echo ""
echo "The ASIAIR should now boot Debian Trixie."
echo "  Hostname: astro"
echo "  User: astro / astro"
echo "  SSH: enabled (connect via ethernet or find WiFi IP)"
echo ""
echo "On first boot, the rootfs will auto-resize to fill the partition."
echo ""
echo "To restore stock firmware, use the backup images in:"
echo "  hardware/asiair-plus-rk3568-256g/asiair-backup/"
