# Graphics drivers. Mesa (AMD, Intel, nouveau) is the base system and the default boot
# entry. The proprietary Nvidia drivers cannot be selected reliably at boot, so each one
# gets its own boot menu entry via a specialisation.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  defaultLabel = "AMD / Intel graphics";

  nvidiaProfiles = {
    nvidia = {
      label = "Nvidia RTX and GTX 16xx or newer";
      package = kernelPackages: kernelPackages.nvidiaPackages.production;
      # The open kernel modules support Turing (GTX 16xx, RTX 20xx) and newer only.
      open = true;
    };
    nvidia-legacy = {
      label = "Nvidia GTX 750, 900 and 1000 series";
      # 580 is the last branch supporting Maxwell, Pascal and Volta.
      package = kernelPackages: kernelPackages.nvidiaPackages.legacy_580;
      open = false;
    };
  };

  distroName = config.system.nixos.distroName;
  entriesDir = "${config.boot.loader.efi.efiSysMountPoint}/loader/entries";

  # Glob patterns are matched against loader entry file names, e.g.
  # nixos-generation-3-specialisation-nvidia.conf.
  titleCases = lib.concatStrings (
    lib.mapAttrsToList (name: profile: ''
      *-specialisation-${name}.conf) label=${lib.escapeShellArg profile.label} ;;
    '') nvidiaProfiles
  );

  # Every game is 32-bit, so 32-bit GL and Vulkan must work as well.
  glxinfo32 = pkgs.writeShellScriptBin "glxinfo32" ''
    exec ${pkgs.pkgsi686Linux.mesa-demos}/bin/glxinfo "$@"
  '';
  vulkaninfo32 = pkgs.writeShellScriptBin "vulkaninfo32" ''
    exec ${pkgs.pkgsi686Linux.vulkan-tools}/bin/vulkaninfo "$@"
  '';
in
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.systemPackages = [
    pkgs.mesa-demos
    pkgs.vulkan-tools
    glxinfo32
    vulkaninfo32
  ];

  # Default entry first, then the Nvidia entries in attribute order. Specialisations
  # inherit this value, hence the lower priority.
  boot.loader.systemd-boot.sortKey = lib.mkDefault "lanos";

  # The boot loader titles entries "<distro> (<specialisation>)"; replace that with
  # labels a non-technical player recognizes.
  boot.loader.systemd-boot.extraInstallCommands = ''
    for entry in ${entriesDir}/nixos-generation-*.conf; do
      case "$(basename "$entry")" in
        ${titleCases}
        *) label=${lib.escapeShellArg defaultLabel} ;;
      esac
      ${pkgs.gnused}/bin/sed -i "s|^title .*|title ${distroName} - $label|" "$entry"
    done
  '';

  specialisation = lib.mapAttrs (name: profile: {
    configuration =
      { config, ... }:
      {
        system.nixos.tags = [ name ];
        boot.loader.systemd-boot.sortKey = "lanos-${name}";
        # The nvidia module also blacklists nouveau.
        services.xserver.videoDrivers = [ "nvidia" ];
        hardware.nvidia = {
          package = profile.package config.boot.kernelPackages;
          inherit (profile) open;
          modesetting.enable = true;
        };
      };
  }) nvidiaProfiles;
}
