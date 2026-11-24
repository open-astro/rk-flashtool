# ASIAIR Plus: mainline device tree

`rk3568-zwo-asiair-plus.dts` is a mainline Linux device tree for the ASIAIR Plus,
ported from the stock 4.19 BSP tree (`../asiair-plus.dts`) and the pin map in
`../inventory.md`. It compiles cleanly against mainline v7.3.6. It has **not** been
boot-tested yet.

## Build

Drop it into a kernel tree at `arch/arm64/boot/dts/rockchip/`, add
`dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3568-zwo-asiair-plus.dtb` to that directory's
Makefile, and run `make dtbs`.

Kernel config needed beyond arm64 defconfig:

```
CONFIG_PWM_GPIO=y            # DC ports + buzzer (mainline 6.11+)
CONFIG_INPUT_PWM_BEEPER=y    # buzzer as /dev/input beeper
CONFIG_KEYBOARD_GPIO=y       # front button
CONFIG_LEDS_GPIO=y
CONFIG_BRCMFMAC=m            # AP6256 WiFi (needs brcmfmac43456-sdio firmware + nvram)
CONFIG_BT_HCIUART_BCM=y      # AP6256 Bluetooth
CONFIG_MFD_RK8XX_I2C=y
CONFIG_REGULATOR_RK808=y
CONFIG_REGULATOR_FAN53555=y  # tcs4525 vdd_cpu
CONFIG_DWMAC_ROCKCHIP=y
```

## Hardware → userspace

| Hardware | Pin | Interface |
|---|---|---|
| DC port 1-4 | GPIO4_C6 / C5 / C2 / C3 | `/sys/class/pwm/pwmchipN` (one chip per port, channel 0). 100 % duty = on |
| Buzzer | GPIO0_B7 | `pwm-beeper` input device (`SND_TONE`), or its pwm-gpio chip directly |
| Power / activity / network / status LED | GPIO0_D4 / D3 / D5 / D6 | `/sys/class/leds/airplus:*` |
| Button | GPIO0_A5 | `gpio-keys`, emits `BTN_0` |
| USB port power | GPIO0_C2 / A6 / B0 / C7 | on at boot (pull-up); `gpioset gpiochip0 <line>=0` cuts a port |

The pwm-gpio chip numbers depend on probe order. Find each one by its device
tree node through `/sys/class/pwm/pwmchip*/device/of_node` (pwm-dc1..4, pwm-buzzer).
Software PWM runs on hrtimers, which is fine for dew heaters (10 Hz to 1 kHz) and the piezo.

## VERIFY on hardware

- **Power MCU.** A previous mainline boot attempt (2026-04-25) ended with 5 SYS LED
  blinks and then the MCU cut power. This tree keeps the power LED (GPIO0_D4) on from boot the way stock
  does, but what the MCU actually expects from the SoC is still unknown. Boot with a UART on
  uart2 (1.5 Mbaud) attached.
- Polarity of the network and status LEDs (GPIO0_D5/D6).
- Whether the button is active low.
- Ethernet PHY delays: the stock `tx_delay`/`rx_delay` values with `phy-mode = "rgmii"` were carried over.
- The `zwo` vendor prefix isn't in mainline `vendor-prefixes.yaml`, which only matters for upstreaming.
