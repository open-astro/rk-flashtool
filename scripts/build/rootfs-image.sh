#!/bin/bash
set -e

# Build an ext4 rootfs image from the Trixie rootfs directory.
# The resulting image can be flashed to the ASIAIR with scripts/flash-rootfs.
#
# Prerequisites:
#   - Debian rootfs at $BASEDIR/asiair-rootfs (from debootstrap + rootfs-setup.sh)
#
# Usage: sudo scripts/build/rootfs-image.sh

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASEDIR="$(dirname "$REPODIR")"
ROOTFS="$BASEDIR/asiair-rootfs"
OUTDIR="$BASEDIR/asiair-image"
ROOTFS_IMG="$OUTDIR/rootfs-stock.img"
ROOTFS_IMG_MB=4096

if [ ! -d "$ROOTFS/etc" ]; then
    echo "ERROR: Rootfs not found at $ROOTFS"
    echo "Run scripts/build/rootfs-setup.sh first."
    exit 1
fi

echo ""
echo "=== Building OpenAstro Linux rootfs image (${ROOTFS_IMG_MB} MB) ==="
echo ""

mkdir -p "$OUTDIR"
dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count=0 seek=$ROOTFS_IMG_MB 2>/dev/null
mkfs.ext4 -L rootfs -q "$ROOTFS_IMG"

ROOTFSMNT="/tmp/asiair-rootfs-mount"
mkdir -p "$ROOTFSMNT"
mount -o loop "$ROOTFS_IMG" "$ROOTFSMNT"

echo "Copying rootfs contents..."
cp -a "$ROOTFS"/* "$ROOTFSMNT"/

echo ""
df -h "$ROOTFSMNT"
umount "$ROOTFSMNT"
rmdir "$ROOTFSMNT"

echo ""
echo "Image ready: $ROOTFS_IMG ($(du -h "$ROOTFS_IMG" | cut -f1))"
echo ""
echo "Flash with: sudo scripts/flash-rootfs $ROOTFS_IMG"
echo "  or:       sudo scripts/flash-all $ROOTFS_IMG"
