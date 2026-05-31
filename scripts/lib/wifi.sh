#!/bin/bash
# Shared helper: optionally set up the built-in WiFi as an access point (hotspot)
# in a rootfs image before it is flashed.
#
# The unit broadcasts its own WiFi network that you join from a phone/laptop to
# reach it directly (like the stock ASIAIR hotspot) — it does NOT join an
# existing router. This is the useful mode in the field where there is no other
# network. Clients get an IP via DHCP and the unit answers at 10.42.0.1.
#
# Requirements baked into the image (see scripts/build/rootfs-setup.sh):
#   - NetworkManager (manages the AP)
#   - dnsmasq-base   (NM's "ipv4 method=shared" needs the dnsmasq binary to hand
#                     out DHCP leases; without it the AP radio starts but no
#                     client can get an address and activation fails)
#
# Source this file, then call:  configure_wifi_in_image <path-to-raw-ext4.img>
#
# The image must be a raw (decompressed) ext4 filesystem. Requires root (mount).

# Directory of this library, used to locate the vendored .debs.
_WIFI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Echo a writable directory with at least ~4.5 GB free for the decompressed
# rootfs image. /tmp is often a small RAM-backed tmpfs, so prefer the image's
# own directory (on real disk) and fall back to /var/tmp. Returns 1 if none fit.
# (Lives here because both install and flash-rootfs source this file.)
pick_workdir() {
    local need_kb=4718592   # ~4.5 GB
    local d avail
    for d in "${TMPDIR:-}" "$(dirname "$1")" /var/tmp /tmp; do
        [ -n "$d" ] && [ -d "$d" ] && [ -w "$d" ] || continue
        avail=$(df -Pk "$d" 2>/dev/null | awk 'NR==2{print $4}')
        if [ "${avail:-0}" -ge "$need_kb" ]; then echo "$d"; return 0; fi
    done
    return 1
}

# Write a NetworkManager AP-mode keyfile connection into the mounted rootfs.
# Args: <rootfs-mountpoint> <ssid> <psk> <country>
_wifi_write_profile() {
    local mnt="$1" ssid="$2" psk="$3" country="$4"
    local dir="$mnt/etc/NetworkManager/system-connections"
    local uuid
    uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")"

    mkdir -p "$dir"
    # mode=ap makes wlan0 a hotspot; ipv4 method=shared runs DHCP + NAT so
    # clients get an address (10.42.0.x) and reach the unit at 10.42.0.1.
    cat > "$dir/openastro-ap.nmconnection" << EOF
[connection]
id=$ssid
uuid=$uuid
type=wifi
autoconnect=true
autoconnect-priority=10
interface-name=wlan0

[wifi]
mode=ap
ssid=$ssid
band=bg
channel=6

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=shared

[ipv6]
method=ignore
EOF

    # NetworkManager ignores keyfiles that are group/world readable.
    chmod 600 "$dir/openastro-ap.nmconnection"

    # Regulatory domain (affects allowed channels / TX power).
    if [ -n "$country" ]; then
        mkdir -p "$mnt/etc/NetworkManager/conf.d"
        cat > "$mnt/etc/NetworkManager/conf.d/wifi-country.conf" << EOF
[device]
wifi.country=$country
EOF
    fi
}

# Ensure the dnsmasq binary exists in the mounted rootfs (AP DHCP needs it). If
# missing, extract the vendored .debs straight into the image — the build host
# is the same arch as the target (arm64), so this is just an offline file unpack
# (no chroot/qemu). Returns 1 if it could not be provided.
_wifi_ensure_dnsmasq() {
    local mnt="$1"
    if [ -x "$mnt/usr/sbin/dnsmasq" ] || [ -x "$mnt/usr/bin/dnsmasq" ]; then
        return 0
    fi

    # dnsmasq-base needs libnetfilter-conntrack3, which in turn needs
    # libnfnetlink0 — all three must be present or dnsmasq won't load.
    local debs_dir="$_WIFI_LIB_DIR/../../blobs/debs"
    local debs=(
        "$debs_dir"/dnsmasq-base_*.deb
        "$debs_dir"/libnetfilter-conntrack3_*.deb
        "$debs_dir"/libnfnetlink0_*.deb
    )

    if ! command -v dpkg-deb >/dev/null 2>&1; then
        echo "  WARNING: dpkg-deb not found; cannot inject dnsmasq."
        echo "  The hotspot radio will start but clients won't get an IP."
        return 1
    fi
    local d
    for d in "${debs[@]}"; do
        if [ ! -f "$d" ]; then
            echo "  WARNING: vendored .deb missing ($d); cannot inject dnsmasq."
            echo "  The hotspot radio will start but clients won't get an IP."
            return 1
        fi
    done

    echo "  Injecting dnsmasq into the image (required for the hotspot)..."
    for d in "${debs[@]}"; do
        dpkg-deb -x "$d" "$mnt" || {
            echo "  ERROR: failed to extract $(basename "$d") into the image."
            return 1
        }
    done
    return 0
}

