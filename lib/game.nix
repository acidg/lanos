# A game package: a game.json for the launcher plus, through the store paths it names,
# everything the game needs (its files, engine or Proton). The options are type-checked
# here, so a broken recipe fails when the package is built instead of on a stick.
{ lib, pkgs }:
let
  inherit (lib) mkOption types;

  configType = types.submodule {
    options = {
      template = mkOption {
        type = types.path;
        description = "Template rendered before each launch, with $player_name, $width etc.";
      };
      target = mkOption {
        type = types.str;
        description = "File the template is rendered to, relative to root.";
      };
      root = mkOption {
        type = types.enum [
          "instance"
          "install"
          "home"
        ];
        default = "instance";
        description = ''
          The game's writable directory on the stick, its writable copy of install, or
          the player's home.
        '';
      };
    };
  };

  options = {
    id = mkOption {
      type = types.strMatching "[a-z0-9][a-z0-9-]*";
      description = "Short name, used for directories and the command line.";
    };
    name = mkOption { type = types.str; };
    version = mkOption {
      type = types.str;
      description = "Version of the package; change it with every change to the game.";
    };
    files = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "The game files from lanos.gameFiles, so the tools can import them.";
    };
    install = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        Game files the stick gets a writable copy of, as $install, for games that write
        into their own directory. The copy is renewed when the package changes.
      '';
    };
    command = mkOption {
      type = types.nonEmptyListOf types.str;
      description = "Command line, with template variables such as $width and $instance.";
    };
    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables, with the same template variables.";
    };
    directory = mkOption {
      type = types.str;
      default = "$instance";
      description = ''
        Working directory the game starts in; many games load their own libraries
        from there. Defaults to the game's writable directory on the stick.
      '';
    };
    gamescope = mkOption {
      type = types.bool;
      default = true;
    };
    resolution = mkOption {
      type = types.strMatching "native|[0-9]+x[0-9]+";
      default = "native";
      description = "Resolution the game renders at; gamescope scales it to the display.";
    };
    configs = mkOption {
      type = types.listOf configType;
      default = [ ];
    };
    configure = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Script run before each launch, with the template variables as LANBOX_*.";
    };
  };

  parseResolution =
    text:
    if text == "native" then
      null
    else
      let
        parts = lib.splitString "x" text;
      in
      {
        width = lib.toInt (builtins.elemAt parts 0);
        height = lib.toInt (builtins.elemAt parts 1);
      };
in
definition:
let
  game =
    (lib.evalModules {
      modules = [
        { inherit options; }
        definition
      ];
    }).config;

  usesInstall = builtins.any (config: config.root == "install") game.configs;

  manifest = assert lib.assertMsg (
    usesInstall -> game.install != null
  ) "${game.id}: configs with root \"install\" need the install option"; {
    # The game.json layout the launcher understands.
    format = 1;
    inherit (game)
      id
      name
      version
      command
      env
      directory
      gamescope
      ;
    resolution = parseResolution game.resolution;
    install = if game.install == null then null else "${game.install}";
    configs = map (config: {
      template = "${config.template}";
      inherit (config) target root;
    }) game.configs;
    configure = if game.configure == null then null else "${game.configure}";
  };
in
pkgs.writeTextFile {
  name = "${game.id}-${game.version}";
  destination = "/game.json";
  text = builtins.toJSON manifest;
  passthru.lanos = {
    inherit (game)
      id
      name
      version
      files
      ;
  };
}
