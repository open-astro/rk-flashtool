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

The device should appear as `Vid=0x2207,Pid=0x350a` in `sudo ./rk-flashtool ld`.

### Entering Maskrom Mode

If the bootloader is corrupted, the SoC may fall to Maskrom automatically on
power-up. If it does NOT (device not visible on `lsusb`), force Maskrom by
shorting the eMMC data lines:

1. Remove the ASIAIR Plus enclosure (4 corner screws)
2. Locate the **eMMC chip** — small BGA chip with QR code label, to the right
   of the RK3568B2 SoC (board marking: ASI AIR PLUS V2.3)
3. With the device **unpowered** (no USB, no 12V), connect the USB-C cable to the PC
4. Run the USB watch loop on the PC:
   ```bash
   while true; do lsusb 2>/dev/null | grep 2207 && echo "FOUND" && break; sleep 0.1; done
   ```
5. Lay a **paper clip or conductive wire across the top of the eMMC chip** to short
   the data lines — this prevents the BootROM from reading eMMC
6. While holding the short, **plug in 12V power and turn on**
7. When "FOUND" appears in the terminal, **remove the paper clip immediately**
8. The device should now show as Maskrom in `sudo ./rk-flashtool ld`

**GND reference:** Capacitor **C3816** on the PCB, or any of the brass mounting
standoffs in the corners.

**Important:** Remove the short before running any flash commands — the eMMC must
be accessible for writes to succeed.

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

All commands below are run from the repo root with `sudo ./rk-flashtool`.

### Read-Only (Safe)

```bash
# List connected devices
sudo ./rk-flashtool ld

# Print partition table
sudo ./rk-flashtool ppt

# Read chip info
sudo ./rk-flashtool rci

# Read flash info
sudo ./rk-flashtool rfi

# Read device capabilities
sudo ./rk-flashtool rcb

# Read flash sectors to file (e.g., read uboot partition: 8192 sectors at LBA 0x4000)
sudo ./rk-flashtool rl 0x4000 0x2000 uboot-dump.img
```

### Write (DESTRUCTIVE — use with care)

```bash
# Write sectors from file (e.g., restore uboot partition)
sudo ./rk-flashtool wl 0x4000 uboot-backup.img

# Write to named partition
sudo ./rk-flashtool wlx uboot uboot-backup.img

# Write GPT partition table
sudo ./rk-flashtool gpt gpt-backup.img

# Erase entire flash (DANGEROUS)
sudo ./rk-flashtool ef

# Reset device
sudo ./rk-flashtool rd
```

## Restore Procedure (Loader Mode)

If U-Boot is still running (device shows as `Loader` in `sudo ./rk-flashtool ld`),
you can restore directly without uploading a loader first.

Restore from backup images in `asiair-backup/`:

```bash
# 1. Pre-partition bootloader area (sectors 0-16383)
sudo ./rk-flashtool wl 0 asiair-backup/20260423_bootloader_pre_partition.bin

# 2. GPT partition table
sudo ./rk-flashtool gpt asiair-backup/20260423_gpt_primary.bin

# 3. Individual partitions
sudo ./rk-flashtool wl 0x4000  asiair-backup/20260423_p1_uboot.bin
sudo ./rk-flashtool wl 0x6000  asiair-backup/20260423_p2_misc.bin
sudo ./rk-flashtool wl 0x8000  asiair-backup/20260423_p3_boot.bin
sudo ./rk-flashtool wl 0x28000 asiair-backup/20260423_p4_recovery.bin
sudo ./rk-flashtool wl 0x38000 asiair-backup/20260423_p5_asiair_header.bin  # first 64 MB only
sudo ./rk-flashtool wl 0x1BC38000 asiair-backup/20260423_p6_pi.bin
sudo ./rk-flashtool wl 0x1BD38000 asiair-backup/20260423_p7_rootfs.bin
sudo ./rk-flashtool wl 0x1CB38000 asiair-backup/20260423_p8_swap.bin        # if backup exists

# 4. Reset device
sudo ./rk-flashtool rd
```

**Notes:**
- The rootfs image (p7) is 7 GB. USB writes of files this large may time out.
  If the rootfs was never modified (e.g., only the bootloader was changed), it
  does not need to be restored.
- p5 (asiair) is 222 GB — only the first 64 MB header was backed up. The full
  partition contains ASIAIR capture data (FITS files, darks, etc.) and is too
  large for a sector-level backup. The VFAT filesystem header is enough to make
  it mountable; user data must be restored separately.
- p8 (swap) can be recreated if no backup exists: boot into Linux and run
  `mkswap /dev/mmcblk0p8`. The stock fstab enables it automatically.

## Maskrom Recovery (Bricked Bootloader) — TESTED 2026-04-24, 2026-04-25

If the bootloader is corrupted, the device may enter Maskrom mode automatically
on power-up. If it does not (SYS LED blinks 5 times then powers off, device not
visible on `lsusb`), you must force Maskrom via the eMMC short method described
in "Entering Maskrom Mode" above.

In Maskrom mode, `sudo ./rk-flashtool ld` reports `Maskrom` instead of `Loader`.

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
sudo ./rk-flashtool ld
# Expected: DevNo=1  Vid=0x2207,Pid=0x350a,LocationID=...  Maskrom

