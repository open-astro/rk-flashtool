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
- [ ] Obtain RK3568 MiniLoaderAll.bin (from Rockchip repo or extract from stock)
- [x] Test: verify rk-flashtool detects RK3568 (reports PID 0x350a in Loader mode, chip info "3568")
- [x] Document rk-flashtool usage, restore procedure, and recovery guide (flashtool-recovery.md)
- [ ] Document how to enter Maskrom mode on ASIAIR Plus (needs PCB inspection for eMMC CLK pin)

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

- [ ] Decide: Rockchip BSP 4.19 (all drivers work) vs mainline 6.x (modern, needs porting)
- [ ] Fork/clone chosen kernel source
- [ ] Create ASIAIR Plus device tree (.dts) for chosen kernel
  - [ ] RK3568 base SoC
  - [ ] eMMC (sdhci)
  - [ ] USB host controllers (DWC3/xHCI)
  - [ ] Ethernet (GMAC)
  - [ ] WiFi SDIO (AP6256 / bcmdhd or brcmfmac)
  - [ ] Bluetooth UART
  - [ ] GPIO bank definitions
  - [ ] PWM GPIO / airplus-gpios node
  - [ ] LED definitions (gpio-leds)
  - [ ] DC power port GPIO mapping
  - [ ] USB power enable regulators
  - [ ] HDMI output
  - [ ] Thermal management (TSADC)
- [ ] Configure kernel (.config)
  - [ ] Start from stock config or defconfig
  - [ ] Enable required drivers (WiFi, BT, USB, GPIO, PWM, LEDs)
  - [ ] Enable Debian-required features (cgroups, namespaces, systemd support)
- [ ] Build kernel Image + dtb + modules
- [ ] Decide pwm_gpio driver strategy:
  - [ ] Option A: Port stock pwm_gpio.ko to new kernel (easiest)
  - [ ] Option B: Rewrite as proper mainline driver
  - [ ] Option C: Use libgpiod from userspace (no kernel module needed)
- [ ] WiFi driver strategy:
  - [ ] Option A: Use Rockchip bcmdhd_wifi6 fork (proven, but out-of-tree)
  - [ ] Option B: Use mainline brcmfmac (cleaner, but may need firmware tweaks)
- [ ] Test: boot custom kernel on ASIAIR Plus

## Phase 6: Debian Root Filesystem

- [ ] Create arm64 Debian rootfs via debootstrap (bookworm or trixie)
- [ ] Install essential packages (systemd, network-manager, openssh-server, etc.)
- [ ] Configure networking (WiFi AP mode + station mode, ethernet)
- [ ] Configure hostname, users, SSH keys
- [ ] Install WiFi/BT firmware blobs to /lib/firmware/
- [ ] Install kernel modules
- [ ] Create fstab for eMMC partitions
- [ ] Set up boot configuration (extlinux.conf or boot.scr)
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

- [ ] Document full restore procedure (dd-based, partition by partition)
- [ ] Document rk-flashtool Maskrom recovery procedure
- [ ] Create one-command restore script
- [ ] Test: full restore to stock firmware from backup
- [ ] Test: full restore from bricked state via rk-flashtool

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

### External Repos (cloned alongside rkdeveloptool)

| Repo | Purpose | URL |
|------|---------|-----|
| u-boot | Mainline U-Boot source | https://github.com/u-boot/u-boot.git |
| rkbin | Rockchip DDR blob + BL31 firmware | https://github.com/rockchip-linux/rkbin.git |

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
