# ASIAIR Mini RV1126 — Maskrom Recovery Guide

## Device Identity

| Property | Value |
|----------|-------|
| SoC | RV1126 (ARMv7, Cortex-A7, quad-core) |
| USB VID | 0x2207 (Rockchip) |
| USB PID | 0x110B |
| RAM | 2 GB DDR3 (~1.75 GB usable) |
| eMMC | 32 GB (61079552 sectors), Biwin, manfid 0xF4 |
| Kernel | 4.19.111 (SMP PREEMPT, armv7l) |
| OS | Raspbian GNU/Linux 10 (buster) |
| dmesg model | "Rockchip RV1126 AirMini Board" |
| WiFi | AP6256 (Broadcom BCM43456), driver: bcmdhd |
| USB hub | Cypress USB 2.0 Hub (VID 04b4, PID 6572) |
| Power | USB-C bus powered (no DC adapter needed) |

**Note:** The USB PID 0x110B is shared between RV1106 and RV1126. The ASIAIR Mini
uses the RV1126 despite the PID suggesting otherwise. Confirmed via `dmesg` on a
jailbroken unit.

## WiFi / Network

The ASIAIR Mini runs hostapd on a virtual AP interface (`uap0`) with `wlan0`
available for upstream client connections (bridge mode).

| Property | Value |
|----------|-------|
| SSID pattern | `ASIAIR_XXXXXXXX` (hex suffix, unique per unit) |
| Default password | `12345678` |
| Gateway IP | `10.0.0.1/24` |
| 5 GHz | Channel 36, 802.11n (hw_mode=a) |
| 2.4 GHz | Channel 11, 802.11n (hw_mode=g) |
| Encryption | WPA2-PSK (CCMP) |
| Config files | `/home/pi/AP_5G.conf`, `/home/pi/AP_2.4G.conf` |
| Active config | `/home/pi/wlan0.conf` (copied from 5G or 2.4G) |

SSH access (after jailbreak): `ssh pi@10.0.0.1` (password: `raspberry`)

## ASIAIR Application

The ZWO ASIAIR app lives in `/home/pi/ASIAIR/bin/` and consists of:

| Process | Ports | Purpose |
|---------|-------|---------|
| `zwoair_updater` | 4350, 4360 | OTA updates (jailbreak target) |
| `zwoair_guider` | 4030, 4040, 4400, 4500 | Autoguiding |
| `zwoair_imager` | 4700, 4800, 4801 | Imaging / camera control |
| `sshd` | 22 | OpenSSH (after jailbreak) |
| `smbd` | 139, 445 | Samba file sharing |

Port 4801 is present on recent firmware (previously used to distinguish
firmware versions, but now present on the Mini regardless).

## Partition Table (from full_backup.img)

| # | Name       | Start Sector | Size     | Purpose                          |
|---|------------|-------------|----------|----------------------------------|
| 1 | uboot      | 0x4000      | 4 MB     | Rockchip U-Boot                  |
| 2 | misc       | 0x6000      | 4 MB     | A/B slot metadata                |
| 3 | boot       | 0x8000      | 64 MB    | Kernel + ramdisk                 |
| 4 | recovery   | 0x28000     | 32 MB    | Recovery image                   |
| 5 | asiair     | 0x38000     | 20 GB    | Image storage (astrophotography) |
| 6 | pi         | 0x2838000   | 512 MB   | /home/pi                         |
| 7 | rootfs     | 0x2938000   | 7 GB     | Root filesystem                  |
| 8 | swap grow  | 0x3738000   | 1.5 GB   | Swap                             |

Pre-partition area: sectors 0–16383 (8 MB) contain GPT header + IDB bootloader.

## Maskrom Recovery

When the ASIAIR Mini's bootloader is corrupted, it enters Maskrom mode on USB
power-up. The device appears as `Vid=0x2207,Pid=0x110b` but flash commands fail
until DDR is initialized.

### The DDR Problem

Generic DDR init blobs from rkbin (`rv1126_ddr_924MHz_v1.14.bin`) **do not work**
with the ASIAIR Mini. ZWO uses custom DDR timing parameters. Sending the generic
blob will hang or fail silently.

The solution is to extract ZWO's stock DDR init from the backup image's IDB
(ID Block), which lives at sector 64 of the eMMC.

### IDB Format (Rockchip)

The IDB starts at sector 64 (byte offset 0x8000) and contains:

- **Header** (4 sectors, RC4-encrypted): magic, entry table for DDR init + loader
- **DDR init blob** (code 0x471): initializes DRAM so the SoC can execute from memory
- **SPL/usbplug** (code 0x472): provides USB flash access after DDR is up

The first 4 sectors of the IDB are RC4-encrypted with a fixed key:
```
{124, 78, 3, 4, 85, 5, 9, 7, 45, 44, 123, 56, 23, 13, 23, 17}
```

After decryption, the header contains entry offsets and sizes for each component.

### Extracting Stock DDR Init from Backup

If you have a `full_backup.img` (sector-for-sector dump of the eMMC), the DDR
init blob can be extracted:

