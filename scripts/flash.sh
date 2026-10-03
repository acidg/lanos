#!/usr/bin/env bash
# Write the LANOS image to a USB stick.
#
# Refuses anything that is not an unmounted, USB-attached whole disk and asks for
# confirmation. USB SSD sticks often report themselves as non-removable, so the
# transport is checked instead of the removable flag.
#
# Afterwards the SSH public key is added (see add-ssh-key.sh). Without an explicit key
# the default ~/.ssh/lanos_ed25519.pub is used if it exists; otherwise the stick gets
# no remote access.
#
# Usage: scripts/flash.sh /dev/sdX [public key file]
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 1 || $# -eq 2 ]] || die "usage: $0 /dev/sdX [public key file]"
dev=$1
default_key="$HOME/.ssh/lanos_ed25519.pub"
key=${2:-$default_key}
repo=$(cd "$(dirname "$0")/.." && pwd)
image_dir="$repo/result-image"
image="$image_dir/lanos.img"
bmap="$image_dir/lanos.bmap"

[[ -f $image ]] || die "no image at $image, build it first: nix build .#image -o result-image"
[[ $# -eq 1 || -f $key ]] || die "no public key at $key"
[[ -b $dev ]] || die "$dev is not a block device"
[[ $(lsblk -dno TYPE "$dev") == disk ]] || die "$dev is not a whole disk"
[[ $(lsblk -dno TRAN "$dev") == usb ]] || die "$dev is not attached via USB"
mounts=$(lsblk -no MOUNTPOINTS "$dev" | grep -v '^$' || true)
[[ -z $mounts ]] || die "$dev has mounted filesystems, unmount them first: $mounts"

image_size=$(stat -c %s "$image")
dev_size=$(lsblk -bdno SIZE "$dev")
((dev_size >= image_size)) || die "$dev is smaller than the image"

lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS "$dev"
read -rp "Everything on $dev will be erased. Type the device path to continue: " answer
[[ $answer == "$dev" ]] || die "aborted"

bmaptool=$(nix build --inputs-from "$repo" --no-link --print-out-paths nixpkgs#bmaptool)/bin/bmaptool

# Ask for the password once, then keep sudo's timestamp fresh during the long copy, so
# the following steps do not prompt again while nobody is watching.
sudo -v
while sudo -n -v 2> /dev/null; do sleep 60; done &
keepalive=$!
trap 'kill "$keepalive" 2> /dev/null' EXIT

sudo "$bmaptool" copy --bmap "$bmap" "$image" "$dev"

if [[ -f $key ]]; then
  "$repo/scripts/add-ssh-key.sh" "$dev" "$key"
else
  echo "No SSH key at $default_key, the stick has no remote access."
fi
echo "Done. Partitions grow to fill the stick on its first boot."
