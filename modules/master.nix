# The master: serves a LAN group's game library to its sticks. The library is a Nix
# store of its own, on a disk with room for the games, filled by lanos-import and
# lanos-publish; harmonia serves it as a binary cache, nginx adds the index in front.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lanos.master;
  indexDir = "/var/lib/lanos-library";
  harmoniaAddress = "127.0.0.1:${toString (cfg.port + 1)}";
in
{
  options.lanos.master = {
    enable = lib.mkEnableOption "serving a LANOS game library";
    store = lib.mkOption {
      type = lib.types.str;
      example = "/mnt/data/lanos";
      description = "Root of the library store, i.e. its store is <store>/nix/store.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = "The user who owns the library store and publishes to it.";
    };
    signingKeyFile = lib.mkOption {
      type = lib.types.str;
      example = "/mnt/data/lanos/keys/library.secret";
      description = "Secret key from `nix key generate-secret`, readable by user.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Port the library is served on; the next port is used internally.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ (pkgs.callPackage ../pkgs/lanos-tools.nix { }) ];
    environment.variables = {
      LANOS_LIBRARY = cfg.store;
      LANOS_SIGNING_KEY = cfg.signingKeyFile;
      LANOS_INDEX_DIR = indexDir;
    };

    systemd.tmpfiles.rules = [ "d ${indexDir} 0755 ${cfg.user} users -" ];

    services.harmonia.cache = {
      enable = true;
      settings = {
        bind = harmoniaAddress;
        real_nix_store = "${cfg.store}/nix/store";
        nix_db_path = "${cfg.store}/nix/var/nix/db/db.sqlite";
      };
    };
    # The library store belongs to its user, and its disk is usually not readable by
    # anyone else. Paths are signed when published, so harmonia needs no key.
    systemd.services.harmonia.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce cfg.user;
      Group = lib.mkForce "users";
      # SQLite keeps its lock files next to the database, even when only reading.
      ReadWritePaths = [ "${cfg.store}/nix/var/nix/db" ];
    };

    services.nginx = {
      enable = true;
      virtualHosts.lanos-library = {
        listen = [
          {
            addr = "0.0.0.0";
            inherit (cfg) port;
          }
        ];
        locations."= /games.json".root = indexDir;
        locations."/" = {
          proxyPass = "http://${harmoniaAddress}";
          # Game files are large; stream them instead of buffering them on disk.
          extraConfig = ''
            proxy_buffering off;
            proxy_read_timeout 1h;
          '';
        };
      };
    };
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Sticks find the master as <hostname>.local without DNS.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };
  };
}
