# The master's tools for filling the library and handing games to sticks.
{
  lib,
  writeShellApplication,
  symlinkJoin,
  coreutils,
  jq,
  nix,
  openssh,
  rsync,
}:
let
  tool =
    name:
    writeShellApplication {
      inherit name;
      runtimeInputs = [
        coreutils
        jq
        nix
        openssh
        rsync
      ];
      text = builtins.readFile ../scripts/${name}.sh;
    };
in
symlinkJoin {
  name = "lanos-tools";
  paths = map tool [
    "lanos-import"
    "lanos-publish"
    "lanos-push"
  ];
  meta.license = lib.licenses.mit;
}
