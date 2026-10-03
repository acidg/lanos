{
  lib,
  python3Packages,
  kdePackages,
  nix,
}:
python3Packages.buildPythonApplication {
  pname = "lanbox";
  version = "0.1.0";
  pyproject = true;

  src = ../launcher;

  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.tomli-w ];
  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  # Appended, so the system's gamescope wrapper with its capabilities comes first.
  makeWrapperArgs = [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [
      kdePackages.kdialog
      kdePackages.libkscreen
      nix
    ])
  ];

  meta = {
    description = "Game launcher for LANOS sticks";
    license = lib.licenses.mit;
    mainProgram = "lanbox";
  };
}
