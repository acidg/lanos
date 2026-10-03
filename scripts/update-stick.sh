#!/usr/bin/env bash
# Update a running LANOS stick over the network to the system in this checkout. Only
# store paths the stick does not have yet are copied, and the player's data stays. The
# stick keeps no older system; to revert, run this again from an older checkout.
#
# The new system becomes the boot default and takes effect on the next boot: a stick
# may be running one of the Nvidia boot entries, and switching it live would replace
# that with the default system.
#
# Usage: scripts/update-stick.sh <host> [private key file]
#   The key defaults to ~/.ssh/lanos_ed25519.
#   SSH_PORT  SSH port of the stick (default 22, 2222 for scripts/run-vm.sh)
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 1 || $# -eq 2 ]] || die "usage: $0 <host> [private key file]"
host=$1
key=${2:-$HOME/.ssh/lanos_ed25519}
repo=$(cd "$(dirname "$0")/.." && pwd)

[[ -f $key ]] || die "no private key at $key"

ssh_opts=(-i "$key" -p "${SSH_PORT:-22}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new)
export NIX_SSHOPTS="${ssh_opts[*]}"

echo "Building the system..."
system=$(nix build --no-link --print-out-paths "$repo#nixosConfigurations.lanbox.config.system.build.toplevel")

echo "Removing systems from $host that no longer run..."
# The stick keeps only the running system, so older systems do not take space from
# the games. A system replaced by an earlier update stays in the store until it is no
# longer running, so it is removed here rather than right after that update.
ssh "${ssh_opts[@]}" "player@$host" "sudo nix-store --gc 2>&1 | tail -1"

echo "Copying $system to $host..."
# The paths built here carry no signature, which the stick's store only accepts from a
# trusted user. The player is none, so run the store daemon as root, which the player
# may via sudo.
nix copy --no-check-sigs --to "ssh-ng://player@$host?remote-program=sudo nix-daemon" "$system"

echo "Making it the boot default..."
ssh "${ssh_opts[@]}" "player@$host" bash -s -- "$system" << 'EOF'
set -euo pipefail
profile=/nix/var/nix/profiles/system
sudo nix-env --profile "$profile" --set "$1"
sudo nix-env --profile "$profile" --delete-generations old
sudo "$1/bin/switch-to-configuration" boot
EOF

echo "Done. The update takes effect when $host boots next."
