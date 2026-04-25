#!/bin/bash
set -e

# Base directory — set to the parent of the rkdeveloptool repo
BASEDIR="${BASEDIR:-$(cd "$(dirname "$0")/../.." && cd .. && pwd)}"
ROOTFS="$BASEDIR/asiair-rootfs"
HWDIR="$BASEDIR/rkdeveloptool/hardware/asiair-plus-rk3568-256g"
LINUX="$BASEDIR/linux"

echo "Base directory: $BASEDIR"

echo "=== Setting up ASIAIR Debian rootfs ==="

# --- Bind mounts for chroot ---
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"

# --- Hostname ---
echo "astro" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'EOF'
127.0.0.1	localhost
127.0.1.1	astro

::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

# --- fstab ---
cat > "$ROOTFS/etc/fstab" << 'EOF'
# <file system>    <mount point>  <type>  <options>                  <dump> <pass>
/dev/mmcblk0p7     /              ext4    errors=remount-ro          0      1
/dev/mmcblk0p3     /boot          ext4    defaults                   0      2
/dev/mmcblk0p8     none           swap    sw                         0      0
EOF

# --- Locale ---
chroot "$ROOTFS" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen"

# --- Root password + user ---
chroot "$ROOTFS" /bin/bash -c "echo 'root:astro' | chpasswd"
chroot "$ROOTFS" /bin/bash -c "useradd -m -s /bin/bash -G sudo astro && echo 'astro:astro' | chpasswd"

# --- SSH: enable and allow password auth ---
chroot "$ROOTFS" /bin/bash -c "systemctl enable ssh"
mkdir -p "$ROOTFS/etc/ssh/sshd_config.d"
cat > "$ROOTFS/etc/ssh/sshd_config.d/allow-password.conf" << 'EOF'
PasswordAuthentication yes
PermitRootLogin yes
EOF

# --- NetworkManager: enable ---
chroot "$ROOTFS" /bin/bash -c "systemctl enable NetworkManager"

# --- Serial console on UART2 (in case UART is ever found) ---
chroot "$ROOTFS" /bin/bash -c "systemctl enable serial-getty@ttyS2.service" 2>/dev/null || true

# --- WiFi firmware blobs ---
FWDIR="$ROOTFS/lib/firmware/brcm"
mkdir -p "$FWDIR"
cp "$HWDIR/fw_bcm43456c5_ag.bin"       "$FWDIR/brcmfmac43456-sdio.bin"
cp "$HWDIR/nvram_ap6256.txt"            "$FWDIR/brcmfmac43456-sdio.txt"
cp "$HWDIR/fw_bcm43456c5_ag_apsta.bin"  "$FWDIR/brcmfmac43456-sdio.ap6256.bin" 2>/dev/null || true
cp "$HWDIR/BCM4345C5.hcd"               "$FWDIR/BCM4345C5.hcd"
# Symlink with board-compatible name
ln -sf brcmfmac43456-sdio.bin "$FWDIR/brcmfmac43456-sdio.zwo,asiair-plus.bin"
ln -sf brcmfmac43456-sdio.txt "$FWDIR/brcmfmac43456-sdio.zwo,asiair-plus.txt"

# --- Install kernel modules ---
echo "=== Installing kernel modules ==="
cd "$LINUX"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$ROOTFS" modules_install

# --- Install kernel Image and DTB ---
BOOTDIR="$ROOTFS/boot"
mkdir -p "$BOOTDIR/extlinux" "$BOOTDIR/dtbs/rockchip"
cp "$LINUX/arch/arm64/boot/Image" "$BOOTDIR/"
cp "$LINUX/arch/arm64/boot/dts/rockchip/rk3568-asiair-plus.dtb" "$BOOTDIR/dtbs/rockchip/"

# --- extlinux.conf for U-Boot ---
cat > "$BOOTDIR/extlinux/extlinux.conf" << 'EOF'
label Debian Trixie
  kernel /boot/Image
  fdt /boot/dtbs/rockchip/rk3568-asiair-plus.dtb
  append root=/dev/mmcblk0p7 rootfstype=ext4 rootwait console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfe660000
EOF

# --- DNS resolver ---
cat > "$ROOTFS/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# --- Install gpiod tools (for DC power port control) ---
chroot "$ROOTFS" /bin/bash -c "apt-get update && apt-get install -y gpiod 2>/dev/null || apt-get install -y libgpiod-tools 2>/dev/null || echo 'gpiod package not found — install manually later'"

# --- Cleanup ---
umount "$ROOTFS/sys"
umount "$ROOTFS/proc"
umount "$ROOTFS/dev/pts"
umount "$ROOTFS/dev"
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"

echo ""
echo "=== ASIAIR Debian rootfs setup complete ==="
echo "  Hostname: astro"
echo "  User: astro / astro"
echo "  Root: root / astro"
echo "  SSH: enabled"
echo "  Kernel: $(ls $BOOTDIR/Image)"
echo "  DTB: $(ls $BOOTDIR/dtbs/rockchip/rk3568-asiair-plus.dtb)"
echo "  WiFi firmware: installed to /lib/firmware/brcm/"
echo ""
echo "Next: write rootfs to ASIAIR eMMC partition 7 (rootfs)"