# Prompt the user about the WiFi hotspot and, if they opt in, inject the AP
# profile into the given raw rootfs image. Returns 0 whether or not WiFi was
# configured; returns non-zero only on a hard failure (mount/write error).
configure_wifi_in_image() {
    local image="$1"

    # Non-interactive escape for scripted/headless use:
    #   OPENASTRO_WIFI=no  (or 0/false)  skips hotspot setup without prompting.
    case "${OPENASTRO_WIFI:-}" in
        no|NO|No|0|false|FALSE)
            echo "Skipping WiFi hotspot setup (OPENASTRO_WIFI=$OPENASTRO_WIFI)."
            return 0
            ;;
    esac

    echo ""
    echo "========================================"
    echo "  WiFi hotspot setup"
    echo "========================================"
    echo ""
    echo "The unit can broadcast its own WiFi network that you join from a phone"
    echo "or laptop to connect to it directly (like the stock ASIAIR hotspot)."
    echo ""
    echo "Skip this if you only connect over the wired Ethernet port."
    echo ""

    local use_wifi
    read -rp "Set up the built-in WiFi hotspot now? [y/N] " use_wifi
    case "$use_wifi" in
        [yY]*) ;;
        *)
            echo "Leaving WiFi off — use the wired Ethernet port to connect."
            return 0
            ;;
    esac

    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: configuring WiFi requires root (re-run with sudo)."
        return 1
    fi

    # Reject control characters (incl. a stray CR from CRLF input): they would
    # silently corrupt the NetworkManager keyfile, which is line-oriented INI.
    local ssid=""
    while [ -z "$ssid" ]; do
        read -rp "  Hotspot name (SSID) to broadcast: " ssid
        if [ -z "$ssid" ]; then
            echo "  SSID cannot be empty."
        elif [[ "$ssid" == *[[:cntrl:]]* ]]; then
            echo "  SSID contains invalid (control) characters."
            ssid=""
        fi
    done

    local psk="" psk2=""
    while true; do
        read -rsp "  Hotspot password: " psk; echo ""
        if [ ${#psk} -lt 8 ]; then
            echo "  WPA passwords must be at least 8 characters."
            continue
        elif [[ "$psk" == *[[:cntrl:]]* ]]; then
            echo "  Password contains invalid (control) characters."
            continue
        fi
        read -rsp "  Confirm password: " psk2; echo ""
        [ "$psk" = "$psk2" ] && break
        echo "  Passwords did not match — try again."
    done

    local country
    read -rp "  WiFi country code [US]: " country
    country="${country:-US}"

    local mnt
    mnt="$(mktemp -d /tmp/openastro-wifi-mount-XXXXXX)"
    if ! mount -o loop "$image" "$mnt"; then
        echo "ERROR: could not mount rootfs image to inject WiFi config."
        rmdir "$mnt"
        return 1
    fi

    # Always unmount, even if a step below fails under 'set -e'. Using '|| rc=…'
    # disables set -e for these calls, so we reach the umount instead of leaking
    # the loop mount. (A bare EXIT trap would clobber the caller's own trap.)
    local rc=0 dns_failed=0
    _wifi_write_profile "$mnt" "$ssid" "$psk" "$country" || rc=1
    # AP mode is useless without dnsmasq (DHCP for clients) — inject if missing.
    [ $rc -eq 0 ] && { _wifi_ensure_dnsmasq "$mnt" || dns_failed=1; }

    sync
    umount "$mnt" 2>/dev/null
    rmdir "$mnt" 2>/dev/null

    if [ $rc -ne 0 ]; then
        echo "ERROR: failed to write the WiFi profile into the image."
        return 1
    fi

    # dnsmasq injection failed: the hotspot would broadcast but hand out no IPs.
    # Let the user decide rather than silently flashing a half-working hotspot.
    if [ $dns_failed -ne 0 ]; then
        echo ""
        echo "Without dnsmasq the hotspot will broadcast but clients can't get an"
        echo "IP address, so they won't be able to connect."
        local ans
        read -rp "Continue flashing anyway? [y/N] " ans
        case "$ans" in
            [yY]*) ;;
            *) echo "Aborted WiFi setup."; return 1 ;;
        esac
    fi

    echo ""
    echo "WiFi hotspot \"$ssid\" configured (country $country)."
    echo "After boot, join \"$ssid\" from your device, then:"
    echo "  ssh astro@10.42.0.1"
    echo "(astro.local also works if your client supports mDNS/Bonjour.)"
    return 0
}
