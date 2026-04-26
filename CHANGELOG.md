# OpenAstro Linux Changelog

<img src="https://www.openastro.net/wp-content/uploads/2026/04/OpenAstro_logo.png" alt="AlpacaBridge logo" width="420">

All notable changes to OpenAstro Linux (rk-flashtool) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-26

### Added
- **OpenAstro Linux Installer** (`scripts/install`)
  - One-command installer: jailbreak → backup → download image → flash rootfs.
  - Only replaces partition 7 (rootfs). The stock boot chain is never touched.
  - Auto-detects ASIAIR on the network via SSH (tries `asiair` and `192.168.88.1`).
  - Backs up all partitions over SSH (bootloader, p1–p4, p6, p7) — the only way to restore stock firmware since ZWO does not distribute firmware images.
  - Downloads the OpenAstro Linux image from GitHub Releases automatically.
  - Detects Loader and Maskrom mode, loads DDR/SPL blob if needed.
  - `--flash-only` flag to skip jailbreak and backup for users who already have a backup.
- **Stock Firmware Restore** (`scripts/restore-stock`)
  - Default mode: restores rootfs only (partition 7) from backup. Requires Loader mode (hold reset button while powering on). Safe — the boot chain is never modified.
  - `--full` mode: full restore of bootloader + all partitions from backup. For emergency recovery from a bricked device. Requires Maskrom mode (eMMC CLK shorting).
  - Verifies backup files exist and checks file sizes before flashing.
- **Flash Scripts**
  - `scripts/flash-all` — Full flash with stock boot chain restore + OpenAstro Linux rootfs, with USB retry logic and automatic USB reset between writes.
  - `scripts/flash-rootfs` — Flash rootfs image to partition 7 only, with auto-download from GitHub Releases.
- **Utility Scripts**
  - `scripts/jailbreak` — Enable SSH on a stock ASIAIR via the OTA update mechanism (network, no physical access required).
  - `scripts/backup` — Backup ASIAIR eMMC partitions over SSH.
  - `scripts/reset-device` — Reboot the device via USB.
  - `scripts/status` — Check if a device is connected and its mode.
- **Build Scripts**
  - `scripts/build/rootfs-setup.sh` — Configure a debootstrap Debian Trixie rootfs for the ASIAIR (stock kernel 4.19.219, stock firmware, user setup, SSH, NetworkManager).
  - `scripts/build/rootfs-image.sh` — Package rootfs directory into a flashable ext4 image.
- **Jailbreak Tools** (`jailbreak/`)
  - Bundled jailbreak from [ASIAIRJailbreak](https://github.com/open-astro/ASIAIRJailbreak) for enabling SSH on stock ASIAIR firmware.
- **Loader Blob** (`blobs/`)
  - `rk356x_spl_loader_v1.23.114.bin` DDR/SPL loader bundled in the repo for Maskrom recovery — no external downloads required.
- **ASIAIR Mini (RV1126) Documentation** (`hardware/asiair-mini-rv1126/`)
  - Hardware inventory and backup documentation for the ASIAIR Mini. Not yet supported for flashing.
- **Manual Maskrom Restore Guide** (`hardware/asiair-plus-rk3568-256g/manual-restore.md`)
  - Step-by-step emergency recovery procedure with partition table, sector addresses, and USB troubleshooting tips.

### Changed
- **Project renamed** from `rkdeveloptool` to `rk-flashtool` / OpenAstro Linux.
- **C++ source moved** to `src/` subdirectory — all 15 source files relocated from the repo root.
- **Build system updated** — `Makefile.am`, `configure.ac`, and `CMakeLists.txt` updated for `src/` layout with `subdir-objects` support.
- **Progress display** — Replaced ANSI escape codes (`CURSOR_MOVEUP_LINE`/`CURSOR_DEL_LINE`) with `\r` carriage return and `fflush(stdout)` in `read_lba`, `write_lba`, and `write_sparse_lba` functions. Live percentages now display correctly through `sudo`.
- **Version string** — `rkdeveloptool` → `rk-flashtool` in the `--version` output.
- **README.md** — Complete rewrite as OpenAstro Linux project documentation with one-command install, restore instructions, scripts reference, and troubleshooting guide.
- **Hardware documentation** — Updated `flashtool-recovery.md` and `plan.md` for the current project state.

### Removed
- `scripts/debian/asiair-flash.sh` — Replaced by `scripts/flash-all` and `scripts/install`.
- `scripts/debian/asiair-create-image.sh` — Replaced by `scripts/build/rootfs-image.sh`.
- `scripts/debian/asiair-rootfs-setup.sh` — Replaced by `scripts/build/rootfs-setup.sh`.
- `hardware/asiair-plus-rk3568-256g/backup.sh` — Replaced by `scripts/backup`.
