# Disk layout of the stick and the raw image build.
#
# The stick has an ESP and one btrfs partition with a subvolume each for /, /nix, /home
# and /games. Sharing one filesystem means there are no fixed partition sizes to
# outgrow, and files can be reflinked between /nix/store and /games: game packages live
# in the store, and the writable per-stick copies in /games/instances share their
# blocks until they are changed.
#
# The image only holds the ESP and a btrfs partition just big enough for the system, so
# it stays small to build and flash. On first boot, systemd-repart in the initrd grows
# that partition to the end of the stick and systemd-growfs grows the filesystem, so one
# image fits sticks of any size.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Fixed GPT partition UUIDs. All sticks are clones of one image, so fixed IDs are
  # fine, and being LANOS-specific they never match a guest PC's internal disks
  # (unlike labels such as "nixos" or "ESP").
  partUuid = {
    esp = "849D0E6E-2E6D-4351-92FE-1DB24945C61E";
    lanos = "958A0989-51EA-4883-A800-554CA55AB1B8";
  };

  byPartUuid = name: "/dev/disk/by-partuuid/${lib.toLower partUuid.${name}}";

  subvolumes = {
    "/" = "@root";
    "/nix" = "@nix";
    "/home" = "@home";
    "/games" = "@games";
  };
  btrfsOptions = [
    "noatime"
    "compress=zstd"
  ];

  subvolumeMount = mountPoint: {
    device = byPartUuid "lanos";
    fsType = "btrfs";
    options = [ "subvol=${subvolumes.${mountPoint}}" ] ++ btrfsOptions;
  };
in
{
  # The desktop must not offer the running system's stick for safe removal, where a
  # player could unmount it by accident. Other USB drives stay removable.
  services.udev.extraRules = lib.concatMapStrings (uuid: ''
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${lib.toLower uuid}", ENV{UDISKS_SYSTEM}="1", ENV{UDISKS_IGNORE}="1"
  '') (lib.attrValues partUuid);

  # Growing the filesystem through any of its mounts grows it for all subvolumes.
  fileSystems."/" = subvolumeMount "/" // {
    autoResize = true;
  };
  fileSystems."/nix" = subvolumeMount "/nix";
  fileSystems."/home" = subvolumeMount "/home" // {
    # User homes are created during activation, which runs in the initrd.
    neededForBoot = true;
  };
  fileSystems."/games" = subvolumeMount "/games";
  fileSystems."/boot" = {
    device = byPartUuid "esp";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # The launcher installs and updates games as the player.
  systemd.tmpfiles.settings."10-games"."/games".d = {
    user = "player";
    group = "users";
    mode = "0755";
  };

  boot.initrd.systemd.repart.enable = true;
  # A freshly flashed stick still has the backup GPT header where the image ended, so
  # the partition table hides the rest of the stick from systemd-repart.
  boot.initrd.systemd.services.lanos-relocate-gpt = {
    description = "Move the backup GPT header to the end of the stick";
    unitConfig.DefaultDependencies = false;
    after = [ "sysroot.mount" ];
    before = [ "systemd-repart.service" ];
    requiredBy = [ "systemd-repart.service" ];
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.gptfdisk
    ];
    script = ''
      part=$(basename "$(readlink -f ${byPartUuid "lanos"})")
      disk=/dev/$(basename "$(readlink -f "/sys/class/block/$part/..")")
      table=$(sgdisk -p "$disk")
      sectors=$(echo "$table" | sed -n 's/^Disk .*: \([0-9]*\) sectors.*/\1/p')
      last_usable=$(echo "$table" | sed -n 's/.*last usable sector is \([0-9]*\).*/\1/p')
      # The backup header and partition array take the last 33 sectors.
      if ((last_usable < sectors - 34)); then
        sgdisk -e "$disk"
      fi
    '';
  };
  # systemd-repart matches the btrfs partition by its type. Without a size limit it
  # grows the partition over all free space behind it.
  systemd.repart.partitions."10-lanos".Type = "linux-generic";

  system.build.image = import ./disk-image.nix {
    inherit
      config
      lib
      pkgs
      partUuid
      subvolumes
      btrfsOptions
      ;
    label = "lanos";
  };
}
