# ASIAIR Plus RK3568 — rk-flashtool Recovery Guide

## Device Identity

| Property | Value |
|----------|-------|
| SoC | RK3568 (chip info: `38 36 35 33` = "3568") |
| USB VID | 0x2207 (Rockchip) |
| USB PID | 0x350a (shared with RK3566) |
| eMMC | Samsung 256GB (238592 MB / 488636416 sectors) |

## USB Modes

| Mode | Meaning | When |
|------|---------|------|
| **Loader** | Bootloader (U-Boot) is running, full flash access | Normal USB connection while powered on |
| **Maskrom** | Bare SoC, no bootloader running | Bootloader is corrupted, or eMMC CLK shorted to GND |

### Entering Loader Mode

1. Power off the ASIAIR Plus completely
2. Connect USB-C to USB-A cable between the ASIAIR and the PC
3. Hold the reset button on the ASIAIR
4. Plug in the 12V DC power while continuing to hold reset
5. Power on the device while continuing to hold reset
6. Hold reset for 5 seconds, then release

The device should appear as `Vid=0x2207,Pid=0x350a` in `./rk-flashtool ld`.

### Entering Maskrom Mode

TBD — likely requires shorting the eMMC CLK pin on the PCB to prevent the bootloader from loading.

## Device Capabilities (Loader Mode)

```
Direct LBA:       enabled
First 4m Access:  enabled
Read Com Log:     enabled
Read Secure Mode: enabled
New IDB:          enabled
```

Full read/write access to all flash regions including the pre-partition bootloader area.

## Partition Table (verified from live device)

| # | LBA Start | Name | Size |
|---|-----------|------|------|
| 0 | 0x4000 | uboot | 4 MB |
| 1 | 0x6000 | misc | 4 MB |
| 2 | 0x8000 | boot | 64 MB |
| 3 | 0x28000 | recovery | 32 MB |
| 4 | 0x38000 | asiair | 222 GB |
| 5 | 0x1BC38000 | pi | 512 MB |
| 6 | 0x1BD38000 | rootfs | 7 GB |
| 7 | 0x1CB38000 | swap | 3.4 GB |

Sectors 0-16383 (8 MB before partition 0) contain GPT + TPL/SPL bootloader.

## Commands Reference

All commands below are run from the repo root with `./rk-flashtool`.

### Read-Only (Safe)

```bash
# List connected devices
./rk-flashtool ld

# Print partition table
./rk-flashtool ppt

# Read chip info
./rk-flashtool rci

# Read flash info
./rk-flashtool rfi

# Read device capabilities
./rk-flashtool rcb

# Read flash sectors to file (e.g., read uboot partition: 8192 sectors at LBA 0x4000)
./rk-flashtool rl 0x4000 0x2000 uboot-dump.img
```

### Write (DESTRUCTIVE — use with care)

```bash
# Write sectors from file (e.g., restore uboot partition)
./rk-flashtool wl 0x4000 uboot-backup.img

# Write to named partition
./rk-flashtool wlx uboot uboot-backup.img

# Write GPT partition table
./rk-flashtool gpt gpt-backup.img

# Erase entire flash (DANGEROUS)
./rk-flashtool ef

# Reset device
./rk-flashtool rd
```

## Restore Procedure (Loader Mode)

Restore from backup images in `asiair-backup/`:

```bash
# 1. Pre-partition bootloader area (sectors 0-16383)
./rk-flashtool wl 0 asiair-backup/pre-partition.img

# 2. GPT partition table
./rk-flashtool gpt asiair-backup/gpt.img

# 3. Individual partitions
./rk-flashtool wl 0x4000  asiair-backup/p1-uboot.img
./rk-flashtool wl 0x6000  asiair-backup/p2-misc.img
./rk-flashtool wl 0x8000  asiair-backup/p3-boot.img
./rk-flashtool wl 0x28000 asiair-backup/p4-recovery.img
# p5 (asiair) — 222 GB, restore separately if needed
./rk-flashtool wl 0x1BC38000 asiair-backup/p6-pi.img
./rk-flashtool wl 0x1BD38000 asiair-backup/p7-rootfs.img
# p8 (swap) — recreatable with mkswap, no restore needed

# 4. Reset device
./rk-flashtool rd
```

## Maskrom Recovery (Bricked Bootloader)

If the bootloader is corrupted and the device does not enter Loader mode:

1. Requires MiniLoaderAll.bin for RK3568 (not yet obtained)
2. Enter Maskrom mode (method TBD — likely eMMC CLK pin short)
3. Upload loader: `./rk-flashtool db rk3568_MiniLoaderAll.bin`
4. Proceed with restore as above

## Setup

```bash
# Install udev rule (one-time, requires sudo)
sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# Build rk-flashtool
autoreconf -i && ./configure && make
```
