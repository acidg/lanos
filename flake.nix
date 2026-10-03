{
  description = "LANOS: bootable LAN party system on a USB SSD stick";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      lanbox = nixpkgs.lib.nixosSystem {
        modules = [
          ./hosts/lanbox/configuration.nix
          # Lets `nixos-version --configuration-revision` tell which commit a stick runs.
          { system.configurationRevision = self.rev or self.dirtyRev or null; }
        ];
      };
    in
    {
      nixosConfigurations.lanbox = lanbox;

      packages.${system} = {
        image = lanbox.config.system.build.image;
        default = self.packages.${system}.image;
      };
    };
}
