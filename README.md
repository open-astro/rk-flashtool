# OpenAstro Linux - Debian 13 Trixie for the ASIAIR Plus Rockchip

<img src="https://www.openastro.net/wp-content/uploads/2026/04/OpenAstro_logo.png" alt="AlpacaBridge logo" width="420">

Replace the stock ZWO firmware on your ASIAIR Plus with **Debian 13 (Trixie)** while keeping full hardware support - USB, WiFi, DC power ports, LEDs, and GPIO. Restore to stock at any time from your backup.

## Supported Hardware

| Device | SoC | Storage | Status |
|--------|-----|---------|--------|
| ASIAIR Plus 256GB | RK3568 | 232 GB eMMC | Fully supported |

The ASIAIR Mini (RV1126) is documented in [`hardware/asiair-mini-rv1126/`](hardware/asiair-mini-rv1126/) but not yet supported for flashing.

## How It Works

OpenAstro Linux uses the **stock ASIAIR bootloader and kernel** - only the root filesystem (partition 7) is replaced with Debian Trixie. This means:

- Stock boot chain is untouched (bootloader, kernel, device tree)
- All hardware works out of the box (same drivers as stock)
- Restore to stock firmware at any time with one command
- No repartitioning - stock partition table is preserved

## Install

### 1. Build rk-flashtool

```bash
sudo apt install build-essential autoconf automake libusb-1.0-0-dev pkg-config sshpass python3 wget curl
git clone https://github.com/open-astro/rk-flashtool.git
cd rk-flashtool
./autogen.sh && ./configure && make
```

### 2. Install udev rules

```bash
sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

### 3. Run the installer

Power on your ASIAIR and connect it to the same network as your PC, then:

```bash
sudo scripts/install
```

The installer handles everything automatically:

1. **Jailbreaks** your ASIAIR to enable SSH (over the network, no physical access)
2. **Backs up** all partitions over SSH (~7.7 GB) - your only way back to stock
3. **Downloads** the OpenAstro Linux image from GitHub Releases
4. **Sets up the WiFi hotspot** - enabled by default like the other OpenAstro boards: the unit broadcasts its own network (like the stock ASIAIR); join it and reach the unit at `astro@172.24.1.1`. SSID `OpenAstro-XXXX` (XXXX = last 4 of the WiFi MAC), password `12345678`; change it later from the AlpacaBridge portal, override with `OPENASTRO_SSID`/`OPENASTRO_PSK`/`OPENASTRO_COUNTRY`, or set `OPENASTRO_WIFI=no` to skip and use wired Ethernet only
5. **Pauses** and asks you to enter Loader mode (hold the reset button while powering on)
6. **Flashes** the stock boot chain from your backup + OpenAstro Linux rootfs

Total time: ~15 minutes (mostly waiting for the backup transfer).

> The install/flash scripts check GitHub for the latest OpenAstro release on startup (a quick probe, capped at 15 seconds). When offline they fall back to the newest image already downloaded to `images/`; passing an image path explicitly (`sudo scripts/flash-rootfs path/to/image.img.gz`) skips the check entirely.

### 4. First Boot

The device reboots automatically after flashing. Disconnect USB and wait about 60 seconds.

```
ssh astro@openastro-xxxx.local
```

| Setting | Value |
|---------|-------|
| Hostname | `openastro-xxxx` (xxxx = last 4 hex of the WiFi MAC, lowercase) |
| Login | `astro` / `astro` - **change immediately:** `passwd` |
| SSH | Enabled (root login disabled; unique host keys are generated on first boot) |
| WiFi AP | `OpenAstro-XXXX` (5 GHz, ch 36), password `12345678` - on by default like the other OpenAstro boards |
| AP address | `172.24.1.1` (DHCP for clients) |
| Ethernet | DHCP |
| AlpacaBridge | Preinstalled ASCOM Alpaca server + web portal at `http://openastro-xxxx.local:6800` (from the hotspot: `http://172.24.1.1:6800`) |

`XXXX` is the last 4 hex digits of the unit's WiFi MAC address (e.g.
`OpenAstro-915D`), applied automatically on first boot so multiple units in
the same place each get a unique hotspot name. The hostname gets the same
suffix in lowercase (`openastro-915d`), so two units on one home network never
fight over the same DHCP or mDNS name, and AlpacaBridge stamps the same 4
characters on its device names (`915D: ...` in NINA). One ID everywhere.

Reach it over ethernet (`ssh astro@<ip>`) or by joining the `OpenAstro-XXXX`
WiFi and logging in at `172.24.1.1`. The access point starts automatically at
every boot. Manage WiFi (join your own network, hotspot settings, country)
from the AlpacaBridge portal's WiFi card.