# 2. Upload SPL loader to RAM (gives temporary flash access)
sudo ./rk-flashtool db ../rkbin/rk356x_spl_loader_v1.23.114.bin
# Expected: "Downloading bootloader succeeded."
#
# If `db` fails with PIPE errors (-9), do a full power cycle:
#   - Unplug USB + 12V, wait 30 seconds
#   - If device doesn't appear in Maskrom after power-on, use the eMMC
#     short method (see "Entering Maskrom Mode" above)
#   - Run `db` immediately after the device appears — don't run `ld` first

# 3. Wait 2 seconds for the loader to initialize
sleep 2

# 4. Restore stock pre-partition bootloader (8 MB, sectors 0-16383)
#    This contains GPT header + TPL/SPL.
sudo ./rk-flashtool wl 0 asiair-backup/20260423_bootloader_pre_partition.bin

# 5. Restore stock U-Boot (4 MB at sector 0x4000)
sudo ./rk-flashtool wl 0x4000 asiair-backup/20260423_p1_uboot.bin

# 6. Restore remaining partitions
sudo ./rk-flashtool wl 0x6000  asiair-backup/20260423_p2_misc.bin
sudo ./rk-flashtool wl 0x8000  asiair-backup/20260423_p3_boot.bin
sudo ./rk-flashtool wl 0x28000 asiair-backup/20260423_p4_recovery.bin
sudo ./rk-flashtool wl 0x38000 asiair-backup/20260423_p5_asiair_header.bin  # first 64 MB only

# 7. (Optional) Restore pi, rootfs, swap — only if they were modified
# sudo ./rk-flashtool wl 0x1BC38000 asiair-backup/20260423_p6_pi.bin
# sudo ./rk-flashtool wl 0x1BD38000 asiair-backup/20260423_p7_rootfs.bin  # 7 GB — may time out
# p8 (swap) — no backup, recreate with: mkswap /dev/mmcblk0p8

# 8. Reset device
sudo ./rk-flashtool rd
```

After steps 1-6, the device should boot to stock ASIAIR firmware and appear
on WiFi at `10.0.0.1`. Steps 1-6 take under 2 minutes.

### Troubleshooting: Device not visible on USB

If the device does not appear on `lsusb` at all (no Rockchip 2207 device):

1. The ASIAIR power management MCU may be shutting down the SoC before USB
   enumerates. Symptom: SYS LED blinks 5 times, then device powers off.
2. The BootROM in the RK3568 SoC **cannot be bricked** — it is mask ROM in silicon.
   If the SoC has power and USB, it will always enumerate in Maskrom when it
   cannot find a valid bootloader on eMMC.
3. If the MCU is killing power too quickly, the only solution is to **force Maskrom
   via the eMMC data line short** (see "Entering Maskrom Mode"). This prevents the
   BootROM from reading eMMC at all, so it enters Maskrom USB mode before the
   MCU's boot timeout fires.
4. Try multiple USB cables (USB-C to C and USB-C to A) and multiple USB ports.
5. Unplug everything for 5+ minutes to fully drain the MCU before retrying.

### Troubleshooting: `db` command fails (PIPE / timeout errors)

The `db` command uploads a loader to RAM via USB vendor requests (0x471/0x472).
It can fail with LIBUSB_ERROR_PIPE (-9) or LIBUSB_ERROR_TIMEOUT (-7) if the
USB control endpoint is stalled from prior failed attempts.

1. **Full power cycle** — unplug USB + 12V, wait 30 seconds, reconnect
2. **USB reset** — `sudo usbreset /dev/bus/usb/XXX/YYY` (get path from `lsusb`)
3. **Fresh Maskrom entry** — use the eMMC short method for a clean Maskrom state
4. **Run `db` as the first command** — don't run `ld` or other commands first,
   as they can leave the USB endpoint in a bad state
5. rk-flashtool has built-in retry logic (3 attempts with USB reset between each)

### Incident Log

**2026-04-24:** Mainline U-Boot (idbloader.img + u-boot.itb) was flashed to the
pre-partition area and uboot partition. It worked initially but subsequently
failed to boot, leaving the device in Maskrom mode. The device entered Maskrom
automatically (no eMMC short needed). Recovery restored the stock Rockchip
bootloader. The rootfs, pi, asiair, and other partitions were untouched.

**2026-04-25:** Debian image (new GPT + mainline U-Boot + mainline kernel + Debian
rootfs) was flashed via `asiair-flash.sh`. Device booted but kernel failed to
start — SYS LED blinked 5 times and MCU powered off the device. After power-off,
the device would not enter Maskrom on its own (MCU killed power before USB could
enumerate). The `db` command also failed repeatedly with PIPE errors. Recovery
required opening the case and **shorting the eMMC data lines with a paper clip**
to force Maskrom entry (see "Entering Maskrom Mode"). Once in Maskrom, `db`
succeeded on the first try with a fresh USB connection, and stock firmware was
restored via the `wl` commands above.

## Setup

```bash
# Install udev rule (one-time, requires sudo)
sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# Build rk-flashtool
autoreconf -i && ./configure && make
```
