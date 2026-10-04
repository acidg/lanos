# Running games on the stick: the launcher, gamescope, and where games come from. Games
# are Nix store paths installed from the group's library, which the stick reaches over
# the LAN and trusts by its signing key.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lanos.library;
  lanbox = pkgs.callPackage ../pkgs/lanbox.nix { };

  # The terminal shows the download progress; the choice itself is a dialog.
  manageEntry = pkgs.makeDesktopItem {
    name = "lanbox-manage";
    desktopName = "Manage Games";
    icon = "system-software-install";
    exec = "lanbox manage";
    terminal = true;
    categories = [ "Game" ];
    extraConfig."Name[de]" = "Spiele verwalten";
  };
in
{
  options.lanos.library = {
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://master.local:5000";
      description = "The group's game library, served by a LANOS master.";
    };
    publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Key the library signs packages with; the stick accepts no other.";
    };
  };

  config = lib.mkMerge [
    {
      programs.gamescope.enable = true;
      # gamescope starts MangoHud's mangoapp for games with an fps counter; the frame
      # rate alone covers less of the game than MangoHud's default statistics.
      environment.systemPackages = [
        lanbox
        pkgs.mangohud
      ];
      environment.sessionVariables.MANGOHUD_CONFIG = "fps_only";

      # Installed packages link here, writable per-stick game state lives in instances.
      systemd.tmpfiles.rules = [
        "d /games/packages 0755 player users -"
        "d /games/instances 0755 player users -"
      ];
    }

    (lib.mkIf (cfg.url != null) {
      assertions = [
        {
          assertion = cfg.publicKey != null;
          message = "lanos.library.publicKey is required with lanos.library.url";
        }
      ];

      environment.systemPackages = [ manageEntry ];
      environment.sessionVariables.LANBOX_LIBRARY_URL = cfg.url;

      # Only the library: a party has no internet, and the library holds the complete
      # closure of the system and every game.
      nix.settings.substituters = lib.mkForce [ cfg.url ];
      nix.settings.trusted-public-keys = [ cfg.publicKey ];

      # Resolves the master's name.local without DNS on the party LAN.
      services.avahi = {
        enable = true;
        nssmdns4 = true;
      };
    })
  ];
}
