# migrate-to-ssd

Move a working SD-card Jetson installation onto an NVMe SSD and make the SSD the primary boot device — done entirely on the Jetson itself, no host PC or SDK Manager required.

The three step scripts (`make_partitions.sh`, `copy_partitions.sh`, `configure_ssd_boot.sh`) are vendored unmodified from [jetsonhacks/migrate-jetson-to-ssd](https://github.com/jetsonhacks/migrate-jetson-to-ssd). `migrate-to-ssd.sh` is a local wrapper that runs all three in order. Tested on JetPack 6.x with a Jetson Orin Nano/NX Developer Kit.

**Doing this from the flashing PC over USB-C?** See [instruction.md](instruction.md) and run `./migrate-from-host.sh` from the PC.

## When to use this

You currently boot from a microSD card and want the Jetson to boot from an NVMe SSD instead, keeping the same OS/config you already have set up (rather than reflashing from scratch).

## Prerequisites

- Jetson Orin Nano/NX Developer Kit, currently booted and running from the SD card.
- An NVMe SSD (PCIe — **SATA M.2 drives will not work**) installed in the M.2 Key-M slot, **unformatted / no existing partitions**. Back up anything on it first — the migration scripts will wipe it.
- The SSD must have **more capacity** than the SD card's used space.
- Root/sudo access.
- The SSD must not be mounted while preparing it (unmount it if your file manager auto-mounted it).

## Overview

1. Partition the SSD to mirror the SD card layout.
2. Clone (copy) the SD card's contents onto the SSD.
3. Reconfigure the bootloader (`extlinux.conf`) and `/etc/fstab` to point at the SSD.
4. Reboot. The Jetson's UEFI firmware will boot from NVMe automatically if it finds a valid bootloader there; if it doesn't, fix the boot order once from the UEFI menu.

## Steps

### Option A: one command

```bash
cd migrate-to-ssd
sudo ./migrate-to-ssd.sh
```

This runs all three steps below in order, stopping immediately if any step fails. It prompts once up front for confirmation (the underlying scripts also each confirm before touching the destination disk). Pass `-s /dev/mmcblkX -d /dev/nvme0n1` if your source/destination devices differ from the defaults (`/dev/mmcblk0` → `/dev/nvme0n1`).

### Option B: step by step

```bash
cd migrate-to-ssd

# 1. Create the partition table on the SSD
sudo bash make_partitions.sh

# 2. Copy the SD card's partitions onto the SSD
sudo bash copy_partitions.sh

# 3. Point the bootloader and fstab at the SSD (updates extlinux.conf + fstab UUIDs)
sudo bash configure_ssd_boot.sh
```

Either way, once it finishes, power off, remove the SD card (optional but recommended — see below), and reboot.

```bash
sudo poweroff
```

## Verifying / fixing boot order (UEFI)

Jetson's UEFI firmware normally picks up the new NVMe bootloader automatically once `configure_ssd_boot.sh` has run. If it still boots from the SD card, or drops to a UEFI shell, force NVMe first manually:

1. Reboot and watch the console/HDMI output; press **Esc** at the NVIDIA splash screen to enter the UEFI setup menu.
2. Go to **Boot Maintenance Manager → Boot Options → Change Boot Order**.
3. Move the NVMe entry above the SD card / `removable` entry.
4. Save (F10) and reset.

After confirming the Jetson boots and runs correctly from the SSD, you can leave the SD card out entirely — the board will keep booting straight to NVMe.

## Troubleshooting

- **Stuck at a UEFI shell**: the bootloader is on the NVMe drive but isn't marked as the default boot target yet — use the manual boot-order steps above.
- **SSD not detected**: confirm it's a PCIe NVMe drive (not SATA) and properly seated in the M.2 Key-M slot; check `lspci | grep -i nvme` and `lsblk` while still booted from the SD card.
- **Ran out of space during copy**: the SSD must be larger than the used space on the SD card — free up space on the SD card or use a bigger SSD.

## References

- [jetsonhacks/migrate-jetson-to-ssd](https://github.com/jetsonhacks/migrate-jetson-to-ssd) — the toolkit these steps are based on.
- [jetsonhacks/bootFromExternalStorage](https://github.com/jetsonhacks/bootFromExternalStorage) — alternative host-PC-based flashing approach if you'd rather set up the SSD from a fresh flash instead of migrating an existing SD install.
- [Jetson Orin Nano Developer Kit Quick Start Guide](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/quick_start.html) — NVIDIA's official setup docs.
