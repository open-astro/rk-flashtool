#!/bin/bash
set -e

# Base directory — set to the parent of the rkdeveloptool repo
BASEDIR="${BASEDIR:-$(cd "$(dirname "$0")/../.." && cd .. && pwd)}"
ROOTFS="$BASEDIR/asiair-rootfs"
LINUX="$BASEDIR/linux"
UBOOT="$BASEDIR/u-boot"
OUTDIR="$BASEDIR/asiair-image"
BOOTIMG="$OUTDIR/boot.img"
ROOTFSIMG="$OUTDIR/rootfs.img"

echo "Base directory: $BASEDIR"

BOOT_SIZE_MB=256
ROOTFS_IMG_MB=1280

echo "=== Creating ASIAIR Debian image ==="
mkdir -p "$OUTDIR"

# =============================================
# 1. Create boot partition image (ext4, 256 MB)
# =============================================
echo "--- Creating boot partition (${BOOT_SIZE_MB} MB) ---"
dd if=/dev/zero of="$BOOTIMG" bs=1M count=0 seek=$BOOT_SIZE_MB 2>/dev/null
mkfs.ext4 -L boot -q "$BOOTIMG"

BOOTMNT="/tmp/asiair-boot-mount"
mkdir -p "$BOOTMNT"
mount -o loop "$BOOTIMG" "$BOOTMNT"

mkdir -p "$BOOTMNT/extlinux" "$BOOTMNT/dtbs/rockchip"
cp "$LINUX/arch/arm64/boot/Image" "$BOOTMNT/"
cp "$LINUX/arch/arm64/boot/dts/rockchip/rk3568-asiair-plus.dtb" "$BOOTMNT/dtbs/rockchip/"

cat > "$BOOTMNT/extlinux/extlinux.conf" << 'EOF'
label Debian Trixie
  kernel /Image
  fdt /dtbs/rockchip/rk3568-asiair-plus.dtb
  append root=/dev/mmcblk0p3 rootfstype=ext4 rootwait console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfe660000
EOF

echo "Boot partition contents:"
ls -lh "$BOOTMNT/"
umount "$BOOTMNT"
rmdir "$BOOTMNT"

# =============================================
# 2. Create rootfs partition image (ext4)
# =============================================
echo ""
echo "--- Creating rootfs partition (${ROOTFS_IMG_MB} MB image, resizes on first boot) ---"
dd if=/dev/zero of="$ROOTFSIMG" bs=1M count=0 seek=$ROOTFS_IMG_MB 2>/dev/null
mkfs.ext4 -L rootfs -q "$ROOTFSIMG"

ROOTFSMNT="/tmp/asiair-rootfs-mount"
mkdir -p "$ROOTFSMNT"
mount -o loop "$ROOTFSIMG" "$ROOTFSMNT"

echo "Copying rootfs contents..."
cp -a "$ROOTFS"/* "$ROOTFSMNT"/

# Update fstab for new partition layout
cat > "$ROOTFSMNT/etc/fstab" << 'EOF'
# <file system>    <mount point>  <type>  <options>                  <dump> <pass>
/dev/mmcblk0p3     /              ext4    errors=remount-ro          0      1
/dev/mmcblk0p2     /boot          ext4    defaults                   0      2
/dev/mmcblk0p4     none           swap    sw                         0      0
EOF

# Remove /boot contents from rootfs (they live on the boot partition now)
rm -rf "$ROOTFSMNT/boot/"*
mkdir -p "$ROOTFSMNT/boot"

# First-boot resize service
cat > "$ROOTFSMNT/usr/local/sbin/resize-rootfs" << 'RESIZE_EOF'
#!/bin/bash
DEV=/dev/mmcblk0p3
resize2fs "$DEV"
systemctl disable resize-rootfs.service
rm -f /etc/systemd/system/resize-rootfs.service
rm -f /usr/local/sbin/resize-rootfs
echo "Rootfs resized successfully."
RESIZE_EOF
chmod 755 "$ROOTFSMNT/usr/local/sbin/resize-rootfs"

cat > "$ROOTFSMNT/etc/systemd/system/resize-rootfs.service" << 'SERVICE_EOF'
[Unit]
Description=Resize root filesystem to fill partition
DefaultDependencies=no
Before=local-fs-pre.target
After=systemd-remount-fs.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/resize-rootfs
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
SERVICE_EOF

mkdir -p "$ROOTFSMNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/resize-rootfs.service \
  "$ROOTFSMNT/etc/systemd/system/multi-user.target.wants/resize-rootfs.service"

# Install kernel modules
echo "Installing kernel modules..."
cd "$LINUX"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$ROOTFSMNT" modules_install 2>&1 | tail -3

echo ""
df -h "$ROOTFSMNT"
umount "$ROOTFSMNT"
rmdir "$ROOTFSMNT"

# =============================================
# 3. Copy bootloader images
# =============================================
cp "$UBOOT/idbloader.img" "$OUTDIR/"
cp "$UBOOT/u-boot.itb" "$OUTDIR/"

# =============================================
# 4. Summary
# =============================================
echo ""
echo "=== ASIAIR Debian image created ==="
echo ""
ls -lh "$OUTDIR/"
echo ""
echo "Image files in: $OUTDIR/"
echo "  idbloader.img  — write to sector 0x40 (pre-partition)"
echo "  u-boot.itb     — write to sector 0x4000 (uboot partition)"
echo "  boot.img       — write to partition 2 (boot)"
echo "  rootfs.img     — write to partition 3 (rootfs)"
echo ""
echo "Flash with: sudo bash asiair-flash.sh"
