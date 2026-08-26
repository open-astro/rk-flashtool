# OpenAstro Linux Changelog

<img src="https://www.openastro.net/wp-content/uploads/2026/04/OpenAstro_logo.png" alt="AlpacaBridge logo" width="420">

All notable changes to OpenAstro Linux (rk-flashtool) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Standard OpenAstro system layer** (`scripts/build/rootfs-setup.sh`), aligning the ASIAIR image with the other OpenAstro boards:
  - Unique SSH host keys per unit: the build strips the debootstrap-generated keys (previously shared by every flashed unit) and a first-boot oneshot regenerates them before sshd starts.
  - Per-board hotspot SSID `OpenAstro-XXXX` (last 4 hex of the wlan0 MAC), applied once on first boot by the `openastro-ssid` oneshot; a flash-time custom SSID suppresses the suffix.
  - Per-board hostname `openastro-xxxx` (same 4 hex, lowercase), set by the same oneshot when the hostname is still the image default, so two units on one LAN never collide on DHCP/mDNS and the ID matches the SSID and AlpacaBridge's device names.
  - CPU governor pinned to `performance` (`openastro-cpufreq.service`): the default governor's first-burst clock ramp showed as ~100 ms FAST timing blips in ConformU (AlpacaBridge issue #220).
  - Persistent journald logs (`/var/log/journal`).
  - ZWO HID udev rule (`70-openastro-zwo-hid.rules`, idVendor 03c3, hidraw + hiddev, mode 0666).
  - User `astro` added to hardware-access groups (dialout, plugdev, audio, video, netdev where present).
  - Fleet WiFi conf (`20-openastro-wifi.conf`): powersave off, no scan MAC randomization. NetworkManager manages all interfaces, ethernet included.
  - AlpacaBridge preinstalled from apt.openastro.net (`INSTALL_ALPACABRIDGE=yes` by default now that 3.4.0 ships the WiFi manager).
