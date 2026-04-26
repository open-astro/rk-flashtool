# Manual Full Restore from Maskrom

Emergency procedure for restoring a completely erased ASIAIR Plus (RK3568) from Maskrom mode. This is the nuclear option — you should only need this if the device was erased with `ef` or the bootloader is corrupted.

For normal restore (stock rootfs only), use `sudo scripts/restore-stock` in Loader mode.

## Prerequisites

- Device is in **Maskrom mode** (VID `2207`, PID `350a` — verify with `lsusb | grep 2207`)
- A complete backup in `asiair-backup/` from `scripts/backup`
- rk-flashtool built (`./autogen.sh && ./configure && make`)

## Entering Maskrom

1. Power off the ASIAIR completely
2. Open the enclosure
3. Short the eMMC CLK pin to ground (see photos in `flashtool-recovery.md`)
4. Apply power while holding the short
5. Hold for 2-3 seconds after power connects, then release

Verify: `lsusb | grep 2207` should show `350a` (Maskrom). If you see `350b`, that's Loader mode — the short didn't take.

## USB Tips

Maskrom USB transfers are fragile. If `db` times out:

- Use a **short, high-quality USB-C cable** (under 1 meter, USB 3.0 rated)
- Plug into a **rear motherboard USB port** directly (no hubs, no front panel)
- Power cycle and re-enter Maskrom between attempts
- You may need to try multiple ports — it can take several attempts

## Partition Layout

| Step | Partition | Sector | Hex | Size | Backup File |
|------|-----------|--------|-----|------|-------------|
| 3 | Bootloader (pre-partition) | 0 | 0x0 | 8 MB | `*_bootloader_pre_partition.bin` |
| 4 | p1 — U-Boot | 16384 | 0x4000 | 4 MB | `*_p1_uboot.bin` |
| 5 | p2 — misc | 24576 | 0x6000 | 4 MB | `*_p2_misc.bin` |
| 6 | p3 — boot | 32768 | 0x8000 | 64 MB | `*_p3_boot.bin` |
| 7 | p4 — recovery | 163840 | 0x28000 | 32 MB | `*_p4_recovery.bin` |
| 8 | p6 — /home/pi | 465797120 | 0x1BC38000 | 512 MB | `*_p6_pi.bin` |
| 9 | p7 — rootfs | 466845696 | 0x1BD38000 | 7 GB | `*_p7_rootfs.bin` |

p5 (222 GB user data) and p8 (3.4 GB) are not restored — too large for USB and the stock firmware recreates them on first boot.

## Commands

Run these one at a time from the repo root. Wait for each to complete before running the next.

```bash
# 1. Verify Maskrom
sudo ./rk-flashtool ld

# 2. Load DDR/SPL
sudo ./rk-flashtool db blobs/rk356x_spl_loader_v1.23.114.bin
sleep 3

# 3. Bootloader
sudo ./rk-flashtool wl 0 asiair-backup/20260423_bootloader_pre_partition.bin
sleep 3

# 4. U-Boot (p1)
sudo ./rk-flashtool wl 0x4000 asiair-backup/20260423_p1_uboot.bin
sleep 3

# 5. misc (p2)
sudo ./rk-flashtool wl 0x6000 asiair-backup/20260423_p2_misc.bin
sleep 3

# 6. boot (p3)
sudo ./rk-flashtool wl 0x8000 asiair-backup/20260423_p3_boot.bin
sleep 3

# 7. recovery (p4)
sudo ./rk-flashtool wl 0x28000 asiair-backup/20260423_p4_recovery.bin
sleep 3

# 8. /home/pi (p6)
sudo ./rk-flashtool wl 0x1BC38000 asiair-backup/20260423_p6_pi.bin
sleep 3

# 9. rootfs (p7) — takes several minutes
sudo ./rk-flashtool wl 0x1BD38000 asiair-backup/20260423_p7_rootfs.bin

# 10. Reboot
sudo ./rk-flashtool rd
```

After reboot the device should boot stock ZWO firmware. SSH requires jailbreak (`scripts/jailbreak`).
