#!/bin/bash
set -e

# Build the mainline p3 boot image for the ASIAIR Plus.
#
# Kernel: Armbian 26.8.1 6.18.43-current-rockchip64 (same pinned package and
#         SHA256 as rootfs-setup.sh KERNEL_FLAVOR=mainline).
# DTB:    hardware/asiair-plus-rk3568-256g/mainline/6.18.43-recovered/
#         rk3568-asiair-plus-fixed.dts, compiled here.
# Format: Android boot header v0 + Rockchip RSCE resource (rk-kernel.dtb plus
#         the stock logos), which the stock U-Boot reads. The stock U-Boot also
#         takes the download (Loader) key and the kernel command line from
#         this DTB.
#
# Usage: scripts/build/mainline-boot-image.sh [output.img]
# Env:   ARMBIAN_KERNEL_DEB  use this .deb instead of the cached download
#        STOCK_P3            stock p3 backup to copy the logos from (optional)

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASEDIR="$(dirname "$REPODIR")"
MAINLINE_DIR="$REPODIR/hardware/asiair-plus-rk3568-256g/mainline/6.18.43-recovered"
OUT="${1:-$BASEDIR/asiair-image/boot-mainline-6.18.43.img}"

MAINLINE_KVER="6.18.43-current-rockchip64"
MAINLINE_DEB_NAME="linux-image-current-rockchip64_26.8.1_arm64__6.18.43-S7b92-D16a2-P2f29-C40fc-H2153-HK01ba-Vc222-Be92d-R448a.deb"
MAINLINE_DEB_URL="https://apt.armbian.com/pool/main/l/linux-6.18.43/$MAINLINE_DEB_NAME"
MAINLINE_DEB_SHA256="cb29003f4a1ae5b9394d6c9dda9271d5295fc7838312d23700de947ef77a3764"

for t in dtc dpkg-deb python3 curl sha256sum; do
    command -v "$t" >/dev/null || { echo "ERROR: $t is required"; exit 1; }
done

if [ -z "${ARMBIAN_KERNEL_DEB:-}" ]; then
    KCACHE="$BASEDIR/asiair-kernel-cache"
    mkdir -p "$KCACHE"
    ARMBIAN_KERNEL_DEB="$KCACHE/$MAINLINE_DEB_NAME"
    if [ ! -f "$ARMBIAN_KERNEL_DEB" ]; then
        echo "Downloading Armbian kernel $MAINLINE_KVER..."
        curl -fL --retry 3 -o "$ARMBIAN_KERNEL_DEB.part" "$MAINLINE_DEB_URL"
        mv "$ARMBIAN_KERNEL_DEB.part" "$ARMBIAN_KERNEL_DEB"
    fi
fi
echo "$MAINLINE_DEB_SHA256  $ARMBIAN_KERNEL_DEB" | sha256sum -c --quiet \
    || { echo "ERROR: $ARMBIAN_KERNEL_DEB failed its SHA256 check"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dpkg-deb -x "$ARMBIAN_KERNEL_DEB" "$WORK/deb"
KERNEL="$WORK/deb/boot/vmlinuz-$MAINLINE_KVER"
[ -f "$KERNEL" ] || { echo "ERROR: $KERNEL not in the package"; exit 1; }

dtc -I dts -O dtb -q -o "$WORK/board.dtb" "$MAINLINE_DIR/rk3568-asiair-plus-fixed.dts"

LOGOS=()
if [ -n "${STOCK_P3:-}" ]; then
    [ -f "$STOCK_P3" ] || { echo "ERROR: STOCK_P3=$STOCK_P3 not found"; exit 1; }
    LOGOS=(--logos-from "$STOCK_P3")
fi

mkdir -p "$(dirname "$OUT")"
python3 -I "$REPODIR/scripts/build/mkbootimg-asiair.py" \
    --kernel "$KERNEL" --dtb "$WORK/board.dtb" "${LOGOS[@]}" -o "$OUT"
sha256sum "$OUT" | tee "$OUT.sha256"
echo "Flash to p3 (sector 0x8000), e.g.: sudo ./rk-flashtool wl 0x8000 $OUT"
