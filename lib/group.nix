# Everything a LAN group needs from its own flake: the stick system pointed at the
# group's library, the game packages, and the library index the master publishes.
{ nixpkgs, lanos }:
{
  # The group flake itself; its revision is published with the library.
  self,
  name,
  # Where sticks find the library: { url = "http://master.local:5000"; publicKey = "..."; }
  library,
  # Game recipes: files of the form `{ lanos, ... }: lanos.mkGame { ... }`, called like
  # nixpkgs packages.
  games,
  # Extra NixOS modules for the group's sticks.
  modules ? [ ],
}:
let
  system = "x86_64-linux";

  stick = nixpkgs.lib.nixosSystem {
    modules = [
      lanos.nixosModules.stick
      {
        lanos.library = library;
        system.configurationRevision = self.rev or self.dirtyRev or null;
      }
    ]
    ++ modules;
  };

  # The stick's own package set, so games share store paths with the system.
  pkgs = stick.pkgs;
  gameLib = lanos.lib.forPkgs pkgs;

  gamePackages = builtins.listToAttrs (
    map (
      recipe:
      let
        package = pkgs.callPackage recipe { lanos = gameLib; };
      in
      nixpkgs.lib.nameValuePair package.lanos.id package
    ) games
  );

  # The index sticks read from the library. It references every package and the stick
  # system, so building it puts all of them into the library store.
  index = pkgs.writeTextFile {
    name = "lanos-library-${name}";
    destination = "/games.json";
    text = builtins.toJSON {
      format = 1;
      group = name;
      revision = self.rev or self.dirtyRev or "unknown";
      system = stick.config.system.build.toplevel;
      games = builtins.mapAttrs (_: package: {
        inherit (package.lanos) name version;
        path = package;
      }) gamePackages;
    };
  };

  # What lanos-import needs to know about each game's files.
  importInfo = builtins.mapAttrs (
    _: package:
    let
      files = package.lanos.files;
    in
    if files == null then
      null
    else
      {
        inherit (files) name;
        inherit (files.lanosImport) source include exclude;
        path = files.outPath;
      }
  ) gamePackages;

  app = program: {
    type = "app";
    program = "${lanos.packages.${system}.lanos-tools}/bin/${program}";
  };
in
{
  nixosConfigurations.lanbox = stick;

  packages.${system} = {
    image = stick.config.system.build.image;
    library = index;
  }
  // nixpkgs.lib.mapAttrs' (id: nixpkgs.lib.nameValuePair "game-${id}") gamePackages;

  apps.${system} = {
    import = app "lanos-import";
    publish = app "lanos-publish";
    push = app "lanos-push";
  };

  lanos.games = importInfo;
}
