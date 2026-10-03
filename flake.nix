{
  description = "LANOS: bootable LAN party system on a USB SSD stick";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # A stick without a group library, for working on the system itself. Groups build
      # theirs with lib.mkGroup.
      lanbox = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.stick
          # Lets `nixos-version --configuration-revision` tell which commit a stick runs.
          { system.configurationRevision = self.rev or self.dirtyRev or null; }
        ];
      };
      pkgs = lanbox.pkgs;
    in
    {
      lib = import ./lib {
        inherit nixpkgs;
        lanos = self;
      };

      nixosModules = {
        stick = ./hosts/lanbox/configuration.nix;
        master = ./modules/master.nix;
      };

      nixosConfigurations.lanbox = lanbox;

      packages.${system} = {
        image = lanbox.config.system.build.image;
        lanbox = pkgs.callPackage ./pkgs/lanbox.nix { };
        lanos-tools = pkgs.callPackage ./pkgs/lanos-tools.nix { };
        default = self.packages.${system}.image;
      };

      templates.group = {
        path = ./templates/group;
        description = "A LAN group's games and library settings";
      };
    };
}
