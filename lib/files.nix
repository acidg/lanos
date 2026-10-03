# Game files copied from an install the group owns. They are never downloaded and never
# in git: the recipe only pins their hash, and lanos-import adds them to the library
# store. Any other set of files has a different hash, so a package can only be built
# with exactly the files its config was written for.
{ pkgs }:
{
  name,
  hash,
  # Where the files come from, shown to whoever has to import them.
  source,
  # Top-level paths to copy from the install; empty copies everything.
  include ? [ ],
  # rsync patterns to leave out, e.g. per-user settings that would change the hash.
  exclude ? [ ],
}:
pkgs.requireFile {
  inherit name hash;
  hashMode = "recursive";
  message = ''
    The game files ${name} are not in the library store. Import them from
    ${source} with:
      lanos-import <game id> <path to the install>
  '';
}
// {
  lanosImport = { inherit source include exclude; };
}
