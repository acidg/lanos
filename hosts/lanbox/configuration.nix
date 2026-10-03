{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./image.nix
    ../../modules/clock.nix
    ../../modules/graphics.nix
    ../../modules/network.nix
    ../../modules/session.nix
    ../../modules/firstboot.nix
    ../../modules/ssh.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  # Needed for the full firmware set and the proprietary Nvidia drivers.
  nixpkgs.config.allowUnfree = true;

  system.nixos.distroName = "LANOS";

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  # Players pick their graphics driver here, so leave them time to read the menu.
  boot.loader.timeout = 10;
  # Never touch the boot order of a guest PC; the stick boots via the removable-media
  # fallback path EFI/BOOT/BOOTX64.EFI, which bootctl installs as well.
  boot.loader.efi.canTouchEfiVariables = false;
  boot.initrd.systemd.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";
  # German by default, Alt+Shift switches to US.
  services.xserver.xkb = {
    layout = "de,us";
    options = "grp:alt_shift_toggle";
  };
  console.useXkbConfig = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    git
    htop
    pciutils
    usbutils
  ];

  system.stateVersion = "26.05";
}
