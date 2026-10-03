# Per-stick identity. All sticks are clones of one image, so anything that must differ
# between machines on the LAN is derived from /etc/machine-id, which the image does not
# ship and systemd therefore generates on the first boot of each stick.
{ pkgs, ... }:
{
  # Leave the static hostname unmanaged so it can be written at runtime.
  networking.hostName = "";

  systemd.services.lanbox-hostname = {
    description = "Set a unique per-stick hostname";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-pre.target" ];
    before = [ "network-pre.target" ];
    unitConfig.ConditionPathExists = "!/etc/hostname";
    serviceConfig.Type = "oneshot";
    script = ''
      name="lanbox-$(${pkgs.coreutils}/bin/head -c 6 /etc/machine-id)"
      echo "$name" > /etc/hostname
      echo "$name" > /proc/sys/kernel/hostname
    '';
  };
}