[AlpacaBridge](https://github.com/open-astro/AlpacaBridge) comes preinstalled and updates via `apt` from apt.openastro.net. Its web portal manages devices, WiFi (scan/join networks, hotspot settings, regulatory country), and time sync.

> The hotspot uses 5 GHz channel 36 (matching the other OpenAstro boards), verified working on ASIAIR hardware with the stock bcmdhd driver (2026-08-09 live test, `AP-ENABLED` at 5180 MHz). If your regulatory domain disallows it, switch the profile to 2.4 GHz (`band=bg`, `channel=6`) in `/etc/NetworkManager/system-connections/openastro-ap.nmconnection`, or use the AlpacaBridge web portal's WiFi card.

### Restore Stock Firmware

To go back to the original ZWO firmware at any time:

1. Enter Loader mode (hold reset button while powering on)
2. Run:

```bash
sudo scripts/restore-stock
```

This restores just the rootfs (partition 7) from your backup. The boot chain was never modified, so only the rootfs needs to be restored.

If the device is bricked and won't enter Loader mode, use the full restore (requires Maskrom - eMMC shorting):

```bash
sudo scripts/restore-stock --full
```

## Build Your Own

If you'd prefer to build a custom rootfs instead of using the pre-built image:

### 1. Create a Debian Trixie rootfs

```bash
sudo apt install debootstrap qemu-user-static

sudo debootstrap --arch=arm64 \
  --include=systemd,systemd-sysv,systemd-timesyncd,openssh-server,network-manager,\
dnsmasq-base,wpasupplicant,libpam-systemd,polkitd,wireless-regdb,iw,sudo,\
vim-tiny,less,locales,dbus,iproute2,iputils-ping,wget,curl,\
ca-certificates,usbutils,pciutils,kmod \
  trixie ../asiair-rootfs http://deb.debian.org/debian
```

### 2. Configure the rootfs

```bash
sudo scripts/build/rootfs-setup.sh
```

### 3. Build the image

```bash
sudo scripts/build/rootfs-image.sh
```

### 4. Flash

```bash
sudo scripts/flash-all
```

Or to just update the rootfs without touching the boot chain:

```bash
sudo scripts/flash-rootfs
```

## Scripts Reference

| Script | Description |
|--------|-------------|
| `scripts/install` | **Full installer** - jailbreak, backup, download, flash. Use `--flash-only` to skip jailbreak/backup |
| `scripts/jailbreak` | Enable SSH on a stock ASIAIR (network, no physical access) |
| `scripts/backup` | Backup ASIAIR eMMC over SSH |
| `scripts/flash-all` | Full flash: restore stock boot chain + write OpenAstro Linux rootfs |
| `scripts/flash-rootfs` | Flash rootfs image to p7 only |
| `scripts/restore-stock` | Restore stock rootfs, or `--full` for complete recovery |
| `scripts/reset-device` | Reboot the device via USB |
| `scripts/status` | Check if a device is connected and its mode |
| `scripts/build/rootfs-setup.sh` | Configure a debootstrap rootfs for the ASIAIR |
| `scripts/build/rootfs-image.sh` | Package rootfs directory into flashable ext4 image |

## Hardware Documentation

Detailed hardware reference is in [`hardware/asiair-plus-rk3568-256g/`](hardware/asiair-plus-rk3568-256g/):

- [`inventory.md`](hardware/asiair-plus-rk3568-256g/inventory.md) - Full hardware inventory, GPIO map, peripheral details
- [`plan.md`](hardware/asiair-plus-rk3568-256g/plan.md) - Project status and roadmap
- [`flashtool-recovery.md`](hardware/asiair-plus-rk3568-256g/flashtool-recovery.md) - rk-flashtool commands, Maskrom recovery, partition layout

## rk-flashtool

This repo also contains **rk-flashtool**, a fork of Rockchip's `rkdeveloptool` for reading/writing Rockchip devices over USB (rockusb protocol).

```
sudo ./rk-flashtool -h
```

| Command | Description |
|---------|-------------|
| `db <Loader>` | Download bootloader (Maskrom mode) |
| `rl <Sec> <Len> <File>` | Read flash sectors to file |
| `wl <Sec> <File>` | Write file to flash sectors |
| `ppt` | Print partition table |
| `rd` | Reset device |
| `rci` | Read chip info |
| `rfi` | Read flash info |

## Troubleshooting

### Device not detected on USB

- Check `lsusb | grep 2207` - you should see VID `2207`
- Make sure udev rules are installed (`99-rk-rockusb.rules`)
- Try a different USB cable (some USB-C cables are charge-only)
- The ASIAIR must be in Maskrom or Loader mode, not booted normally

### SSH connection refused after flash

- Wait 30-60 seconds for first boot to complete
- Try `ssh astro@openastro-xxxx.local` or check your router for the device's IP
- If WiFi isn't configured yet, connect via ethernet

### Need to recover from a bad flash

If the device won't boot at all, enter Maskrom mode and run `sudo scripts/restore-stock`. The stock boot chain in your backup will always work.

## License

See [license.txt](license.txt).
