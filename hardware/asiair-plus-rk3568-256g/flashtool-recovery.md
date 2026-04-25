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

If U-Boot is still running (device shows as `Loader` in `./rk-flashtool ld`),
you can restore directly without uploading a loader first.

Restore from backup images in `asiair-backup/`:

```bash
# 1. Pre-partition bootloader area (sectors 0-16383)
./rk-flashtool wl 0 asiair-backup/20260423_bootloader_pre_partition.bin

# 2. GPT partition table
./rk-flashtool gpt asiair-backup/20260423_gpt_primary.bin

# 3. Individual partitions
./rk-flashtool wl 0x4000  asiair-backup/20260423_p1_uboot.bin
./rk-flashtool wl 0x6000  asiair-backup/20260423_p2_misc.bin
./rk-flashtool wl 0x8000  asiair-backup/20260423_p3_boot.bin
./rk-flashtool wl 0x28000 asiair-backup/20260423_p4_recovery.bin
# p5 (asiair) — 222 GB, restore separately if needed
./rk-flashtool wl 0x1BC38000 asiair-backup/20260423_p6_pi.bin
./rk-flashtool wl 0x1BD38000 asiair-backup/20260423_p7_rootfs.bin
# p8 (swap) — recreatable with mkswap, no restore needed

# 4. Reset device
./rk-flashtool rd
```

**Note:** The rootfs image is 7 GB. USB writes of files this large may time out.
If the rootfs was never modified (e.g., only the bootloader was changed), it does
not need to be restored.

## Maskrom Recovery (Bricked Bootloader) — TESTED 2026-04-24

If the bootloader is corrupted, the device enters Maskrom mode automatically on
power-up. No eMMC CLK pin short is needed — the SoC falls through to Maskrom
when it cannot find a valid bootloader.

The device still shows `Vid=0x2207,Pid=0x350a` on USB, but `./rk-flashtool ld`
reports `Maskrom` instead of `Loader`. In Maskrom mode, flash commands (rci, rfi,
wl, etc.) fail until a loader is uploaded to RAM.

### Prerequisites

- `rk356x_spl_loader_v1.23.114.bin` from the rkbin repo
  (located at `../../rkbin/rk356x_spl_loader_v1.23.114.bin` relative to this file,
   or `../../../rkbin/rk356x_spl_loader_v1.23.114.bin` from the repo root)
- Backup images in `asiair-backup/`
- USB-C cable connected between ASIAIR and PC
- 12V DC power to the ASIAIR

### Step-by-Step (tested, recovered a device from this state)

```bash
# 1. Verify device is in Maskrom mode
./rk-flashtool ld
# Expected: DevNo=1  Vid=0x2207,Pid=0x350a,LocationID=...  Maskrom

# 2. Upload SPL loader to RAM (gives temporary flash access)
./rk-flashtool db ../rkbin/rk356x_spl_loader_v1.23.114.bin
# Expected: "Downloading bootloader succeeded."

# 3. Wait 2 seconds, then verify flash access
sleep 2
./rk-flashtool rci
# Expected: Chip Info: 38 36 35 33 ... (= "3568")

# 4. Restore stock pre-partition bootloader (8 MB, sectors 0-16383)
#    This contains GPT header + TPL/SPL — the critical piece that was broken.
./rk-flashtool wl 0 asiair-backup/20260423_bootloader_pre_partition.bin

# 5. Restore stock U-Boot (4 MB at sector 0x4000)
./rk-flashtool wl 0x4000 asiair-backup/20260423_p1_uboot.bin

# 6. Restore remaining boot partitions
./rk-flashtool wl 0x6000  asiair-backup/20260423_p2_misc.bin
./rk-flashtool wl 0x8000  asiair-backup/20260423_p3_boot.bin
./rk-flashtool wl 0x28000 asiair-backup/20260423_p4_recovery.bin

# 7. (Optional) Restore pi and rootfs — only if they were modified
# ./rk-flashtool wl 0x1BC38000 asiair-backup/20260423_p6_pi.bin
# ./rk-flashtool wl 0x1BD38000 asiair-backup/20260423_p7_rootfs.bin  # 7 GB — may time out

# 8. Device will reboot automatically after the loader times out,
#    or may transition to Loader mode. If it stays connected:
./rk-flashtool rd
```

After steps 1-6, the device should boot to stock ASIAIR firmware and appear
on WiFi at `10.0.0.1`. Steps 1-6 take under 2 minutes.

### What went wrong (2026-04-24 incident)

Mainline U-Boot (idbloader.img + u-boot.itb) was flashed to the pre-partition
area and uboot partition. It worked initially but subsequently failed to boot,
leaving the device in Maskrom mode. Recovery restored the stock Rockchip
bootloader to those same regions. The rootfs, pi, asiair, and other partitions
were untouched and did not need restoration.

## Setup

```bash
# Install udev rule (one-time, requires sudo)
sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# Build rk-flashtool
autoreconf -i && ./configure && make
```
