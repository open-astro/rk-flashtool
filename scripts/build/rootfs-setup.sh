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
# ALWAYS undone on exit, error included: a leftover $ROOTFS/dev bind mount is
# catastrophic - a later "rm -rf $ROOTFS" would descend into the real /dev.
cleanup_binds() {
    umount -l "$ROOTFS/sys" "$ROOTFS/proc" "$ROOTFS/dev/pts" "$ROOTFS/dev" 2>/dev/null || true
    # Also release the read-only stock-image loop mount on error exits, so a
    # failed run doesn't leak it until reboot. Harmless if already unmounted.
    if [ "${UNMOUNT_STOCK:-0}" = "1" ]; then
        umount "$STOCKMNT" 2>/dev/null && rmdir "$STOCKMNT" 2>/dev/null || true
    fi
}
trap cleanup_binds EXIT
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/" 2>/dev/null || true

# --- DNS resolver ---
# Written BEFORE any chroot apt-get below: a fresh debootstrap target has no
# resolv.conf, so without this every in-chroot network step (safety-net
# installs, AlpacaBridge) would silently fail on hostname resolution. This is
# also the image's runtime resolver config.
cat > "$ROOTFS/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Debootstrap leaves /var/lib/apt/lists empty, so apt-get install of anything
# outside the --include list has no index to consult. Best-effort like the
# installs themselves - offline builds still finish.
chroot "$ROOTFS" /bin/bash -c "apt-get update -qq" \
    || echo "WARNING: apt-get update failed; safety-net package installs may fail"

# --- Hostname ---
echo "openastro" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'EOF'
127.0.0.1	localhost
127.0.1.1	openastro

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
# Hardware-access groups (only those that exist in this rootfs).
for g in dialout plugdev audio video netdev gpio i2c spi; do
    chroot "$ROOTFS" /bin/bash -c "getent group $g >/dev/null && usermod -aG $g astro" || true
done

# --- SSH ---
chroot "$ROOTFS" /bin/bash -c "systemctl enable ssh"
mkdir -p "$ROOTFS/etc/ssh/sshd_config.d"
cat > "$ROOTFS/etc/ssh/sshd_config.d/openastro.conf" << 'EOF'
PasswordAuthentication yes
PermitRootLogin no
EOF

# Strip the host keys debootstrap generated: every image built from this rootfs
# would otherwise share them fleet-wide. A oneshot regenerates unique keys on
# each unit's first boot, before sshd starts.
rm -f "$ROOTFS/etc/ssh/ssh_host_"*
cat > "$ROOTFS/etc/systemd/system/openastro-sshkeys.service" << 'EOF'
[Unit]
Description=Generate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "$ROOTFS/etc/systemd/system/ssh.service.d"
cat > "$ROOTFS/etc/systemd/system/ssh.service.d/openastro.conf" << 'EOF'
[Unit]
After=openastro-sshkeys.service
Wants=openastro-sshkeys.service
EOF
chroot "$ROOTFS" /bin/bash -c "systemctl enable openastro-sshkeys"

# --- Persistent journald ---
# The directory's existence switches journald to persistent storage.
chroot "$ROOTFS" /bin/bash -c "install -d -m 2755 -g systemd-journal /var/log/journal"

# --- ZWO HID udev rule ---
# ZWO EAF/EFW/filter wheels are USB HID devices (idVendor 03c3); let the
# desktop user talk to them without root.
cat > "$ROOTFS/etc/udev/rules.d/70-openastro-zwo-hid.rules" << 'EOF'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="03c3", GROUP="plugdev", MODE="0666"
KERNEL=="hiddev*", ATTRS{idVendor}=="03c3", GROUP="plugdev", MODE="0666"
EOF

