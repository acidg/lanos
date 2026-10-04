# Autologin into the shared player account. KDE Plasma is the interim desktop; whether
# it or a minimal compositor behaves better with gamescope and Nvidia is still open.
{ pkgs, ... }:
{
  users.users.player = {
    isNormalUser = true;
    description = "Player";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
  # The account has no password, so on-site fixes need sudo without one.
  security.sudo.wheelNeedsPassword = false;

  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = false;
  };
  # Every MB of the system is needed twice during an update, so drop what a gaming
  # session does not need. Konsole, Dolphin, Ark, Spectacle and the X11 session stay for on-site
  # troubleshooting.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    aurorae
    baloo-widgets
    dolphin-plugins
    elisa
    ffmpegthumbs
    gwenview
    kate
    khelpcenter
    krdp
    ktexteditor
    okular
    plasma-browser-integration
    plasma-workspace-wallpapers
    qrca
  ];
  programs.kde-pim.enable = false;
  services.orca.enable = false;
  services.speechd.enable = false;
  services.geoclue2.enable = false;
  # Must never offer firmware updates for a guest's PC.
  services.fwupd.enable = false;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.displayManager.autoLogin = {
    enable = true;
    user = "player";
  };
  # The player has no password, so logging out must start a new session instead of
  # stopping at a login screen nobody can get past.
  services.displayManager.sddm.autoLogin.relogin = true;

  # Players switch off and leave; a hung game or session process must not hold up the
  # shutdown for minutes.
  systemd.user.extraConfig = "DefaultTimeoutStopSec=10s";
  systemd.services."user@".serviceConfig.TimeoutStopSec = "10s";

  # Without a password a locked screen could never be unlocked again.
  environment.etc."xdg/kscreenlockerrc".text = ''
    [Daemon]
    Autolock=false
    LockOnResume=false
  '';
  # On a laptop without a mouse, players walk with the keys and aim with the touchpad
  # at the same time, which disable-while-typing would block.
  environment.etc."xdg/kcminputrc".text = ''
    [Libinput][Defaults][Touchpad]
    DisableWhileTyping=false
  '';
  # Handhelds such as the Steam Deck have no keyboard, e.g. for the Wi-Fi password. The
  # on-screen keyboard opens when a text field is tapped on a touchscreen; with a real
  # keyboard it stays hidden.
  environment.etc."xdg/kwinrc".text = ''
    [Wayland]
    InputMethod=/run/current-system/sw/share/applications/org.kde.plasma.keyboard.desktop
    VirtualKeyboardEnabled=true
  '';
  # A wallet would ask the player to create a password on the first Wi-Fi login, and
  # protects nothing on an unencrypted stick. Without it, Wi-Fi passwords are stored
  # by NetworkManager.
  environment.etc."xdg/kwalletrc".text = ''
    [Wallet]
    Enabled=false
  '';
  # Players share sticks and reboot often; restoring the previous session would reopen
  # whatever the last person left open, e.g. a debugging terminal.
  environment.etc."xdg/ksmserverrc".text = ''
    [General]
    loginMode=emptySession
  '';
}
