# ASIAIR Plus RK3568 — Debian Conversion Plan

Goal: Replace stock ASIAIR Plus firmware with Debian + AlpacaBridge, with full
hardware support (USB, DC power ports, WiFi, BT, LEDs, button) and the ability
to restore to stock at any time.

**Prerequisite:** ASIAIR must be jailbroken for SSH access using
[open-astro/ASIAIRJailbreak](https://github.com/open-astro/ASIAIRJailbreak)
before any of this work is possible.

---

## Phase 1: Investigation & Documentation

- [x] Identify SoC (RK3568, 4x Cortex-A55)
- [x] Map eMMC partition layout (8 partitions: uboot, misc, boot, recovery, asiair, pi, rootfs, swap)
- [x] Extract device tree source (asiair-plus.dts / .dtb)
- [x] Extract stock kernel config (asiair-kernel.config)
- [x] Decode GPIO mapping — DC power ports, USB power, LEDs, button
- [x] Reverse-engineer pwm_gpio.ko ioctl interface (pwm_gpio.h)
- [x] Identify WiFi chip (Broadcom AP6256 / BCM43456, bcmdhd_wifi6 driver)
- [x] Identify Bluetooth chip (BCM4345C5, integrated with WiFi)
- [x] Capture WiFi/BT firmware blobs (fw_bcm43456c5_ag.bin, BCM4345C5.hcd, nvram_ap6256.txt)
- [x] Catalog everything into hardware/asiair-plus-rk3568-256g/

## Phase 2: Full Backup (BEFORE touching anything)

- [x] Write backup script (streams from ASIAIR via SSH to local machine)
- [x] Dump pre-partition bootloader area (sectors 0–16383, 8 MB)
- [x] Dump partition 1 — uboot (4 MB)
- [x] Dump partition 2 — misc (4 MB)
- [x] Dump partition 3 — boot (64 MB, kernel + ramdisk)
- [x] Dump partition 4 — recovery (32 MB)
- [x] Dump partition 5 — asiair VFAT header (first 64 MB of 222 GB — full image backup available separately)
- [x] Dump partition 6 — pi (512 MB, /home/pi)
- [x] Dump partition 7 — rootfs (7 GB, stock root filesystem)
- [x] Partition 8 — swap (3.4 GB) — skipped, recreatable with mkswap
- [x] Dump GPT partition table (primary + backup)
- [x] Verify backups with SHA256 checksums
- [x] Transfer backups to local machine (7.7 GB total in asiair-backup/)
- [ ] Test: confirm backup can be written back with dd (dry run on offset check)

## Phase 3: rk-flashtool RK3568 Support (Brick Recovery Safety Net)

- [x] Add RK3568 USB PID (0x350b) to RKScan.cpp VID/PID table
- [x] Add RK3568 device type to DefineHeader.h enum
- [x] Add RK3568 udev rule to 99-rk-rockusb.rules
- [x] Build rk-flashtool with RK3568 support
- [x] Obtain RK3568 SPL loader (rk356x_spl_loader_v1.23.114.bin from rkbin repo)
- [x] Test: verify rk-flashtool detects RK3568 (reports PID 0x350a in Loader mode, chip info "3568")
- [x] Document rk-flashtool usage, restore procedure, and recovery guide (flashtool-recovery.md)
- [x] Document Maskrom recovery (tested 2026-04-24 — device enters Maskrom automatically when bootloader is corrupted)

## Phase 4: U-Boot

- [x] Decide: mainline U-Boot (2025.x, generic-rk3568 defconfig)
- [x] Set up cross-compilation toolchain (aarch64-linux-gnu-gcc 14.2)
- [x] Build TPL/SPL + U-Boot proper for RK3568 (BL31 v1.45, DDR 1560MHz v1.23)
- [x] Build idbloader.img (TPL + SPL merged, 198K) + u-boot.itb (U-Boot + ATF, 1003K)
- [x] Flash to ASIAIR Plus (idbloader at sector 0x40, u-boot.itb at sector 0x4000)
- [x] Test: mainline U-Boot boots ASIAIR Plus, stock kernel loads, SSH works
- [ ] Verify: U-Boot serial console (no UART pads found — ZWO removed debug headers)
- [ ] Configure U-Boot to boot from eMMC with standard distro boot (extlinux.conf)
- [ ] Create ASIAIR Plus board-specific U-Boot device tree (optional, generic works)

## Phase 5: Kernel

- [x] Decide: mainline Linux 7.0 (arm64 defconfig, brcmfmac WiFi, libgpiod for DC ports)
- [x] Clone mainline kernel source
- [x] Create ASIAIR Plus device tree (rk3568-asiair-plus.dts)
  - [x] RK3568 base SoC
  - [x] eMMC (sdhci, Samsung 256GB)
  - [x] USB host controllers (xHCI + EHCI/OHCI + USB2/3 PHY)
  - [x] USB power enable regulators (4 ports, GPIO-controlled)
  - [x] Ethernet (GMAC0, RGMII, PHY reset GPIO1_B1)
  - [x] WiFi SDIO (AP6256 / brcmfmac, pwrseq via GPIO2_B1)
  - [ ] Bluetooth UART
  - [x] LED definitions (gpio-leds: power, activity, network, status)
  - [x] Button input (gpio-keys: GPIO0_A5)
  - [x] Thermal management (TSADC)
  - [x] Power domains (pmu_io_domains)
  - N/A: HDMI (no connector on board)
- [x] Configure kernel (arm64 defconfig — all drivers already enabled)
- [x] Build kernel Image (42MB) + dtb (58KB) + modules
- [x] WiFi: mainline brcmfmac (in defconfig as module)
- [ ] DC power ports: libgpiod from userspace (GPIO4_C2/C3/C5/C6)
- [ ] Test: boot custom kernel on ASIAIR Plus

## Phase 6: Debian Root Filesystem

- [x] Create arm64 Debian rootfs via debootstrap (trixie)
- [x] Install essential packages (systemd, network-manager, openssh-server, etc.)
- [ ] Configure networking (WiFi AP mode + station mode, ethernet)
- [x] Configure hostname, users, SSH keys (scripts/debian/asiair-rootfs-setup.sh)
- [x] Install WiFi/BT firmware blobs to /lib/firmware/ (scripts/debian/asiair-rootfs-setup.sh)
- [x] Install kernel modules (scripts/debian/asiair-rootfs-setup.sh)
- [x] Create fstab for eMMC partitions (scripts/debian/asiair-create-image.sh)
- [x] Set up boot configuration (extlinux.conf via scripts/debian/asiair-create-image.sh)
- [ ] Test: boot Debian on ASIAIR Plus
- [ ] Verify: SSH access works
- [ ] Verify: WiFi works (both AP and station mode)
- [ ] Verify: Ethernet works
- [ ] Verify: USB ports work (connect camera/mount)
- [ ] Verify: DC power ports controllable
- [ ] Verify: LEDs controllable
- [ ] Verify: Button input works

## Phase 7: AlpacaBridge & Application Stack

- [ ] Research AlpacaBridge requirements (runtime, dependencies)
- [ ] Install AlpacaBridge on Debian
- [ ] Configure ASCOM Alpaca device drivers
- [ ] Test: connect telescope equipment via USB
- [ ] Test: control DC power ports from AlpacaBridge
- [ ] Test: full astrophotography workflow
- [ ] Performance tuning (disable unnecessary services, optimize for real-time)

## Phase 8: Restore & Recovery Documentation

- [x] Document full restore procedure (flashtool-recovery.md — partition by partition via rk-flashtool)
- [x] Document rk-flashtool Maskrom recovery procedure (flashtool-recovery.md — tested 2026-04-24)
- [x] Create flash script (scripts/debian/asiair-flash.sh)
- [x] Test: full restore to stock firmware from backup (2026-04-24)
- [x] Test: full restore from bricked state via rk-flashtool (2026-04-24, Maskrom recovery)

---

## Partition Layouts

### Stock ASIAIR Partition Table (GPT)

| # | Name     | Start Sector | Size    | Format     | Purpose                          |
|---|----------|-------------|---------|------------|----------------------------------|
| 1 | uboot    | 0x4000      | 4 MB    | raw (FDT)  | Rockchip U-Boot                  |
| 2 | misc     | 0x6000      | 4 MB    | raw        | A/B slot metadata                |
| 3 | boot     | 0x8000      | 64 MB   | raw        | Android boot image (kernel)      |
| 4 | recovery | 0x28000     | 32 MB   | raw (FDT)  | Recovery image                   |
| 5 | asiair   | 0x38000     | 222 GB  | VFAT       | Image storage (astrophotography) |
| 6 | pi       | 0x1BC38000  | 512 MB  | ext4       | /home/pi                         |
| 7 | rootfs   | 0x1BD38000  | 7 GB    | ext4       | Stock root filesystem (read-only)|
| 8 | swap     | 0x1CB38000  | 3.4 GB  | linux-swap | Swap                             |

Pre-partition area: sectors 0–16383 (8 MB) contain GPT header + TPL/SPL bootloader.

### Debian Partition Table (GPT) — new layout for 32GB and 256GB units

| # | Name   | Start Sector | Size           | Format | Purpose                        |
|---|--------|-------------|----------------|--------|--------------------------------|
| 1 | uboot  | 0x4000      | 4 MB           | raw    | Mainline U-Boot (u-boot.itb)   |
| 2 | boot   | 0x6000      | 256 MB         | ext4   | Kernel + DTB + extlinux.conf   |
| 3 | rootfs | 0x86000     | (all remaining - 1 GB) | ext4 | Debian OS (auto-resized on first boot) |
| 4 | swap   | (end - 1GB) | 1 GB           | swap   | Swap                           |

Pre-partition area: sectors 0–16383 (8 MB) — idbloader.img at sector 0x40.

This layout works on any eMMC size. The rootfs image ships small (~1.2 GB)
and expands to fill available space on first boot via resize2fs.

---

## Build Dependencies (Debian/Ubuntu)

### rk-flashtool (Phase 3)

```bash
sudo apt install build-essential autoconf automake libusb-1.0-0-dev pkg-config
```

### U-Boot Cross-Compilation (Phase 4)

```bash
sudo apt install gcc-aarch64-linux-gnu bison flex swig python3-dev \
  python3-setuptools python3-pyelftools device-tree-compiler bc libssl-dev
```

### Kernel Build + Debian Rootfs (Phase 5 & 6)

```bash
sudo apt install debootstrap qemu-user-static
```

### Flashing & Debugging

```bash
sudo apt install strace sfdisk
```

### Create Debian Trixie arm64 Rootfs

```bash
sudo debootstrap --arch=arm64 \
  --include=systemd,systemd-sysv,openssh-server,network-manager,wpasupplicant,hostapd,sudo,vim-tiny,less,locales,dbus,iproute2,iputils-ping,wget,curl,ca-certificates,usbutils,pciutils,kmod \
  trixie /home/dev/Documents/GitHub/asiair-rootfs http://deb.debian.org/debian
```

### External Repos (cloned alongside rkdeveloptool)

| Repo | Purpose | URL |
|------|---------|-----|
| u-boot | Mainline U-Boot source | https://github.com/u-boot/u-boot.git |
| rkbin | Rockchip DDR blob + BL31 firmware | https://github.com/rockchip-linux/rkbin.git |
| linux | Mainline Linux kernel source | https://github.com/torvalds/linux.git |

---

## Files in This Directory

| File | Description |
|------|-------------|
| plan.md | This file — project plan and progress tracker |
| flashtool-recovery.md | rk-flashtool usage, restore procedure, Maskrom recovery |
| inventory.md | Complete hardware inventory with GPIO maps |
| asiair-plus.dts | Stock device tree source (decompiled from live system) |
| asiair-plus.dtb | Stock device tree blob (binary) |
| asiair-kernel.config | Stock kernel config (4.19.219) |
| pwm_gpio.ko | Stock ZWO power control kernel module |
| pwm_gpio.h | Reverse-engineered ioctl header for pwm_gpio |
| fw_bcm43456c5_ag.bin | WiFi firmware (main) |
| fw_bcm43456c5_ag_apsta.bin | WiFi firmware (AP+STA mode) |
| fw_bcm43456c5_ag_p2p.bin | WiFi firmware (P2P mode) |
| nvram_ap6256.txt | WiFi NVRAM calibration data |
| BCM4345C5.hcd | Bluetooth firmware |