```python
#!/usr/bin/env python3
"""Extract DDR init blob from Rockchip IDB in a backup image."""
import struct, sys

RC4_KEY = bytes([124, 78, 3, 4, 85, 5, 9, 7, 45, 44, 123, 56, 23, 13, 23, 17])

def rc4_decrypt(key, data):
    S = list(range(256))
    j = 0
    for i in range(256):
        j = (j + S[i] + key[i % len(key)]) & 0xFF
        S[i], S[j] = S[j], S[i]
    i = j = 0
    out = bytearray(len(data))
    for k in range(len(data)):
        i = (i + 1) & 0xFF
        j = (j + S[i]) & 0xFF
        S[i], S[j] = S[j], S[i]
        out[k] = data[k] ^ S[(S[i] + S[j]) & 0xFF]
    return bytes(out)

with open(sys.argv[1], 'rb') as f:
    # IDB is at sector 64 (offset 0x8000)
    f.seek(64 * 512)
    hdr_enc = f.read(4 * 512)

hdr = rc4_decrypt(RC4_KEY, hdr_enc)
magic = struct.unpack_from('<I', hdr, 0)[0]
print(f"IDB magic: {magic:#x} ({'valid' if magic == 0x0FF0AA55 else 'INVALID'})")

# Entry table starts at offset 32 in decrypted header
# Each entry: 1B type, 2B sector_offset (from IDB start), 2B sector_count, ...
# DDR init is code 0x471 (entry type 1), usbplug is code 0x472 (entry type 2)
entry_count = struct.unpack_from('<B', hdr, 12)[0]
for i in range(entry_count):
    off = 32 + i * 8  # simplified — actual struct varies by IDB version
    # Parse and extract based on your IDB version

print("Dump raw IDB area for manual extraction:")
print(f"  dd if={sys.argv[1]} of=stock_idb.bin bs=512 skip=64 count=512")
```

In practice, the simplest approach is to dump the IDB area and use it directly
with `rk-flashtool db` or build a loader from the stock components:

```bash
# Extract raw IDB from backup (sectors 64-575, covers DDR + SPL)
dd if=full_backup.img of=stock_idb.bin bs=512 skip=64 count=512

# Or use the full pre-partition area which includes the IDB
dd if=full_backup.img of=stock_bootloader.bin bs=512 count=16384
```

### Prerequisites

- `full_backup.img` — full eMMC dump of a working ASIAIR Mini
- `rv1126_usbplug_v1.24.bin` from rkbin (`bin/rv11/rv1126_usbplug_v1.24.bin`)
- Stock DDR init extracted from backup (see above)
- rk-flashtool built with RV1126 support (PID 0x110B)
- udev rule installed: `sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/`
- USB-C cable between ASIAIR Mini and PC

### Step-by-Step Recovery

```bash
# 1. Connect ASIAIR Mini via USB-C (powers from USB, no DC needed)

# 2. Verify Maskrom mode
./rk-flashtool ld
# Expected: DevNo=1  Vid=0x2207,Pid=0x110b,LocationID=...  Maskrom

# 3. Upload stock DDR init + usbplug to RAM
#    The 'db' command sends code 0x471 (DDR init) then 0x472 (usbplug)
#    from a combined loader binary.
#
#    Option A: Use the stock SPL loader if you have one
./rk-flashtool db rv1126_spl_loader_stock.bin

#    Option B: Use rkbin's generic loader (WILL FAIL on ASIAIR Mini
#    due to custom DDR timing — listed here only for reference)
#    ./rk-flashtool db ../rkbin/rv1126_spl_loader_v1.14.110.bin  # DON'T USE

# 4. Wait for DDR init + usbplug to load
sleep 3

# 5. Verify flash access
./rk-flashtool rci
# Expected: chip info output (confirms DDR is up and usbplug is running)

# 6. Write full backup image to eMMC (30 GB, takes ~45 minutes over USB)
./rk-flashtool wl 0 /path/to/full_backup.img

# 7. After write completes, unplug and reconnect USB to reboot
```

### Troubleshooting

**"Creating Comm Object failed!"**
- Check udev rule is installed and reloaded (`sudo udevadm control --reload-rules`)
- Kill any stale processes holding the USB device: `sudo lsof /dev/bus/usb/*`
- Unplug and re-plug USB

**DDR init hangs (no response after `db` command)**
- You're using a generic DDR blob. The ASIAIR Mini needs its stock DDR init
  extracted from a backup image. See "Extracting Stock DDR Init" above.

**Write appears stuck at low percentage**
- 30 GB over USB 2.0 takes ~45 minutes. The progress updates are infrequent
  for the first few percent. Be patient.

**Wrong SoC identification (RV1106 vs RV1126)**
- PID 0x110B is shared. The ASIAIR Mini is RV1126, not RV1106. Confirmed by
  `dmesg` on a jailbroken unit: "Machine model: Rockchip RV1126 AirMini Board"

## Differences from ASIAIR Plus (RK3568)

| | ASIAIR Plus | ASIAIR Mini |
|---|---|---|
| SoC | RK3568 (ARM64, Cortex-A55) | RV1126 (ARMv7, Cortex-A7, quad-core) |
| RAM | 4 GB | 2 GB DDR3 |
| eMMC | 256 GB | 32 GB (Biwin) |
| Power | 12V DC required | USB-C bus powered |
| Kernel | 4.19.x (aarch64) | 4.19.111 (armv7l) |
| OS | Raspbian GNU/Linux 10 | Raspbian GNU/Linux 10 (buster) |
| WiFi chip | AP6275S (BCM43752) | AP6256 (BCM43456) |
| WiFi gateway | 10.0.0.1 | 10.0.0.1 |
| DDR init | Generic rkbin blob works | **Stock blob required** (custom DDR timing) |
| SPL loader | `rk356x_spl_loader_v1.23.114.bin` | Must extract from backup |
| Maskrom entry | Automatic (no bootloader = Maskrom) | Automatic (same behavior) |
| USB PID | 0x350A | 0x110B |

## Setup

```bash
# Install udev rule (one-time, requires sudo)
sudo cp 99-rk-rockusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# Build rk-flashtool (includes RV1126 support)
autoreconf -i && ./configure && make
```
