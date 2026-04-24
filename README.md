# rkdeveloptool

A simple way to read/write RockChip devices over USB (rockusb protocol).

## Build & Install

### Prerequisites

```bash
sudo apt-get install libudev-dev libusb-1.0-0-dev dh-autoreconf pkg-config
```

### Compile

```bash
./autogen.sh
./configure
make
```

### Install udev rules (for non-root access)

```bash
sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

## Usage

```
rkdeveloptool -h
```

### Common Commands

| Command | Description |
|---------|-------------|
| `db <Loader>` | Download bootloader to device (Maskrom mode) |
| `ul <Loader>` | Upgrade loader |
| `rl <BeginSec> <SectorLen> <File>` | Read LBA sectors to file |
| `wl <BeginSec> <File>` | Write file to LBA sectors |
| `wlx <PartitionName> <File>` | Write file to named partition |
| `ppt` | Print partition table |
| `gpt <file>` | Write GPT partition table |
| `ef` | Erase flash |
| `rd [subcode]` | Reset device |
| `rid` | Read flash ID |
| `rfi` | Read flash info |
| `rci` | Read chip info |

### Example: Flash a kernel image

```bash
sudo ./rkdeveloptool db RKXXLoader.bin      # download bootloader to device
sudo ./rkdeveloptool wl 0x8000 kernel.img   # write kernel (0x8000 = sector offset)
sudo ./rkdeveloptool rd                     # reset device
```

## ASIAIR Plus RK3568 Support

This repo includes hardware documentation and tools for the ZWO ASIAIR Plus
(RK3568, 256 GB eMMC). See [`hardware/asiair-plus-rk3568-256g/`](hardware/asiair-plus-rk3568-256g/) for:

- Full hardware inventory and GPIO mapping
- Stock device tree source and kernel config
- Reverse-engineered `pwm_gpio` ioctl interface (DC power ports, USB power, LEDs)
- WiFi/Bluetooth firmware blobs (Broadcom AP6256)
- Backup and restore scripts

### Prerequisites

1. **Jailbreak your ASIAIR** — SSH is not enabled on stock firmware. You must
   first apply the jailbreak from [open-astro/ASIAIRJailbreak](https://github.com/open-astro/ASIAIRJailbreak)
   to enable SSH access (user: `pi`, password: `raspberry`).

2. **Install sshpass** on your local machine:
   ```bash
   sudo apt-get install sshpass
   ```

### Backup the ASIAIR Plus

The backup script streams all eMMC partitions from the ASIAIR to your local
machine over SSH. No storage needed on the device itself.

#### Run the backup

```bash
cd hardware/asiair-plus-rk3568-256g/
./backup.sh pi@asiair
```

Default credentials: user `pi`, password `raspberry` (override with
`ASIAIR_PASS=yourpass ./backup.sh pi@asiair`).

Backups are saved to `./asiair-backup/` (~7.2 GB total):

| File | Contents |
|------|----------|
| `*_gpt_primary.bin` | GPT partition table (primary) |
| `*_gpt_backup.bin` | GPT partition table (backup) |
| `*_bootloader_pre_partition.bin` | SPL/TPL bootloader (sectors 0–16383) |
| `*_p1_uboot.bin` | U-Boot (4 MB) |
| `*_p2_misc.bin` | A/B slot metadata (4 MB) |
| `*_p3_boot.bin` | Kernel + ramdisk (64 MB) |
| `*_p4_recovery.bin` | Recovery image (32 MB) |
| `*_p5_asiair_header.bin` | VFAT header (first 64 MB of 222 GB data partition) |
| `*_p6_pi.bin` | /home/pi (512 MB) |
| `*_p7_rootfs.bin` | Root filesystem (7 GB) |
| `*_checksums.sha256` | SHA256 checksums for verification |

#### Project plan

See [`hardware/asiair-plus-rk3568-256g/plan.md`](hardware/asiair-plus-rk3568-256g/plan.md)
for the full project plan: backup, custom kernel/U-Boot, Debian install, and
AlpacaBridge deployment.

## Troubleshooting

### `PKG_CHECK_MODULES` error during configure

```
./configure: line 4269: syntax error near unexpected token `LIBUSB1,libusb-1.0'
```

Install pkg-config:

```bash
sudo apt-get install pkg-config libusb-1.0
```