# --- Per-board hotspot SSID (OpenAstro-XXXX) ---
# On first boot, append the last 4 hex digits of the wlan0 MAC to the hotspot
# SSID so every unit broadcasts a unique name. The stamp file prevents a second
# suffix on later boots, and is pre-created at flash time when the user picks a
# custom SSID (see scripts/lib/wifi.sh).
cat > "$ROOTFS/usr/local/sbin/openastro-ssid" << 'EOF'
#!/bin/sh
set -e
STAMP=/var/lib/openastro/ssid-set
KEYFILE=/etc/NetworkManager/system-connections/openastro-ap.nmconnection
[ -e "$STAMP" ] && exit 0
[ -f "$KEYFILE" ] || exit 0
# wlan0 appears once the bcmdhd module has loaded. Wait up to 60s: a slow
# firmware load past a short timeout would leave the AP broadcasting the
# un-suffixed fleet-default SSID for that boot. But only pay that wait a
# few boots: on a unit whose radio never comes up (firmware/hardware
# fault), give up permanently after 3 failed attempts rather than adding
# 60s to every boot forever.
ATTEMPTS=/var/lib/openastro/ssid-attempts
mkdir -p /var/lib/openastro
n=$(cat "$ATTEMPTS" 2>/dev/null || echo 0)
case "$n" in *[!0-9]*|'') n=0 ;; esac
if [ "$n" -ge 3 ]; then exit 0; fi
i=0
while [ ! -e /sys/class/net/wlan0/address ] && [ "$i" -lt 120 ]; do
    sleep 0.5; i=$((i + 1))
done
if [ ! -e /sys/class/net/wlan0/address ]; then
    echo $((n + 1)) > "$ATTEMPTS"
    exit 0
fi
rm -f "$ATTEMPTS"
SUFFIX=$(tr -d ':\n' < /sys/class/net/wlan0/address | tail -c 4 | tr 'a-f' 'A-F')
[ -n "$SUFFIX" ] || exit 0
sed -i "s/^ssid=.*/ssid=OpenAstro-$SUFFIX/; s/^id=.*/id=OpenAstro-$SUFFIX/" "$KEYFILE"
mkdir -p /var/lib/openastro
touch "$STAMP"
EOF
chmod 755 "$ROOTFS/usr/local/sbin/openastro-ssid"
cat > "$ROOTFS/etc/systemd/system/openastro-ssid.service" << 'EOF'
[Unit]
Description=Set per-board OpenAstro hotspot SSID
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/openastro-ssid

[Install]
WantedBy=multi-user.target
EOF
chroot "$ROOTFS" /bin/bash -c "systemctl enable openastro-ssid"

# --- NetworkManager ---
# NM manages ALL interfaces (fleet policy), ethernet included: with no
# ifupdown/systemd-networkd config in this rootfs, eth0 falls to NM's
# default DHCP.
chroot "$ROOTFS" /bin/bash -c "systemctl enable NetworkManager"

# Fleet WiFi conf: no powersave (dropping clients mid-session would strand a
# mount served all night) and no scan MAC randomization (stable radio
# identity).
mkdir -p "$ROOTFS/etc/NetworkManager/conf.d"
cat > "$ROOTFS/etc/NetworkManager/conf.d/20-openastro-wifi.conf" << 'EOF'
[connection]
wifi.powersave=2

[device]
wifi.scan-rand-mac-address=no
EOF

# --- WiFi hotspot dependency ---
# The optional WiFi hotspot (NetworkManager "ipv4 method=shared") needs the
# dnsmasq binary to hand out DHCP leases to clients. Without it the AP radio
# starts but clients can't get an address and activation fails.
# NOTE: this apt-get runs inside the chroot and therefore needs outbound network
# at build time. (The installer's runtime path injects the same dependency
# offline via vendored .debs - see scripts/lib/wifi.sh - so flashing needs no
# network.) Normally dnsmasq-base is already present from the debootstrap
# --include list, so this branch is just a safety net.
if [ ! -x "$ROOTFS/usr/sbin/dnsmasq" ]; then
    echo "Installing dnsmasq-base (required for the WiFi hotspot)..."
    chroot "$ROOTFS" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq-base" \
        || echo "WARNING: could not install dnsmasq-base - the WiFi hotspot will not hand out IPs."
fi

# --- WiFi manager dependencies (AlpacaBridge docs/rk3568-image-notes.md) ---
# polkitd:        REQUIRED - NM authorizes D-Bus callers via polkit; without it
#                 AlpacaBridge's packaged polkit rule does nothing and the
#                 unprivileged alpacabridge user cannot manage WiFi.
# wireless-regdb: the kernel otherwise logs "Direct firmware load for
#                 regulatory.db failed" and falls back to the world regdom.
# iw:             field diagnostics (works unprivileged on this driver).
# wpasupplicant:  REQUIRED - NetworkManager cannot drive ANY wifi device
#                 (AP mode included) without wpa_supplicant; it is only a
#                 Recommends of network-manager, which debootstrap skips.
#                 Without it both wifi devices sit "unavailable" and the
#                 hotspot never comes up.
# Normally present from the debootstrap --include list; safety net like above.
for pkg in polkitd wireless-regdb iw wpasupplicant; do
    if ! chroot "$ROOTFS" dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "Installing $pkg..."
        chroot "$ROOTFS" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg" \
            || echo "WARNING: could not install $pkg."
    fi
