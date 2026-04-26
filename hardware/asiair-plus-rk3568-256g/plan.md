# ASIAIR Plus RK3568 — Debian Conversion Plan

Goal: Replace stock ASIAIR Plus firmware with Debian + AlpacaBridge, with full
hardware support (USB, DC power ports, WiFi, BT, LEDs, button) and the ability
to restore to stock at any time.

**Prerequisite:** ASIAIR must be jailbroken for SSH access using
[open-astro/ASIAIRJailbreak](https://github.com/open-astro/ASIAIRJailbreak)
before any of this work is possible.

**Approach:** Stock kernel (4.19.219) + Debian Trixie userland. Only the rootfs
partition (p7) is replaced. Stock bootloader, kernel, DTB, and partition table
are preserved unchanged. Mainline kernel migration is a future project.

---

## Phase 1: Investigation & Documentation — COMPLETE

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

## Phase 2: Full Backup — COMPLETE

- [x] Write backup script (streams from ASIAIR via SSH to local machine)
- [x] Dump all partitions (pre-partition bootloader, p1-p7, GPT tables)
- [x] Verify backups with SHA256 checksums
- [x] Transfer backups to local machine (7.7 GB total in asiair-backup/)

## Phase 3: rk-flashtool RK3568 Support — COMPLETE

- [x] Add RK3568 USB PID (0x350b) to RKScan.cpp VID/PID table
- [x] Add RK3568 device type to DefineHeader.h enum
- [x] Add RK3568 udev rule to 99-rk-rockusb.rules
- [x] Build rk-flashtool with RK3568 support
- [x] Test: verify rk-flashtool detects RK3568 in Maskrom and Loader mode
- [x] Document rk-flashtool usage, restore procedure, and recovery guide (flashtool-recovery.md)
- [x] Document Maskrom recovery (tested — device enters Maskrom automatically when bootloader is corrupted)

## Phase 4: Debian Trixie Installation — COMPLETE

- [x] Create arm64 Debian rootfs via debootstrap (trixie)
- [x] Install essential packages (systemd, network-manager, openssh-server, etc.)
- [x] Configure hostname (astro), users (astro/astro), SSH keys
- [x] Install stock kernel modules (4.19.219) from backup
- [x] Install stock WiFi/BT firmware blobs from backup
- [x] Configure fstab for stock partition layout (p7=root, p8=swap, p6=/home)
- [x] Configure pwm_gpio auto-load via modules-load.d
- [x] Build rootfs ext4 image (4 GB)
- [x] Flash rootfs to p7 (stock bootloader + kernel untouched)
- [x] Boot Debian Trixie on ASIAIR Plus — SUCCESS (2026-04-25)
- [x] Verify: SSH access works
- [x] Verify: USB ports work
- [x] Verify: GPIO (DC power ports) works

## Phase 5: Hardware Verification — IN PROGRESS

- [x] SSH access
- [x] USB ports (camera/mount connected)
- [x] GPIO / DC power ports (pwm_gpio driver)
- [ ] WiFi (AP mode + station mode via NetworkManager)
- [ ] Ethernet
- [ ] Bluetooth
- [ ] LEDs controllable
- [ ] Button input

## Phase 6: AlpacaBridge & Application Stack

- [ ] Research AlpacaBridge requirements (runtime, dependencies)
- [ ] Install AlpacaBridge on Debian
- [ ] Configure ASCOM Alpaca device drivers
- [ ] Test: connect telescope equipment via USB
- [ ] Test: control DC power ports from AlpacaBridge
- [ ] Test: full astrophotography workflow

## Phase 7: Restore & Recovery — COMPLETE

- [x] Document full restore procedure (flashtool-recovery.md)
- [x] Create flash scripts (flash-all, flash-boot, flash-rootfs)
- [x] Test: full restore to stock firmware from backup
- [x] Test: full restore from bricked state via Maskrom recovery

---

## Key Architecture Decisions

### Stock kernel, not mainline

Mainline kernel (6.12.x) was built and tested but caused MCU 5-blink shutdown on
boot. The ASIAIR's MCU appears to require specific hardware initialization that only
the stock Rockchip BSP kernel (4.19.219) provides. Rather than reverse-engineering
the MCU protocol, we keep the entire stock boot chain and only replace the rootfs.

Stock DTB bootargs: `root=PARTUUID=614e0000-0000 rootfstype=ext4 ro rootwait`
Boot.img cmdline is empty — U-Boot uses DTB `chosen` node bootargs.

### Stock partition table preserved

No repartitioning. All 8 stock partitions stay. Only p7 (rootfs) contents change.
This means stock recovery (p4) and stock U-Boot (p1) remain as fallbacks.

---

## Build Dependencies (Debian/Ubuntu host)

### rk-flashtool
```bash
sudo apt install build-essential autoconf automake libusb-1.0-0-dev pkg-config
```

### Debian Rootfs
```bash
sudo apt install debootstrap qemu-user-static
```

### Debootstrap Command
```bash
sudo debootstrap --arch=arm64 \
  --include=systemd,systemd-sysv,openssh-server,network-manager,wpasupplicant,sudo,vim-tiny,less,locales,dbus,iproute2,iputils-ping,wget,curl,ca-certificates,usbutils,pciutils,kmod \
  trixie /home/dev/Documents/GitHub/asiair-rootfs http://deb.debian.org/debian
```

---

## External Repos (cloned alongside rk-flashtool)

| Repo | Purpose |
|------|---------|
| rkbin | Rockchip DDR blob + SPL loader for Maskrom recovery |

Note: u-boot and linux repos were used for the mainline kernel attempt and are no
longer needed for the stock kernel approach.
