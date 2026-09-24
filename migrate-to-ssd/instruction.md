# Migrating a Jetson to SSD from the flashing PC

How to move a Jetson Orin Nano from an SD card to an NVMe SSD using the same Ubuntu 22.04 PC that you use to flash Jetsons, with the Jetson connected over **USB-C**.

The migration scripts run **on the Jetson**, not on the PC. In recovery mode the PC cannot see the Jetson's SD card or SSD as disks. Instead, you boot the Jetson normally and start the scripts from the PC over the USB-C network link.

There are two ways to do it:

| | Option A: Migrate an existing SD card | Option B: Flash directly to SSD |
|---|---|---|
| Keeps your AIVision / Developer SD card setup | ✅ Yes | ❌ No, you get a clean JetPack install |
| Needs an SD card | Yes (only during migration) | No |
| Tools | This folder (`migrate-to-ssd.sh`) | SDK Manager or `l4t_initrd_flash.sh` |

---

## 🧰 Requirements

- Ubuntu 22.04 PC with this repo cloned on it
- Jetson Orin Nano Developer Kit
- USB-C cable (Jetson ↔ PC)
- **PCIe NVMe** SSD in the Jetson's M.2 Key-M slot. SATA M.2 drives will not work.
  - The SSD must be **larger than the used space** on the SD card
  - Everything on the SSD **will be erased**
- For Option A: a working SD card (AIVision 🟢 or Developer 🟢🟢) that boots the Jetson

---

## Option A: Migrate an existing SD card (recommended)

### 1. Prepare the Jetson

1. Power off the Jetson.
2. **Remove the recovery jumper** (FC REC ↔ GND). The Jetson must boot normally, not in recovery mode.
3. Install the NVMe SSD in the M.2 Key-M slot.
4. Insert the SD card you want to migrate.
5. Connect the Jetson to the PC with the USB-C cable.
6. Power on and wait about 1 minute for it to boot fully.

### 2. Check the connection from the PC

When the Jetson is booted, it appears on the PC as a USB network device. The Jetson is always at `192.168.55.1`.

```bash
ping -c 3 192.168.55.1
```

