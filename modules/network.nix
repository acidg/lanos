{
  # Wired DHCP works out of the box; players can add WiFi from the desktop.
  networking.networkmanager.enable = true;
  networking.modemmanager.enable = false;
  # LAN game discovery relies on broadcasts and games use many dynamic UDP ports.
  networking.firewall.enable = false;
}
