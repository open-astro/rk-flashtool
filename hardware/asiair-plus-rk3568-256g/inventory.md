# ASIAIR Plus Hardware Inventory

Cataloged: 2026-04-23
Device: ZWO ASIAIR Plus (AirPlus-RK3568)
Serial: 80dc05dee22adbeb

## SoC

- **RockChip RK3568**
- Device tree compatible: `rockchip,rk3568-airplus-evb0`, `rockchip,rk3568`
- CPU: 4x ARM Cortex-A55 (ARMv8, CPU part 0xd05)
- BogoMIPS: 48.00

## Stock Firmware

- Kernel: Linux 4.19.219 (Rockchip BSP)
- Compiler: aarch64-linux-gnu-gcc (Linaro GCC 6.3-2017.05) 6.3.1
- Kernel built: 2024-05-08
- `/proc/config.gz`: available (full kernel config extractable)
- `dtc`: available at `/usr/bin/dtc`
- rootfs mounted **read-only**

## eMMC Storage

- Total: 233 GiB (250,181,844,992 bytes / 488,636,416 sectors)
- Disklabel: GPT
- Disk identifier: 73987B6B-4974-4C94-A3E8-58AB2EB7A946

### Partition Layout

| Part | Name       | Start Sector | End Sector  | Size   | Format      | Mount Point   | Content                                 |
|------|------------|-------------|-------------|--------|-------------|---------------|-----------------------------------------|
| p1   | uboot      | 16384       | 24575       | 4 MB   | raw (FDT)   | —             | U-Boot (magic: `d0 0d fe ed`)           |
| p2   | misc       | 24576       | 32767       | 4 MB   | raw         | —             | A/B slot metadata (header: `AB0`)       |
| p3   | boot       | 32768       | 163839      | 64 MB  | raw         | —             | Kernel boot image (magic: `ANDROID!`)   |
| p4   | recovery   | 163840      | 229375      | 32 MB  | raw (FDT)   | —             | Recovery image (magic: `d0 0d fe ed`)   |
| p5   | asiair     | 229376      | 465797119   | 222 GB | VFAT        | /boot/Image   | Image storage (221 GB used)             |
| p6   | pi         | 465797120   | 466845695   | 512 MB | ext4        | /home/pi      | User home (66 MB used)                  |
| p7   | rootfs     | 466845696   | 481525759   | 7 GB   | ext4        | / (ro)        | Rootfs (5.6 GB used of 6.9 GB, 86%)    |
| p8   | swap       | 481525760   | 488636352   | 3.4 GB | linux-swap  | —             | Swap partition                          |

Note: Sectors 0–16383 (first 8 MB) contain GPT header + U-Boot/TPL/SPL (before p1).

### Disk Space

```
/dev/root       6.9G  5.6G  966M  86% /
/dev/mmcblk0p6  488M   66M  387M  15% /home/pi
/dev/mmcblk0p5  222G  221G  976M 100% /boot/Image
```

## WiFi

- **Chip: Broadcom AP6256 (BCM43456)**
- Interface: SDIO
- SDIO ID: `02D0:A9BF`
- Driver: `bcmsdh_sdmmc` / `bcmdhd_wifi6` (Rockchip fork)
- Driver version: 101.10.361.29 (wlan=r892223-20221214-2)
- Compiled: 2024-03-10
- Source path (in kernel tree): `drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd_wifi6`
- Interfaces:
  - `wlan0` — station mode (MAC: c0:f5:35:8a:78:ec)
  - `uap0` — AP mode (MAC: c2:f5:35:8a:78:ec)
- WiFi power controlled by GPIO
- Host wake IRQ: 74
- Device tree node: `wireless-wlan`

## Bluetooth

- Device tree node: `wireless-bluetooth`
- Likely integrated with AP6256 (combo chip: WiFi + BT)

## Ethernet

- `eth0`: UP, MAC 8e:08:67:48:d7:0a
- Device tree nodes: `ethernet@fe010000`, `ethernet@fe2a0000` (2 MACs available)

## USB

8 host controllers enumerated:

| Bus | USB Version | Type      |
|-----|-------------|-----------|
| 1   | USB 2.0     | EHCI/OHCI |
| 2   | USB 2.0     | EHCI/OHCI |
| 3   | USB 1.1     | OHCI      |
| 4   | USB 1.1     | OHCI      |
| 5   | USB 2.0     | xHCI      |
| 6   | USB 3.0     | xHCI      |
| 7   | USB 2.0     | xHCI      |
| 8   | USB 3.0     | xHCI      |

