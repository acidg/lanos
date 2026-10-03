# Remote access, so the organizer can debug game launches and push fixes over the LAN.
#
# The image ships without any key. scripts/add-ssh-key.sh puts the organizer's public
# key onto a stick's ESP when it is flashed, so the repo and the image stay generic.
# Host keys are generated on first boot, so every stick has its own.
let
  espKeyFile = "/boot/lanos/authorized_keys";
  keyFile = "/run/lanos/authorized_keys";
in
{
  services.openssh = {
    enable = true;
    # The firewall is off, so everyone on the LAN can reach this port.
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "player" ];
    };
    authorizedKeysFiles = [ keyFile ];
  };

  # sshd reads authorized keys as the logged-in user, but the ESP is readable by root
  # only, so expose a world-readable copy.
  systemd.services.lanos-ssh-key = {
    description = "Provide the organizer SSH key from the ESP";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    unitConfig = {
      ConditionPathExists = espKeyFile;
      RequiresMountsFor = "/boot";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      install -D -m 644 ${espKeyFile} ${keyFile}
    '';
  };
}
