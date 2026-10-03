# Build every game of the group flake and the stick system into the library store, sign
# them and publish the index sticks read. Each publish is a generation of the library
# profile, which keeps it from being garbage collected; older generations can be
# deleted with `nix profile wipe-history --profile $LANOS_LIBRARY/nix/var/nix/profiles/library`.
#
# Usage: lanos-publish
#   LANOS_LIBRARY      library store (set on a LANOS master)
#   LANOS_SIGNING_KEY  secret key file of the library (set on a LANOS master)
#   LANOS_INDEX_DIR    where the served games.json goes (set on a LANOS master)
#   LANOS_FLAKE        group flake (default: the current directory)

library=${LANOS_LIBRARY:?set LANOS_LIBRARY to the library store}
key=${LANOS_SIGNING_KEY:?set LANOS_SIGNING_KEY to the library signing key}
index_dir=${LANOS_INDEX_DIR:?set LANOS_INDEX_DIR to the directory games.json is served from}
flake=${LANOS_FLAKE:-.}
profile="$library/nix/var/nix/profiles/library"

echo "Building the library..."
mkdir -p "$(dirname "$profile")"
nix build --store "$library" --profile "$profile" "$flake#library"
# The profile names the logical /nix/store path; on disk it lives below $library.
index=$(readlink -f "$profile")

echo "Signing..."
nix store sign --store "$library" --key-file "$key" --recursive "$index"

# Write and rename, so a stick never reads a half-written index.
cp "$library$index/games.json" "$index_dir/games.json.new"
mv "$index_dir/games.json.new" "$index_dir/games.json"
echo "Published:"
jq -r '.games | to_entries[] | "  \(.key) \(.value.version)"' "$index_dir/games.json"