Device tree USB nodes:
- `usb@fd800000`, `usb@fd840000`, `usb@fd880000`, `usb@fd8c0000`
- `usb2-phy@fe8a0000`, `usb2-phy@fe8b0000`
- `usbdrd`, `usbhost`

USB power regulators (from device tree):
- `vcc-usb2-power1-regulator`
- `vcc-usb2-power2-regulator`
- `vcc-usb3-power1-regulator`
- `vcc-usb3-power2-regulator`
- `vcc5v0-usb`

## Power

- `dc-12v` — main DC input
- `vcc3v3-sys` — 3.3V system rail
- `vcc5v0-sys` — 5V system rail
- `vcc5v0-usb` — 5V USB rail
- `test-power` — unknown (test/debug?)
- 26 regulators enumerated (regulator.0 through regulator.25)

## GPIO — Full Map (VERIFIED FROM LIVE STATE)

GPIO banks resolved from phandles:
- Phandle 0x37 = `gpio@fdd60000` = **GPIO0** (gpiochip0, GPIOs 0–31)
- Phandle 0x115 = `gpio@fe750000` = **GPIO2** (gpiochip2, GPIOs 64–95)
- Phandle 0x11b = `gpio@fe770000` = **GPIO4** (gpiochip4, GPIOs 128–159)

The `airplus-gpios` node (compatible: `pwm-gpio`, kernel module: `pwm_gpio`) controls
**12 GPIOs** via a misc device at `/sys/class/misc/pwm-gpio-misc`.
The ASIAIR user-space apps (`zwoair_imager`, `zwoair_guider`) control ports through this device.

### Group 1: Status LEDs & Control (GPIO0, indices 0–3)

| Index | GPIO# | RK3568     | Dir | Value | Verified Function                              |
|-------|-------|------------|-----|-------|-------------------------------------------------|
| 0     | 29    | GPIO0_D5   | out | hi    | **Network/status LED** (pinctrl: `led-network`) |
| 1     | 30    | GPIO0_D6   | out | lo    | **Status LED** (4th LED in D3-D6 cluster)       |
| 2     | 5     | GPIO0_A5   | in  | hi    | **Physical button input** (pinctrl: `airplus-keys`) |
| 3     | 15    | GPIO0_B7   | out | lo    | **DC master enable or control signal**           |

### Group 2: DC Power Port PWM/Variable Control (GPIO4, indices 4–7)

All confirmed as outputs — these drive the 12V DC power ports:

| Index | GPIO# | RK3568     | Dir | Value | Verified Function                     |
|-------|-------|------------|-----|-------|----------------------------------------|
| 4     | 150   | GPIO4_C6   | out | hi    | DC port 1 PWM (**currently ON**)       |
| 5     | 149   | GPIO4_C5   | out | lo    | DC port 2 PWM (currently off)          |
| 6     | 146   | GPIO4_C2   | out | lo    | DC port 3 PWM (currently off)          |
| 7     | 147   | GPIO4_C3   | out | lo    | DC port 4 PWM (currently off)          |

### Group 3: USB Port Power Enables (GPIO0, indices 8–11)

All currently set as **inputs (hi-Z)** — USB power is always on via pull-ups.
The pwm-gpio driver switches to `out lo` to cut power to individual USB ports.

| Index | GPIO# | RK3568     | Dir | Value | Verified Function                     | Regulator          |
|-------|-------|------------|-----|-------|----------------------------------------|--------------------|
| 8     | 18    | GPIO0_C2   | in  | hi    | USB2 port 1 power (on, floating)       | vcc-usb2-power-en1 |
| 9     | 6     | GPIO0_A6   | in  | hi    | USB2 port 2 power (on, floating)       | vcc-usb2-power-en2 |
| 10    | 8     | GPIO0_B0   | in  | hi    | USB3 port 1 power (on, floating)       | vcc-usb3-power-en1 |
| 11    | 23    | GPIO0_C7   | in  | hi    | USB3 port 2 power (on, floating)       | vcc-usb3-power-en2 |

### LED Cluster (GPIO0 Bank D — 4 consecutive pins)

