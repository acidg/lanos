#!/usr/bin/env bash
# Put an SSH public key on a LANOS stick (or image file), so the stick accepts SSH
# logins as "player" with that key. The key lands on the ESP, which is written without
# mounting anything; the image itself never contains a key.
#
# Use one key for all sticks, kept on the PC that creates them. Create it once with:
#   ssh-keygen -t ed25519 -f ~/.ssh/lanos_ed25519 -C lanos-master
#
# Usage: scripts/add-ssh-key.sh <device-or-image> [public key file]
#   The key defaults to ~/.ssh/lanos_ed25519.pub.
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 1 || $# -eq 2 ]] || die "usage: $0 <device-or-image> [public key file]"
target=$1
key=${2:-$HOME/.ssh/lanos_ed25519.pub}
repo=$(cd "$(dirname "$0")/.." && pwd)

[[ -e $target ]] || die "$target does not exist"
[[ -f $key ]] || die "no public key at $key, create one with: ssh-keygen -t ed25519 -f ${key%.pub} -C lanos-master"
ssh-keygen -l -f "$key" > /dev/null || die "$key is not an SSH public key"

sudo=()
[[ -w $target ]] || sudo=(sudo)

# The ESP is the first partition. The image uses 512-byte sectors.
start=$("${sudo[@]}" partx -g -o START -n 1 "$target")
esp="$target@@$((start * 512))"

mtools=$(nix build --inputs-from "$repo" --no-link --print-out-paths 'nixpkgs#mtools^out')/bin
mtool() { "${sudo[@]}" env MTOOLS_SKIP_CHECK=1 "$mtools/$1" -i "$esp" "${@:2}"; }

mtool mdir ::/lanos > /dev/null 2>&1 || mtool mmd ::/lanos
mtool mcopy -o "$key" ::/lanos/authorized_keys
echo "Installed $(ssh-keygen -l -f "$key") on $target"
