# Disk layout of the stick and the raw image build.
#
# The image only holds ESP and root, so it stays small to build and flash. On first
# boot, systemd-repart in the initrd grows root and creates /home and /games in the
# remaining space, so one image fits sticks of any size.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  # Fixed GPT partition UUIDs. All sticks are clones of one image, so fixed IDs are
  # fine, and being LANOS-specific they never match a guest PC's internal disks
  # (unlike labels such as "nixos" or "ESP").
  partUuid = {
    esp = "849D0E6E-2E6D-4351-92FE-1DB24945C61E";
    root = "958A0989-51EA-4883-A800-554CA55AB1B8";
    home = "5D4C2DBE-05F4-4E00-90E8-721F4407B740";
    games = "9C3517DC-511B-4E9E-AD73-CDD6DFBF40B3";
  };
  # Own GPT type for /games: root uses the generic Linux type and systemd-repart
  # matches existing partitions to definitions by type.
  gamesPartType = "8A3FAA84-D3AE-49CA-8FB5-25215B374126";

  byPartUuid = name: "/dev/disk/by-partuuid/${lib.toLower partUuid.${name}}";
in
{
  fileSystems."/" = {
    device = byPartUuid "root";
    fsType = "ext4";
    autoResize = true;
    options = [ "noatime" ];
  };
  fileSystems."/boot" = {
    device = byPartUuid "esp";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };
  fileSystems."/home" = {
    device = byPartUuid "home";
    fsType = "ext4";
    options = [ "noatime" ];
    # User homes are created during activation, which runs in the initrd.
    neededForBoot = true;
  };
  fileSystems."/games" = {
    device = byPartUuid "games";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd"
    ];
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
      part=$(basename "$(readlink -f ${byPartUuid "root"})")
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
  # systemd-repart formats new partitions with mkfs.<fstype> and then mounts them, so
  # the initrd needs the tools and kernel module of every filesystem it creates. ext4
  # is already there for root.
  boot.initrd.supportedFilesystems = [ "btrfs" ];
  # Sized for a 64 GB stick at minimum. Root holds about twice the system closure, so a
  # full nixpkgs update fits next to the running generation. On bigger sticks root and
  # /home stop at their maximum and /games takes the rest.
  systemd.repart.partitions = {
    "10-root" = {
      Type = "linux-generic";
      SizeMinBytes = "24G";
      SizeMaxBytes = "40G";
    };
    "20-home" = {
      Type = "home";
      UUID = partUuid.home;
      Label = "lanos-home";
      Format = "ext4";
      SizeMinBytes = "2G";
      SizeMaxBytes = "8G";
    };
    "30-games" = {
      Type = gamesPartType;
      UUID = partUuid.games;
      Label = "lanos-games";
      Format = "btrfs";
      SizeMinBytes = "8G";
      Weight = 10000;
    };
  };

  system.build.image = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit config lib pkgs;
    name = "lanos-image";
    baseName = "lanos";
    format = "raw";
    partitionTableType = "efi";
    # Room for kernel and initrd of every generation times every boot menu entry.
    bootSize = "1024M";
    label = "lanos-root";
    rootGPUID = partUuid.root;
    copyChannel = false;
    memSize = 4096;
    # The block map lets bmaptool skip the unused parts of the image when flashing.
    postVM = ''
      ${pkgs.gptfdisk}/bin/sgdisk --partition-guid=1:${partUuid.esp} $diskImage
      ${pkgs.bmaptool}/bin/bmaptool create $diskImage -o $out/lanos.bmap
    '';
  };
}
