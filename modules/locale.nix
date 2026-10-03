# Language and keyboard. The system defaults apply to the console, the login manager
# and the first login, where each player picks their own; the choice lives in /home
# with the rest of their data.
{ config, pkgs, ... }:
let
  xkb = config.services.xserver.xkb;

  chooser = pkgs.writeShellApplication {
    name = "lanos-locale";
    runtimeInputs = with pkgs.kdePackages; [
      kconfig
      kdialog
      qttools
    ];
    runtimeEnv = {
      DEFAULT_LAYOUTS = xkb.layout;
      XKB_OPTIONS = xkb.options;
    };
    text = builtins.readFile ./locale-chooser.sh;
  };

  launcher = pkgs.makeDesktopItem {
    name = "lanos-locale";
    desktopName = "Language and Keyboard";
    icon = "preferences-desktop-locale";
    exec = "${chooser}/bin/lanos-locale";
    categories = [ "Settings" ];
    extraConfig."Name[de]" = "Sprache und Tastatur";
  };
in
{
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocales = [ "de_DE.UTF-8/UTF-8" ];
  # German by default, Alt+Shift switches to US.
  services.xserver.xkb = {
    layout = "de,us";
    options = "grp:alt_shift_toggle";
  };
  console.useXkbConfig = true;

  environment.systemPackages = [
    launcher
    (pkgs.makeAutostartItem {
      name = "lanos-locale";
      package = launcher;
      appendExtraArgs = [ "--first-login" ];
    })
  ];
}
