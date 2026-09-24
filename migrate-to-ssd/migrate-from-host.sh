#!/bin/bash
# Runs the SD -> SSD migration on a Jetson from the flashing PC over the USB-C network link.
# Copies this folder to the Jetson, shows its disks, runs migrate-to-ssd.sh there via ssh,
# then optionally powers the Jetson off. The Jetson must be booted normally (no recovery jumper).
# Run as your normal user on the PC (not sudo); you'll be asked for the Jetson's password.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

JETSON_HOST="192.168.55.1"
JETSON_USER="aivision"
SOURCE="/dev/mmcblk0"
DESTINATION="/dev/nvme0n1"

usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Migrate a USB-C connected Jetson from its SD card to its SSD, driven from this PC."
    echo
    echo "Options:"
    echo "  -H, --host        Jetson address (default: $JETSON_HOST)"
    echo "  -u, --user        Jetson username (default: $JETSON_USER)"
    echo "  -s, --source      Source disk on the Jetson (default: $SOURCE)"
    echo "  -d, --destination Destination disk on the Jetson (default: $DESTINATION)"
    echo "  -h, --help        Show this help message and exit"
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -H|--host)
            JETSON_HOST="$2"
            shift 2
            ;;
        -u|--user)
            JETSON_USER="$2"
            shift 2
            ;;
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not with sudo (sudo is used on the Jetson side)." >&2
    exit 1
fi

TARGET="$JETSON_USER@$JETSON_HOST"

# Share one ssh connection across all steps so the password is only asked once.
CONTROL_PATH="$(mktemp -u /tmp/migrate-ssd-ssh.XXXXXX)"
SSH_OPTS=(-o ControlMaster=auto -o ControlPath="$CONTROL_PATH" -o ControlPersist=15m
          -o StrictHostKeyChecking=accept-new)
cleanup() {
    ssh -o ControlPath="$CONTROL_PATH" -O exit "$TARGET" &>/dev/null || true
}
trap cleanup EXIT

echo "=== Jetson SD -> SSD migration (from host) ==="
echo "Jetson: $TARGET"
echo

echo "--- Checking connection ---"
if ! ping -c 2 -W 2 "$JETSON_HOST" &>/dev/null; then
    echo "Error: cannot reach $JETSON_HOST." >&2
    echo "Make sure the recovery jumper is removed, the Jetson has fully booted," >&2
    echo "and the USB-C cable supports data." >&2
    exit 1
fi

# Every Jetson on the bench shares the same address, so drop the previous one's host key.
ssh-keygen -R "$JETSON_HOST" &>/dev/null || true

echo "--- Copying migration scripts to the Jetson ---"
tar -C "$SCRIPT_DIR/.." -cf - "$(basename "$SCRIPT_DIR")" \
    | ssh "${SSH_OPTS[@]}" "$TARGET" 'rm -rf ~/migrate-to-ssd && mkdir -p ~/migrate-to-ssd && tar -xf - -C ~/migrate-to-ssd --strip-components=1'

echo
echo "--- Disks on the Jetson ---"
ssh "${SSH_OPTS[@]}" "$TARGET" lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
echo

REMOTE_CMD="cd ~/migrate-to-ssd && sudo ./migrate-to-ssd.sh -s $(printf '%q' "$SOURCE") -d $(printf '%q' "$DESTINATION")"

echo "--- Running migration on the Jetson ---"
ssh -t "${SSH_OPTS[@]}" "$TARGET" "$REMOTE_CMD"

echo
read -r -p "Power off the Jetson now so you can remove the SD card? (y/N): " CONFIRM
if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
    ssh -t "${SSH_OPTS[@]}" "$TARGET" 'sudo poweroff' || true
    echo
    echo "Wait for the Jetson to shut down, remove the SD card, and power it on again."
else
    echo "Leaving the Jetson running. Power it off before removing the SD card."
fi

echo
echo "After it boots, verify it's running from the SSD with:"
echo "  ssh-keygen -R $JETSON_HOST && ssh $TARGET findmnt /"
echo "SOURCE should be ${DESTINATION}p1."
