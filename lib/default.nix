{ nixpkgs, lanos }:
{
  # Functions for game recipes, bound to the package set the games are built with.
  forPkgs = pkgs: {
    mkGame = import ./game.nix { inherit (nixpkgs) lib; inherit pkgs; };
    gameFiles = import ./files.nix { inherit pkgs; };
  };

  mkGroup = import ./group.nix { inherit nixpkgs lanos; };
}
