# Per-stick identity. All sticks are clones of one image, so anything that must differ
# between machines on the LAN is derived from /etc/machine-id, which the image does not
# ship and systemd therefore generates on the first boot of each stick.
{
  # Unset, so the static hostname below is not generated from this option.
  networking.hostName = "";
  # systemd replaces every "?" with a hex digit hashed from /etc/machine-id.
  environment.etc.hostname.text = ''
    lanbox-??????
  '';
}
