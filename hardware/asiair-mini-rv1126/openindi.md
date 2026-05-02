# OpenINDI — Expanded INDI Support for ASIAIR Mini

Repartition your ASIAIR Mini (RV1126) to expand the root filesystem from 7 GB
to ~20 GB, providing space to install additional INDI drivers for third-party
focusers, filter wheels, rotators, and cameras.

## Overview

The stock ASIAIR Mini dedicates 20 GB to astrophotography image storage (p5)
and only 7 GB to the root filesystem (p7). With the stock ZWO app and INDI
1.7.8 pre-installed, only ~970 MB is free on rootfs — not enough for additional
drivers and vendor SDKs.

OpenINDI shrinks the image storage partition and expands rootfs:

| Partition | Stock | OpenINDI | Purpose |
|-----------|-------|----------|---------|
| p1-p4 | 104 MB | 104 MB | Boot chain (unchanged) |
| p5 (asiair) | 20 GB | 8 GB | Astrophoto image storage |
| p6 (pi) | 512 MB | 512 MB | /home/pi |
| p7 (rootfs) | 7 GB | **19.9 GB** | Root filesystem |
| p8 (swap) | 1.5 GB | 768 MB | Swap |

The boot chain, kernel, and ZWO application are preserved. Only the partition
boundaries and filesystem sizes change.

## Prerequisites

### Hardware

- ASIAIR Mini (RV1126)
- USB-C cable connected to your PC
- The ASIAIR must be in **Loader mode** (hold reset button while powering on)

### Software

Install on your PC (Debian/Ubuntu):

```bash
sudo apt install build-essential autoconf automake libusb-1.0-0-dev \
    pkg-config python3 e2fsprogs dosfstools
```

### Backup

You **must** have a full backup of your ASIAIR in `asiair-backup/` before
running this script. If you don't have one, create it first:

```bash
scripts/jailbreak        # enable SSH on the ASIAIR
scripts/backup pi@10.0.0.1  # backup all partitions (~8 GB)
```

The backup is also your only way to restore the stock partition layout.

### Disk Space

The script needs ~21 GB of free space in `/tmp` (or wherever `TMPDIR` points)
to prepare the expanded rootfs image. If `/tmp` is too small, set `TMPDIR`:

```bash
TMPDIR=/path/to/large/disk sudo scripts/openindi
```

## Usage

### 1. Build rk-flashtool

```bash
./autogen.sh && ./configure && make
```

### 2. Enter Loader mode

Power off the ASIAIR Mini. Hold the reset button while powering on via USB-C.
Verify with:

```bash
./rk-flashtool ld
# Expected: DevNo=1  Vid=0x2207,Pid=0x110b,...  Loader
```

### 3. Run the script

```bash
sudo scripts/openindi
```

The script will:

1. Verify all backup files are present
2. Show the current and proposed partition layout
3. Ask for confirmation before proceeding
4. Build a new GPT partition table
5. Prepare the expanded rootfs (copies backup, resizes to ~20 GB)
6. Create a fresh VFAT for the image storage partition
7. Write everything to the ASIAIR over USB
8. Reset the device

The rootfs write (~20 GB over USB) takes **15-30 minutes**. Do not disconnect
the USB cable during this time.

### 4. Verify

After the device resets, connect to the ASIAIR WiFi and SSH in:

```bash
ssh pi@10.0.0.1    # password: raspberry
```

Check the new partition layout:

```bash
df -h
# /dev/root should now show ~19 GB with ~13 GB free
```

### 5. Install INDI drivers

The rootfs is mounted read-only by default. To install packages:

```bash
sudo mount -o remount,rw /
sudo apt update
sudo apt install indi-full    # or specific drivers
sudo mount -o remount,ro /
```

## What Gets Installed (Stock)

The stock ASIAIR Mini already includes INDI 1.7.8 with these driver categories:

| Category | Drivers | Examples |
|----------|---------|---------|
| Mounts | ~25 | EQMod, Celestron, iOptron, SynScan, LX200 |
| Focusers | ~20 | MoonLite, Pegasus, RoboFocus, DeepSkyDad |
| Filter wheels | ~7 | QHY CFW2/3, Optec, Xagyl, Manual |
| Weather | ~6 | OpenWeatherMap, SQM, Vantage |
| Domes | ~3 | Baader, ScopeDome, Rolloff |
| Rotators | 1 | Pyxis |
| Cameras | 0 | ZWO only (via proprietary libASICamera2.so) |

With the expanded rootfs, you can add third-party camera drivers (QHY, Atik,
PlayerOne, SVBony), additional focusers, rotators, and upgrade to INDI 2.x.

## Restoring Stock Partition Layout

To go back to the original 20 GB/7 GB partition layout:

```bash
sudo scripts/restore-stock --full
```

This writes all backup partitions (including the original GPT) back to the
device, fully restoring the stock layout.

## Troubleshooting

### "Not enough disk space"

Set `TMPDIR` to a location with at least 21 GB free:

```bash
TMPDIR=/mnt/external sudo scripts/openindi
```

### Write fails on rootfs (p7)

The rootfs is the largest write (~20 GB). USB connections can be flaky over
long transfers. The script retries once with a USB reset. If it fails again:

1. Check your USB cable (use a short, data-capable cable)
2. Try a different USB port (USB 3.0 ports are more reliable)
3. Re-run the script — it's safe to run multiple times

### Device won't boot after repartition

Enter Loader mode (hold reset while powering on) and restore stock:

```bash
sudo scripts/restore-stock --full
```

### ASIAIR app doesn't start after repartition

The ZWO application expects the VFAT image storage at p5. If the app fails to
find it, remount rw and check the mount point:

```bash
sudo mount -o remount,rw /
# Verify /etc/fstab has the correct PARTUUID for p5
blkid /dev/mmcblk0p5
```

The partition UUIDs are preserved from the backup, so this should not normally
be an issue.

## Technical Details

### How It Works

1. **GPT rebuild** — `scripts/lib/build-gpt.py` reads the backup GPT, modifies
   partition boundaries for p5-p8, recomputes CRC32 checksums, and outputs both
   primary and backup GPT images.

2. **Bootloader merge** — The new GPT primary (sectors 0-33) is overlaid onto
   the stock bootloader image (sectors 0-16383). This ensures the IDB bootloader
   at sector 64 is preserved while the partition table is updated.

3. **Rootfs resize** — The 7 GB rootfs backup is copied, truncated to 20 GB,
   and expanded with `resize2fs`. This happens entirely on the host before
   writing to flash.

4. **VFAT creation** — A fresh FAT32 filesystem is created for the 8 GB image
   storage partition. Only the first 64 MB (superblock + FAT tables) is written;
   the rest of the partition is initialized by the filesystem as needed.

### Files

| File | Purpose |
|------|---------|
| `scripts/openindi` | Main repartition script |
| `scripts/lib/build-gpt.py` | GPT partition table builder |
| `scripts/lib/gpt.sh` | Bash GPT parser (shared with other scripts) |
