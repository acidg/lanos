# Install games on a stick from the master, for sticks the organizer wants to prepare
# without the player pulling them. Copies only what the stick does not have yet.
#
# Usage: lanos-push <stick> <game id>...
#   LANOS_LIBRARY    library store (set on a LANOS master)
#   LANOS_INDEX_DIR  where the published games.json is (default: $LANOS_LIBRARY/index)
#   LANOS_SSH_KEY    private key for the sticks (default: ~/.ssh/lanos_ed25519)

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -ge 2 ]] || die "usage: lanos-push <stick> <game id>..."
host=$1
shift
library=${LANOS_LIBRARY:?set LANOS_LIBRARY to the library store}
index="${LANOS_INDEX_DIR:-$library/index}/games.json"
key=${LANOS_SSH_KEY:-$HOME/.ssh/lanos_ed25519}
[[ -f $index ]] || die "nothing published yet, run lanos-publish first"

ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new)
export NIX_SSHOPTS="${ssh_opts[*]}"

for id in "$@"; do
  path=$(jq -r --arg id "$id" '.games[$id].path // empty' "$index")
  [[ -n $path ]] || die "the library has no game '$id'"
  echo "Pushing $id..."
  # The stick accepts the paths because the library signed them.
  nix copy --from "$library" --to "ssh-ng://player@$host" "$path"
  ssh "${ssh_opts[@]}" "player@$host" bash -s -- "$id" "$path" <<'EOF'
lanbox install "$1" "$2"
EOF
done