- **WiFi manager prerequisites** per AlpacaBridge `docs/rk3568-image-notes.md`:
  - `polkitd` installed (required: NetworkManager authorizes AlpacaBridge's unprivileged D-Bus calls via polkit).
  - `wireless-regdb` and `iw` installed; `systemd-timesyncd` installed and enabled (the board has no usable RTC and clock drift breaks TLS/apt and Alpaca timestamps).
  - Stock nvram `ccode=DE` replaced with `ccode=US` in both firmware locations (DE disallows 5 GHz ch 149-165); the installer's country prompt now also patches nvram `ccode` to match the chosen country.

### Changed
- **Hostname is now `openastro`** (was `astro`); connect with `ssh astro@openastro.local`.
- **SSH root login disabled**; use `astro` + sudo.
- **Hotspot aligned with the OpenAstro fleet defaults**: 5 GHz channel 36, unit pinned at 172.24.1.1/24, autoconnect-priority -10 with unlimited retries (`autoconnect-retries=0` means "retry forever" in NetworkManager), keeping the AP profile as an always-available fallback. The installer prompt now defaults to SSID `OpenAstro-XXXX` and password `12345678` on empty input instead of requiring custom values. 5 GHz AP mode on the stock bcmdhd driver was validated on hardware 2026-08-09 (AP-ENABLED at 5180 MHz).

### Fixed
- **Installer no longer destroys an existing stock backup** (`scripts/install`)
  - Re-running the installer after flashing would re-run the backup against a
    non-stock device and overwrite the original backup (which `restore-stock`
    then preferred, being the most recent file) - destroying the only path back
    to stock. The backup step now detects an existing valid backup and skips it;
    pass `--rebackup` to force a fresh one.
  - Backups now stream to a `.partial` temp file and are moved into place only on
    success, so a failed transfer can no longer truncate an existing backup.
- **Corrected the release image URL** (`scripts/install`, `scripts/flash-rootfs`)
  - Pointed at the actual `rootfs-stock.img.gz` asset (was a 404). Failed/partial
    downloads are now cleaned up instead of being left to poison the next run.
- **Decompress the image onto a filesystem with room** (`scripts/install`, `scripts/flash-rootfs`)
  - The rootfs decompresses to ~4 GB, but `/tmp` is often a small RAM-backed
    tmpfs, causing "No space left on device". The temp now goes to a directory
    with enough free space (TMPDIR, the image dir, or /var/tmp), with an
    up-front space check and a clear error instead of a cryptic gzip failure.

### Added
- **Optional WiFi hotspot setup during install** (`scripts/install`, `scripts/flash-rootfs`)
  - The installer asks whether to set up the built-in WiFi as a hotspot before
    flashing. If you opt in, it prompts for a hotspot SSID/password (and country
    code) and bakes a NetworkManager AP-mode profile into the image.
  - The unit broadcasts its own WiFi network (like the stock ASIAIR) that you
    join from a phone/laptop and reach at `astro@10.42.0.1` - it does not join an
    existing router. Skip it to connect over the wired Ethernet port instead.
  - Shared logic lives in `scripts/lib/wifi.sh`.
- **Installer injects `dnsmasq` into the image** (`scripts/lib/wifi.sh`, `blobs/debs/`)
  - NetworkManager's hotspot mode (`ipv4 method=shared`) needs the dnsmasq binary
    to hand out DHCP leases; without it the AP radio starts but clients never get
    an IP. When configuring the hotspot, the installer now checks the mounted
    rootfs and, if dnsmasq is absent, extracts the vendored `dnsmasq-base`,
    `libnetfilter-conntrack3`, and `libnfnetlink0` arm64 `.debs` (the full
    runtime dependency closure) straight into the image with `dpkg-deb -x`
    (offline, no chroot - the build host is the same arch as the target).
    **No image rebuild is required.**
  - `dnsmasq-base` was also added to the from-scratch build
    (`scripts/build/rootfs-setup.sh`, debootstrap include list) so freshly built
    images already contain it.

## [1.0.0] - 2026-04-26

### Added
- **OpenAstro Linux Installer** (`scripts/install`)
  - One-command installer: jailbreak → backup → download image → flash rootfs.
  - Only replaces partition 7 (rootfs). The stock boot chain is never touched.
  - Auto-detects ASIAIR on the network via SSH (tries `asiair` and `192.168.88.1`).
  - Backs up all partitions over SSH (bootloader, p1-p4, p6, p7) - the only way to restore stock firmware since ZWO does not distribute firmware images.
  - Downloads the OpenAstro Linux image from GitHub Releases automatically.
  - Detects Loader and Maskrom mode, loads DDR/SPL blob if needed.
  - `--flash-only` flag to skip jailbreak and backup for users who already have a backup.
- **Stock Firmware Restore** (`scripts/restore-stock`)
  - Default mode: restores rootfs only (partition 7) from backup. Requires Loader mode (hold reset button while powering on). Safe - the boot chain is never modified.
  - `--full` mode: full restore of bootloader + all partitions from backup. For emergency recovery from a bricked device. Requires Maskrom mode (eMMC CLK shorting).
  - Verifies backup files exist and checks file sizes before flashing.
- **Flash Scripts**
  - `scripts/flash-all` - Full flash with stock boot chain restore + OpenAstro Linux rootfs, with USB retry logic and automatic USB reset between writes.
  - `scripts/flash-rootfs` - Flash rootfs image to partition 7 only, with auto-download from GitHub Releases.
- **Utility Scripts**
  - `scripts/jailbreak` - Enable SSH on a stock ASIAIR via the OTA update mechanism (network, no physical access required).
  - `scripts/backup` - Backup ASIAIR eMMC partitions over SSH.
  - `scripts/reset-device` - Reboot the device via USB.
  - `scripts/status` - Check if a device is connected and its mode.
- **Build Scripts**
  - `scripts/build/rootfs-setup.sh` - Configure a debootstrap Debian Trixie rootfs for the ASIAIR (stock kernel 4.19.219, stock firmware, user setup, SSH, NetworkManager).
  - `scripts/build/rootfs-image.sh` - Package rootfs directory into a flashable ext4 image.
- **Jailbreak Tools** (`jailbreak/`)
  - Bundled jailbreak from [ASIAIRJailbreak](https://github.com/open-astro/ASIAIRJailbreak) for enabling SSH on stock ASIAIR firmware.
- **Loader Blob** (`blobs/`)
  - `rk356x_spl_loader_v1.23.114.bin` DDR/SPL loader bundled in the repo for Maskrom recovery - no external downloads required.
- **ASIAIR Mini (RV1126) Documentation** (`hardware/asiair-mini-rv1126/`)
  - Hardware inventory and backup documentation for the ASIAIR Mini. Not yet supported for flashing.
- **Manual Maskrom Restore Guide** (`hardware/asiair-plus-rk3568-256g/manual-restore.md`)
  - Step-by-step emergency recovery procedure with partition table, sector addresses, and USB troubleshooting tips.

### Changed
- **Project renamed** from `rkdeveloptool` to `rk-flashtool` / OpenAstro Linux.
- **C++ source moved** to `src/` subdirectory - all 15 source files relocated from the repo root.
- **Build system updated** - `Makefile.am`, `configure.ac`, and `CMakeLists.txt` updated for `src/` layout with `subdir-objects` support.
- **Progress display** - Replaced ANSI escape codes (`CURSOR_MOVEUP_LINE`/`CURSOR_DEL_LINE`) with `\r` carriage return and `fflush(stdout)` in `read_lba`, `write_lba`, and `write_sparse_lba` functions. Live percentages now display correctly through `sudo`.
- **Version string** - `rkdeveloptool` → `rk-flashtool` in the `--version` output.
- **README.md** - Complete rewrite as OpenAstro Linux project documentation with one-command install, restore instructions, scripts reference, and troubleshooting guide.
- **Hardware documentation** - Updated `flashtool-recovery.md` and `plan.md` for the current project state.

### Removed
- `scripts/debian/asiair-flash.sh` - Replaced by `scripts/flash-all` and `scripts/install`.
- `scripts/debian/asiair-create-image.sh` - Replaced by `scripts/build/rootfs-image.sh`.
- `scripts/debian/asiair-rootfs-setup.sh` - Replaced by `scripts/build/rootfs-setup.sh`.
- `hardware/asiair-plus-rk3568-256g/backup.sh` - Replaced by `scripts/backup`.
