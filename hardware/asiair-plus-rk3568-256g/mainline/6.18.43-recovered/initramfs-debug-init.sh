#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null || mdev -s
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
mount -t configfs configfs /sys/kernel/config 2>/dev/null
PWR=/sys/class/leds/airplus_power
# --- USB ACM serial gadget console (dwc3 dual-role) ---
insmod /lib/modules/libcomposite.ko 2>/dev/null
insmod /lib/modules/u_serial.ko 2>/dev/null
insmod /lib/modules/usb_f_acm.ko 2>/dev/null
G=/sys/kernel/config/usb_gadget/g1
if mkdir -p $G 2>/dev/null; then
  echo 0x1d6b > $G/idVendor; echo 0x0104 > $G/idProduct
  mkdir -p $G/strings/0x409; echo "OpenAstro" > $G/strings/0x409/manufacturer; echo "ASIAIR-debug" > $G/strings/0x409/product
  mkdir -p $G/configs/c.1/strings/0x409; echo acm > $G/configs/c.1/strings/0x409/configuration
  mkdir -p $G/functions/acm.0; ln -s $G/functions/acm.0 $G/configs/c.1/ 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do udc=$(ls /sys/class/udc 2>/dev/null | head -1); [ -n "$udc" ] && break; sleep 1; done
  [ -n "$udc" ] && echo "$udc" > $G/UDC 2>/dev/null
fi
# --- eMMC diagnostic (blink code) ---
i=0; while [ $i -lt 60 ] && [ ! -b /dev/mmcblk0 ]; do sleep 0.5; i=$((i+1)); done
D=/sys/bus/platform/devices/fe310000.mmc
CODE=1
if [ -e "$D" ]; then CODE=2; grep -q fe310000 /sys/kernel/debug/devices_deferred 2>/dev/null && CODE=5; [ -e "$D/driver" ] && CODE=3; [ -b /dev/mmcblk0 ] && CODE=4; fi
if [ "$CODE" = 4 ]; then
  { echo "OPENASTRO-BOOTLOG-V1 initramfs $(uname -r) CODE=4"; cat /proc/partitions; dmesg; echo "OPENASTRO-BOOTLOG-END"; } > /tmp/log.txt 2>&1
  dd if=/tmp/log.txt of=/dev/mmcblk0p2 bs=1M seek=2 conv=notrunc,fsync 2>/dev/null; sync
fi
# console on the gadget if it bound
if [ -e /dev/ttyGS0 ]; then
  (while :; do echo "=== OPENASTRO DEBUG CODE=$CODE $(uname -r) ==="; dmesg | tail -80; sleep 5; done > /dev/ttyGS0 2>&1) &
  (while :; do setsid sh -c 'exec sh </dev/ttyGS0 >/dev/ttyGS0 2>&1'; sleep 2; done) &
fi
echo none > $PWR/trigger 2>/dev/null
while :; do n=0; while [ $n -lt $CODE ]; do echo 1 > $PWR/brightness; sleep 0.25; echo 0 > $PWR/brightness; sleep 0.25; n=$((n+1)); done; sleep 2; done
