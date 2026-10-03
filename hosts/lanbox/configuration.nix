{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./image.nix
    ../../modules/clock.nix
    ../../modules/graphics.nix
    ../../modules/locale.nix
    ../../modules/network.nix
    ../../modules/session.nix
    ../../modules/firstboot.nix
    ../../modules/games.nix
    ../../modules/ssh.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  # Needed for the full firmware set and the proprietary Nvidia drivers.
  nixpkgs.config.allowUnfree = true;

  system.nixos.distroName = "LANOS";

  boot.loader.systemd-boot.enable = true;
  # One system per stick, so older systems do not take space from the games. A bad
  # update is reverted by pushing the previous one again.
  boot.loader.systemd-boot.configurationLimit = 1;
  # Players pick their graphics driver here, so leave them time to read the menu.
  boot.loader.timeout = 10;
  # Never touch the boot order of a guest PC; the stick boots via the removable-media
  # fallback path EFI/BOOT/BOOTX64.EFI, which bootctl installs as well.
  boot.loader.efi.canTouchEfiVariables = false;
  boot.initrd.systemd.enable = true;

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
