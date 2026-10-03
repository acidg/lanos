{
  description = "Games of our LAN group";

  inputs.lanos.url = "github:acidg/lanos";

  outputs =
    { self, lanos }:
    lanos.lib.mkGroup {
      inherit self;
      name = "my-group";
      library = {
        # The master's hostname on the party LAN, see the LANOS README.
        url = "http://my-master.local:5000";
        # Output of `nix key convert-secret-to-public` for the library's signing key.
        publicKey = "my-group-1:replace-me";
      };
      games = [
        # ./games/some-game
      ];
    };
}
