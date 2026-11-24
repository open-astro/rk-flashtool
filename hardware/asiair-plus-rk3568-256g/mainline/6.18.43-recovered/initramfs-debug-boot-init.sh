#!/bin/busybox sh
# Debug initramfs that BOOTS Debian on p7 and keeps a USB serial root shell.
#
# 1. USB ACM gadget ("ASIAIR-debug", 1d6b:0104) -> /dev/ttyACM0 on the host.
# 2. Mount p7, install a root shell service on ttyGS0 and enable a persistent journal.
# 3. switch_root into Debian's systemd. The gadget stays bound across switch_root.
#
# The ttyGS0 root shell is a debug back door: remove
# /etc/systemd/system/openastro-usb-debug-shell.service once networking works.
# If p7 can't be mounted, it falls back to a shell in the initramfs.

/bin/busybox --install -s /bin
mkdir -p /proc /sys /dev /tmp /newroot
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null || mdev -s
mount -t configfs configfs /sys/kernel/config 2>/dev/null
LOG=/tmp/initramfs.log
log() { echo "[initramfs] $*" | tee -a $LOG > /dev/kmsg; }

# --- USB ACM gadget ---
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
  [ -n "$udc" ] && echo "$udc" > $G/UDC 2>/dev/null && log "gadget bound to $udc"
fi

# --- find and mount the rootfs (p7, by PARTUUID) ---
ROOT=""
i=0
while [ $i -lt 40 ] && [ -z "$ROOT" ]; do
  for d in /dev/mmcblk0p7 /dev/mmcblk1p7 /dev/mmcblk2p7; do
    [ -b $d ] && ROOT=$d && break
  done
  [ -z "$ROOT" ] && sleep 0.5
  i=$((i+1))
done
log "rootfs device: ${ROOT:-NOT FOUND}"

if [ -n "$ROOT" ] && mount -t ext4 -o rw $ROOT /newroot && { [ -x /newroot/sbin/init ] || [ -L /newroot/sbin/init ]; }; then
  U=/newroot/etc/systemd/system/openastro-usb-debug-shell.service
  cat > $U <<'EOF'
[Unit]
Description=OpenAstro DEBUG root shell on USB gadget serial (ttyGS0) - remove after bring-up
After=systemd-udevd.service
ConditionPathExists=/dev/ttyGS0

[Service]
ExecStart=/bin/bash -l
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyGS0
TTYReset=yes
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /newroot/etc/systemd/system/multi-user.target.wants
  ln -sf ../openastro-usb-debug-shell.service /newroot/etc/systemd/system/multi-user.target.wants/openastro-usb-debug-shell.service
  # keep the journal across reboots so a failed boot can be read on the next one
  mkdir -p /newroot/var/log/journal
  cp $LOG /newroot/var/log/openastro-initramfs.log 2>/dev/null
  sync
  log "debug shell installed; switching to Debian"
  mount --move /dev /newroot/dev
  mount --move /proc /newroot/proc
  mount --move /sys /newroot/sys
  exec switch_root /newroot /sbin/init
fi

# --- fallback: stay in the initramfs with a shell on the gadget ---
log "could not boot rootfs; staying in initramfs"
while :; do
  if [ -e /dev/ttyGS0 ]; then setsid sh -c 'exec sh </dev/ttyGS0 >/dev/ttyGS0 2>&1'; fi
  sleep 2
done