| GPIO# | RK3568   | Kernel Label     | Dir | Value | Function                 | Controlled By      |
|-------|----------|------------------|-----|-------|--------------------------|---------------------|
| 27    | GPIO0_D3 | airplus_activity | out | hi    | Activity LED (off)       | gpio-leds framework |
| 28    | GPIO0_D4 | airplus_power    | out | lo    | Power LED (**on**)       | gpio-leds framework |
| 29    | GPIO0_D5 | airplus-gpios    | out | hi    | Network LED (**on**)     | pwm-gpio module     |
| 30    | GPIO0_D6 | airplus-gpios    | out | lo    | Status LED (off)         | pwm-gpio module     |

Note: LEDs are **active low** (gpio-leds: flag 0x01) for D3/D4.
D5/D6 controlled by pwm-gpio, polarity TBD (D5 `out hi` appears lit based on
`led-network` pinctrl, but active-high/low needs physical verification).

### DC Power Port LEDs (above ports)

The per-port indicator LEDs are likely **hardwired to the DC power MOSFET gate** —
when GPIO4 drives the port high, both the power output and the indicator LED activate.
No separate GPIO control for port LEDs has been found in the device tree.
This should be verified by toggling a port and observing the LED.

### Other GPIOs (not in airplus-gpios)

| GPIO# | RK3568   | Label                | Dir | Value | Function               |
|-------|----------|----------------------|-----|-------|------------------------|
| 41    | GPIO1_B1 | mdio-reset           | out | hi    | Ethernet PHY reset     |
| 73    | GPIO2_B1 | reset                | out | hi    | WiFi SDIO reset        |
| 77    | GPIO2_B5 | bt_default_rts       | in  | hi    | Bluetooth UART RTS     |
| 79    | GPIO2_B7 | bt_default_poweron   | out | lo    | Bluetooth power (off)  |
| 80    | GPIO2_C0 | bt_default_wake_host | in  | lo    | Bluetooth wake host    |

### GPIO Chip Summary

| Chip      | Base | Range | Address      | Bank  | Active Pins |
|-----------|------|-------|--------------|-------|-------------|
| gpiochip0 | 0    | 0-31  | fdd60000     | GPIO0 | 10          |
| gpiochip1 | 32   | 32-63 | fe740000     | GPIO1 | 1           |
| gpiochip2 | 64   | 64-95 | fe750000     | GPIO2 | 4           |
| gpiochip3 | 96   | 96-127| fe760000     | GPIO3 | 0           |
| gpiochip4 | 128  | 128-159| fe770000    | GPIO4 | 4           |
| gpiochip5 | 511  | 511   | rk817-gpio   | PMIC  | 0           |

## ASIAIR Software Stack

Running processes that interact with hardware:
- `zwoair_imager` — main imaging application
- `zwoair_guider` — autoguiding application
- `zwoair_updater` — firmware updater
- `zwoair_daemon.sh` — watchdog/management daemon
- `hostapd` — WiFi AP mode
- `wpa_supplicant` — WiFi station mode

Hardware control interface: `/sys/class/misc/pwm-gpio-misc` (character device)

## Bluetooth (VERIFIED)

- BT power GPIO: **GPIO2_B7** (gpio79) — currently **off** (`out lo`)
- BT wake host IRQ: **GPIO2_C0** (gpio80) — `in lo`
- UART RTS GPIO: **GPIO2_B5** (gpio77) — `in hi`
- Clock source: external clock
- Compatible: `bluetooth-platdata`

## WiFi (VERIFIED)

- **Chip: Broadcom AP6256 (BCM43456)**
- Host wake IRQ: **GPIO2_B2** (gpio74)
- SDIO reset: **GPIO2_B1** (gpio73) — `out hi` (active)
- Power sequence: `mmc-pwrseq-simple`
- Chip type in DTS: `ap6256`
- Compatible: `wlan-platdata`
- Driver: `bcmdhd_wifi6` (Rockchip fork, v101.10.361.29)

## GPIO Chips

- gpiochip0 (GPIO0), gpiochip1 (GPIO1), gpiochip2 (GPIO2), gpiochip3 (GPIO3), gpiochip4 (GPIO4), gpiochip5 (rk817-gpio/PMIC)

## Other Peripherals (from device tree)