done

# --- Time sync ---
# The board has no usable RTC and the stock image shipped no NTP daemon; the
# clock drifting breaks TLS (apt) and Alpaca timestamps. systemd-timesyncd is
# in the debootstrap --include list; enable it (safety-net install like above).
if ! chroot "$ROOTFS" dpkg -s systemd-timesyncd >/dev/null 2>&1; then
    chroot "$ROOTFS" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-timesyncd" \
        || echo "WARNING: could not install systemd-timesyncd."
fi
chroot "$ROOTFS" /bin/bash -c "systemctl enable systemd-timesyncd" || true

# --- Install stock kernel modules (4.19.219) ---
echo "Installing stock kernel modules..."
# debootstrap installs no kernel, so /lib/modules may not exist; without it
# cp -a would create lib/modules AS the 4.19.219 dir (flattened, modprobe
# then finds nothing and WiFi never comes up).
mkdir -p "$ROOTFS/lib/modules"
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

# The stock nvram hardcodes ccode=DE, which disallows 5 GHz ch 149-165 that US
# users should have. Default to US to match the other OpenAstro images; the
# runtime regulatory domain is user-selectable in the AlpacaBridge WiFi card
# (docs/rk3568-image-notes.md item 3).
sed -i 's/^ccode=.*/ccode=US/' \
    "$ROOTFS/lib/firmware/nvram_ap6256.txt" \
    "$FW_DST/nvram_ap6256.txt" "$FW_DST/nvram.txt"

# --- AlpacaBridge (from apt.openastro.net) ---
# On by default since AlpacaBridge 3.4.0 shipped the WiFi manager. Needs
# outbound network in the chroot, same as the dnsmasq safety net above.
# Set INSTALL_ALPACABRIDGE=no to skip.
INSTALL_ALPACABRIDGE="${INSTALL_ALPACABRIDGE:-yes}"
if [ "$INSTALL_ALPACABRIDGE" = yes ]; then
    echo "Configuring apt.openastro.net repository..."
    # Fetch + dearmor the keyring on the build host: the image does not ship
    # gnupg (apt itself never needs it, only the one-time dearmor does).
    # Degrade with a warning on network failure, like the other network-
    # dependent steps above - an offline build must still produce an image.
    repo_ok=0
    # Nothing in the minimal rootfs is guaranteed to have created this
    # directory (no gnupg in the chroot); gpg -o does not create parents.
    mkdir -p "$ROOTFS/usr/share/keyrings"
    if curl -fsSL https://apt.openastro.net/repo/openastro-archive-keyring.gpg \
        | gpg --dearmor --yes -o "$ROOTFS/usr/share/keyrings/openastro-archive-keyring.gpg"; then
        if chroot "$ROOTFS" /bin/bash -c "
            echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openastro-archive-keyring.gpg] https://apt.openastro.net trixie main\" \
                > /etc/apt/sources.list.d/openastro.list
            apt-get update -qq
        "; then
            repo_ok=1
        else
            echo "WARNING: apt.openastro.net update failed"
        fi
    else
        echo "WARNING: could not fetch the apt.openastro.net keyring"
    fi
    if [ "$repo_ok" = 1 ]; then
        echo "Installing AlpacaBridge from apt.openastro.net..."
        chroot "$ROOTFS" /bin/bash -c \
            "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq alpacabridge >/dev/null" \
            || echo "WARNING: AlpacaBridge install failed; image will not ship AlpacaBridge"
    else
        echo "WARNING: apt.openastro.net unavailable; image will not ship AlpacaBridge"
    fi
fi

# --- Auto-load pwm_gpio module ---
mkdir -p "$ROOTFS/etc/modules-load.d"
echo "pwm_gpio" > "$ROOTFS/etc/modules-load.d/pwm-gpio.conf"

# --- Cleanup ---
cleanup_binds
trap - EXIT
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"

echo ""
echo "=== ASIAIR Debian rootfs setup complete ==="
echo "  Hostname: openastro"
echo "  User: astro / astro"
echo "  Root: root / astro (SSH root login disabled)"
echo "  SSH: enabled, unique host keys generated on first boot"
echo "  Kernel modules: stock 4.19.219"
echo "  Firmware: stock (BCM43456 WiFi/BT)"
echo ""
echo "Next: build rootfs image with asiair-stock-flash.sh or manually"
