# Recovered: Armbian 6.18.43 mainline bring-up (Aug 2026)

The Aug 2026 mainline work (DTS source, pwm-gpio-compat source, build scripts) was
never committed and its working tree is gone. These files were pulled back off the
ASIAIR on 2026-11-24 over the debug initramfs's USB ACM shell, with md5 verified.

| File | What |
|---|---|
| `rk3568-asiair-plus.dtb` | DTB from p3 (raw, in the boot.img "second" slot). **Proven on hardware**: stock U-Boot loads it and the board stays powered. |
| `rk3568-asiair-plus.decompiled.dts` | `dtc -I dtb -O dts` of the above. Phandles are numeric; the original source is lost. |
| `pwm_gpio_compat.ko` | Clean-room `/dev/pwm-gpio-misc` ABI module (GPL, OpenAstro), vermagic `6.18.43-current-rockchip64`, built with debug info. Source lost, so rebuild from `../../pwm_gpio.h`. |
| `initramfs-debug-init.sh` | `/init` of the debug initramfs that was in p3: a USB ACM root shell plus an eMMC blink code. It never mounts the rootfs. |

Large binaries are kept beside the stock backup in `asiair-backup/mainline-6.18.43-recovered/`
(kernel Image, the full debug p3, and `boot-6.18.43-noinitramfs.img`, which is the same kernel and DTB
without the ramdisk).

Notes:
- The blink code's "3" is a false failure. This DT has no `mmc0` alias, so the eMMC
  is `mmcblk1` and the script only looks for `/dev/mmcblk0`.
- p7 already has the matching mainline rootfs: Debian 13, `/lib/modules/6.18.43-current-rockchip64`
  including `extra/pwm_gpio_compat.ko`, brcmfmac firmware `brcmfmac43456-sdio.zwo,asiair-plus.*`,
  and `BCM4345C5.hcd`.
- Pack with `scripts/build/mkbootimg-asiair.py --raw-dtb` (selftest reproduces this p3 byte-for-byte).