- **Camera**: CSI2 DPHY x3, MIPI CSI-2, RKISP (image signal processor)
- **Display**: HDMI, DSI x2, eDP, VOP (video output processor), EBC (e-ink)
- **PCIe**: 3 controllers (`pcie@fe260000`, `fe270000`, `fe280000`)
- **SATA**: 3 controllers (`sata@fc000000`, `fc400000`, `fc800000`)
- **I2C**: 6 buses (`i2c@fdd40000`, `fe5a0000`–`fe5e0000`)
- **SPI**: 4 buses (`spi@fe610000`–`fe640000`) + SFC (`sfc@fe300000`)
- **UART**: 10+ serial ports (`serial@fdd50000`, `fe650000`–`fe6d0000`)
- **PWM**: 16 channels across multiple controllers
- **CAN**: 3 buses (`can@fe570000`–`fe590000`)
- **ADC**: SARADC (`saradc@fe720000`)
- **TSADC**: Temperature sensor (`tsadc@fe710000`)
- **GPU**: Mali (`gpu@fde60000`)
- **NPU**: Neural processing unit (`npu@fde40000`)
- **Crypto**: Hardware crypto engine (`crypto@fe380000`)
- **RNG**: Hardware random number generator (`rng@fe388000`)
- **Watchdog**: `watchdog@fe600000`
- **NAND**: `nandc@fe330000`
- **eMMC**: `sdhci@fe310000`

## Exported Artifacts (on device at /home/pi/)

- [x] `asiair-plus.dts` — Full decompiled device tree source (146 KB)
- [x] `asiair-plus.dtb` — Compiled device tree blob (119 KB)
- [x] `asiair-kernel.config` — Full kernel config (164 KB)

These need to be copied to this repo:
```bash
scp pi@asiair:~/asiair-plus.dts ./
scp pi@asiair:~/asiair-plus.dtb ./
scp pi@asiair:~/asiair-kernel.config ./
```

## Data Resolved

- [x] GPT partition names — uboot, misc, boot, recovery, asiair, pi, rootfs, swap
- [x] Partition p4 — recovery image (FDT format)
- [x] Partition p8 — swap partition
- [x] `airplus-gpios` node — 12 GPIOs decoded (4x DC enable + 4x DC PWM + 4x USB power)
- [x] Full kernel config — exported to repo
- [x] Device tree source — exported to repo, all phandles resolved
- [x] GPIO phandle 0x37 = GPIO0, 0x115 = GPIO2, 0x11b = GPIO4
- [x] LED GPIOs — GPIO0_D4 (power), GPIO0_D3 (activity)
- [x] BT/WiFi GPIOs — all decoded
- [ ] Pre-partition area (sectors 0–16383): TPL/SPL loader identification

## Kernel Build Requirements

Drivers needed for full hardware support on Debian:

| Subsystem      | Driver / Module                                        | Status in Stock |
|----------------|--------------------------------------------------------|-----------------|
| WiFi           | bcmdhd_wifi6 (Rockchip fork for AP6256/BCM43456)       | Built-in        |
| Bluetooth      | bluetooth-platdata + HCI UART                          | Built-in        |
| USB            | DWC3 (rk3568-dwc3) + xHCI + EHCI + OHCI               | Built-in        |
| eMMC           | RK3568 SDHCI (sdhci@fe310000)                          | Built-in        |
| GPIO           | rockchip,gpio-bank                                     | Built-in        |
| PWM            | rockchip,rk3568-pwm (for DC port variable control)     | Built-in        |
| LEDs           | gpio-leds                                              | Built-in        |
| GPU            | Mali (gpu@fde60000)                                    | Built-in        |
| HDMI           | RK3568 HDMI                                            | Built-in        |
| Ethernet       | RK3568 GMAC x2                                         | Built-in        |
| PCIe           | RK3568 PCIe x3                                         | Built-in        |
| SATA           | RK3568 AHCI x3                                         | Built-in        |
| Camera/ISP     | RKISP + CSI2-DPHY                                      | Built-in        |
| Thermal        | RK3568 TSADC                                           | Built-in        |
| Crypto/RNG     | RK3568 crypto + rng                                    | Built-in        |
| NPU            | RK3568 NPU                                             | Built-in        |
| Power control  | pwm-gpio (custom ZWO driver for airplus-gpios)         | Built-in        |

**Critical note:** The `pwm-gpio` compatible driver for `airplus-gpios` is likely a custom
ZWO/Rockchip driver not present in mainline Linux. This controls the 12V DC power ports
and USB power switching. We will need to either:
1. Extract this driver from the stock kernel source, or
2. Write a simple GPIO userspace control via sysfs/libgpiod
