# Import a game's files into the library store, from an install the group owns. The
# recipe in the group flake says which files to take and pins their hash; the import
# fails if the files differ, e.g. after a game update, and prints the hash they have.
#
# Usage: lanos-import <game id> <install dir>
#   The install dir may be on another machine, e.g. a Steam Deck with SSH enabled:
#   deck@steamdeck:.local/share/Steam/steamapps/common/Half-Life
#   LANOS_LIBRARY  library store (set on a LANOS master)
#   LANOS_FLAKE    group flake (default: the current directory)

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || die "usage: lanos-import <game id> <install dir>"
id=$1
source_dir=${2%/}
library=${LANOS_LIBRARY:?set LANOS_LIBRARY to the library store}
flake=${LANOS_FLAKE:-.}

info=$(nix eval --json "$flake#lanos.games.$id") || die "no game '$id' in $flake"
[[ $info != null ]] || die "game '$id' has no files to import"
name=$(jq -r .name <<<"$info")
expected=$(jq -r .path <<<"$info")

filters=()
while read -r pattern; do
  filters+=("--exclude=$pattern")
done < <(jq -r '.exclude[]' <<<"$info")
while read -r path; do
  filters+=("--include=/$path/***")
done < <(jq -r '.include[]' <<<"$info")
if [[ $(jq '.include | length' <<<"$info") -gt 0 ]]; then
  filters+=("--exclude=*")
fi

# The store path's name must match the recipe, so the files are staged under it. The
# staging copy is kept if copying fails, so running the import again resumes it.
staging="$library/staging/$name"
mkdir -p "$staging"

echo "Copying files from $source_dir..."
# Without a timeout, a source machine that goes to sleep stalls the import forever.
rsync -a --delete --timeout=60 --info=progress2 "${filters[@]}" "$source_dir/" "$staging/"

echo "Adding them to the library..."
added=$(nix store add --store "$library" --name "$name" "$staging")
hash=$(nix hash path "$staging")
rm -rf "$staging"
if [[ $added != "$expected" ]]; then
  echo "The files differ from the recipe. If this is the version you want, set" >&2
  echo "  hash = \"$hash\";" >&2
  echo "in the recipe of $id and import again." >&2
  exit 1
fi
echo "Imported $added"
