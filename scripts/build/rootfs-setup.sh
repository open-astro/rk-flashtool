#!/bin/bash
set -e

# Set up a Debian Trixie rootfs for the ASIAIR Plus (stock kernel approach).
#
# Prerequisites:
#   - Trixie rootfs created via debootstrap at $ROOTFS
#   - Stock rootfs backup mounted (to extract modules + firmware)
#
# Usage: sudo scripts/build/rootfs-setup.sh

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASEDIR="$(dirname "$REPODIR")"
ROOTFS="$BASEDIR/asiair-rootfs"
HWDIR="$REPODIR/hardware/asiair-plus-rk3568-256g"
BACKUP="$HWDIR/asiair-backup"
STOCK_ROOTFS_IMG="$BACKUP/20260423_p7_rootfs.bin"

echo "Base directory: $BASEDIR"
echo "Rootfs:         $ROOTFS"

if [ ! -d "$ROOTFS/etc" ]; then
    echo "ERROR: Rootfs not found at $ROOTFS"
    echo "Run debootstrap first."
    exit 1
fi

echo "=== Setting up ASIAIR Debian rootfs (stock kernel) ==="

# --- Mount stock rootfs to extract modules + firmware ---
STOCKMNT="/tmp/asiair-stock-rootfs"
mkdir -p "$STOCKMNT"
if [ -f "$STOCK_ROOTFS_IMG" ]; then
    echo "Mounting stock rootfs backup..."
    mount -o loop,ro "$STOCK_ROOTFS_IMG" "$STOCKMNT"
    UNMOUNT_STOCK=1
elif [ -d "$STOCKMNT/lib/modules/4.19.219" ]; then
    echo "Stock rootfs already mounted."
    UNMOUNT_STOCK=0
else
    echo "ERROR: Stock rootfs image not found: $STOCK_ROOTFS_IMG"
    exit 1
fi

# --- Bind mounts for chroot ---
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/" 2>/dev/null || true

# --- Hostname ---
echo "astro" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'EOF'
127.0.0.1	localhost
127.0.1.1	astro

::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

# --- fstab (stock partition layout) ---
cat > "$ROOTFS/etc/fstab" << 'EOF'
# <file system>    <mount point>  <type>  <options>                        <dump> <pass>
/dev/mmcblk0p7     /              ext4    defaults,noatime                 0      1
/dev/mmcblk0p8     none           swap    sw                               0      0
/dev/mmcblk0p5     /mnt/data      vfat    uid=1000,gid=1000,nofail,noauto  0      0
EOF
mkdir -p "$ROOTFS/mnt/data"

# --- Locale ---
chroot "$ROOTFS" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen"

# --- Root password + user ---
chroot "$ROOTFS" /bin/bash -c "echo 'root:astro' | chpasswd"
chroot "$ROOTFS" /bin/bash -c "id astro >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo astro"
chroot "$ROOTFS" /bin/bash -c "echo 'astro:astro' | chpasswd"

# --- SSH ---
chroot "$ROOTFS" /bin/bash -c "systemctl enable ssh"
mkdir -p "$ROOTFS/etc/ssh/sshd_config.d"
cat > "$ROOTFS/etc/ssh/sshd_config.d/allow-password.conf" << 'EOF'
PasswordAuthentication yes
PermitRootLogin yes
EOF

# --- NetworkManager ---
chroot "$ROOTFS" /bin/bash -c "systemctl enable NetworkManager"

# --- Install stock kernel modules (4.19.219) ---
echo "Installing stock kernel modules..."
rm -rf "$ROOTFS/lib/modules/"*
cp -a "$STOCKMNT/lib/modules/4.19.219" "$ROOTFS/lib/modules/"
rm -f "$ROOTFS/lib/modules/4.19.219/build"

# --- Install stock firmware ---
echo "Installing stock firmware..."
rm -rf "$ROOTFS/lib/firmware/"*
cp -a "$STOCKMNT/lib/firmware/"* "$ROOTFS/lib/firmware/"

# The stock kernel has hardcoded firmware paths (CONFIG_BCMDHD_FW_PATH and
# CONFIG_BCMDHD_NVRAM_PATH both point to /vendor/etc/firmware/).
echo "Installing WiFi/BT firmware to /vendor/etc/firmware/..."
mkdir -p "$ROOTFS/vendor/etc/firmware"
FW_SRC="$ROOTFS/lib/firmware"
FW_DST="$ROOTFS/vendor/etc/firmware"
cp "$FW_SRC/fw_bcm43456c5_ag.bin"       "$FW_DST/fw_bcmdhd.bin"
cp "$FW_SRC/fw_bcm43456c5_ag.bin"       "$FW_DST/fw_bcm43456c5_ag.bin"
cp "$FW_SRC/fw_bcm43456c5_ag_apsta.bin" "$FW_DST/fw_bcmdhd_apsta.bin"
cp "$FW_SRC/fw_bcm43456c5_ag_apsta.bin" "$FW_DST/fw_bcm43456c5_ag_apsta.bin"
cp "$FW_SRC/fw_bcm43456c5_ag_p2p.bin"   "$FW_DST/fw_bcmdhd_p2p.bin"
cp "$FW_SRC/nvram_ap6256.txt"            "$FW_DST/nvram.txt"
cp "$FW_SRC/nvram_ap6256.txt"            "$FW_DST/nvram_ap6256.txt"
cp "$FW_SRC/BCM4345C5.hcd"              "$FW_DST/BCM4345C5.hcd"

# --- Auto-load pwm_gpio module ---
mkdir -p "$ROOTFS/etc/modules-load.d"
echo "pwm_gpio" > "$ROOTFS/etc/modules-load.d/pwm-gpio.conf"

# --- DNS resolver ---
cat > "$ROOTFS/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# --- Cleanup ---
umount "$ROOTFS/sys"
umount "$ROOTFS/proc"
umount "$ROOTFS/dev/pts"
umount "$ROOTFS/dev"
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
[ "$UNMOUNT_STOCK" = "1" ] && umount "$STOCKMNT" && rmdir "$STOCKMNT"

echo ""
echo "=== ASIAIR Debian rootfs setup complete ==="
echo "  Hostname: astro"
echo "  User: astro / astro"
echo "  Root: root / astro"
echo "  SSH: enabled"
echo "  Kernel modules: stock 4.19.219"
echo "  Firmware: stock (BCM43456 WiFi/BT)"
echo ""
echo "Next: build rootfs image with asiair-stock-flash.sh or manually"