If the ping fails, see [Troubleshooting](#-troubleshooting).

### 3. Run the migration (one command)

From the root of this repo on the PC (as your normal user, **not** with sudo):

```bash
./migrate-to-ssd/migrate-from-host.sh
```

This script:
1. copies this folder to the Jetson
2. shows the Jetson's disks
3. runs `migrate-to-ssd.sh` on the Jetson
4. offers to power the Jetson off

The Jetson password (`1234`) is asked once for ssh and once for sudo. Answer `y` to the confirmations. Options: `-u <user>`, `-H <host>`, `-s <source>`, `-d <destination>` (see `-h`).

After it powers off, go to [step 6](#6-boot-from-the-ssd). Steps 3b–5 below are the same process done by hand.

### 3b. (Manual) Copy the scripts to the Jetson

Run this from the root of this repo on the PC:

```bash
ssh-keygen -R 192.168.55.1          # forget the previous Jetson's key (safe to run every time)
scp -r migrate-to-ssd aivision@192.168.55.1:~
```

Password: `1234`. The first time, answer `yes` to the fingerprint question.

### 4. Check the disks

```bash
ssh aivision@192.168.55.1 lsblk
```

You should see:
- `mmcblk0` for the SD card, with partitions `mmcblk0p1`, `mmcblk0p2`, … and `/` mounted on `mmcblk0p1`
- `nvme0n1` for the SSD

If `nvme0n1` is missing, the SSD is not detected. Stop and see [Troubleshooting](#-troubleshooting).

### 5. Run the migration

```bash
ssh -t aivision@192.168.55.1 'cd ~/migrate-to-ssd && sudo ./migrate-to-ssd.sh'
```

- `-t` is required because the script asks for confirmation (`y/N`) and for the sudo password.
- Answer `y` to each confirmation. This takes several minutes, depending on how much data is on the SD card.
- Wait for `=== Migration complete ===`.

### 6. Boot from the SSD

```bash
ssh aivision@192.168.55.1 sudo poweroff
```

1. Wait for the Jetson to shut down, then **remove the SD card**.
2. Power the Jetson back on.
3. Check that it booted from the SSD:

```bash
ssh-keygen -R 192.168.55.1
ssh aivision@192.168.55.1 findmnt /
```

`SOURCE` should be `/dev/nvme0n1p1`. ✅ Done.

If it does not boot, see [Fixing boot order](#fixing-boot-order-uefi).

---

## Option B: Flash directly to the SSD

Use this if you want a fresh JetPack install on the SSD and no SD card at all. You will have to set up AIVision/Developer again afterwards (GPIO patch, packages, etc.).

1. Install the SSD in the Jetson and remove the SD card.
2. Put the **recovery jumper** on (FC REC ↔ GND), connect USB-C, and power on.
3. Choose one of the following:

**SDK Manager:** follow the normal flashing guide (`sdkmanager --archived-versions`, JetPack 6.0 rev. 2). In the flash dialog, set **Storage Device → NVMe** instead of SD Card. Keep username `aivision` and password `1234`.

**Command line** (after SDK Manager has downloaded JetPack once):

```bash
cd ~/nvidia/nvidia_sdk/JetPack_6.0_Linux_JETSON_ORIN_NANO_TARGETS/Linux_for_Tegra
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 \
  -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
  -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
  --showlogs --network usb0 jetson-orin-nano-devkit internal
```

4. After the flash finishes, power off, remove the jumper, and power on.

---

## Fixing boot order (UEFI)

If the Jetson still boots from the SD card, or stops at a UEFI shell:

1. Connect an HDMI monitor and keyboard to the Jetson.
2. Power on and press **Esc** at the NVIDIA splash screen.
3. Go to **Boot Maintenance Manager → Boot Options → Change Boot Order**.
4. Move the **NVMe** entry to the top.
5. Press **F10** to save, then reset.

---

## 🔧 Troubleshooting

| Problem | Fix |
|---|---|
| `ping 192.168.55.1` fails | Make sure the recovery jumper is **removed** and the Jetson has fully booted. Try a different USB-C cable (some are charge-only). Run `ip a` on the PC and look for an interface with `192.168.55.100`. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | You connected a different Jetson. Run `ssh-keygen -R 192.168.55.1` and try again. |
| `nvme0n1` missing in `lsblk` | The SSD must be PCIe NVMe (not SATA) and fully seated in the M.2 Key-M slot. Check with `ssh aivision@192.168.55.1 'lspci \| grep -i nvme'`. |
| `is not a block device` | The SD card or SSD has a different name. Check `lsblk` and pass the names: `sudo ./migrate-to-ssd.sh -s /dev/mmcblkX -d /dev/nvmeXn1` |
| Ran out of space during copy | The SSD is smaller than the used space on the SD card. Use a bigger SSD. |
| Boots from SD / UEFI shell after migration | See [Fixing boot order](#fixing-boot-order-uefi). |

---

## Quick reference (Option A)

```bash
# Scripted:
./migrate-to-ssd/migrate-from-host.sh

# Manual equivalent:
# On the PC, from the repo root, with the Jetson booted normally over USB-C
ssh-keygen -R 192.168.55.1
scp -r migrate-to-ssd aivision@192.168.55.1:~
ssh aivision@192.168.55.1 lsblk
ssh -t aivision@192.168.55.1 'cd ~/migrate-to-ssd && sudo ./migrate-to-ssd.sh'
ssh aivision@192.168.55.1 sudo poweroff
# Remove the SD card, power on, then check:
ssh-keygen -R 192.168.55.1
ssh aivision@192.168.55.1 findmnt /
```
