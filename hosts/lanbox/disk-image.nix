# Raw image of the stick: GPT with the ESP and the btrfs partition, holding the system
# and the boot loader exactly as an installation would.
#
# nixpkgs' make-disk-image only partitions ext4 images, and its systemd-repart image
# builder copies files but cannot run the boot loader installation. So this works like
# make-disk-image: the btrfs filesystem with its subvolumes is created from a staged
# root outside the VM, which is fast, and a VM only formats the ESP and runs the
# system's own boot loader installation on the mounted image.
{
  config,
  lib,
  pkgs,
  # GPT partition UUIDs, attributes esp and lanos.
  partUuid,
  # btrfs filesystem and GPT partition label.
  label,
  # Subvolume name of each mount point; "/" must be one of them.
  subvolumes,
  btrfsOptions,
}:
let
  toplevel = config.system.build.toplevel;
  closureInfo = pkgs.closureInfo { rootPaths = [ toplevel ]; };

  rootSubvolume = subvolumes."/";
  # Mounted after "/", which they are directly below.
  otherSubvolumes = lib.removeAttrs subvolumes [ "/" ];

  espSizeMiB = 1024;
  # The filesystem is created at its minimum size. The headroom lets the VM write the
  # activation's files and the first boot mount it before it is grown.
  headroomMiB = 1024;
  mountOptions = lib.concatStringsSep "," btrfsOptions;
in
pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand "lanos-image"
    {
      nativeBuildInputs = with pkgs; [
        bmaptool
        btrfs-progs
        config.system.build.nixos-install
        dosfstools
        nix
        nixos-enter
        util-linux
      ];
      memSize = 4096;

      preVM = ''
        mkdir $out
        export HOME=$TMPDIR

        # nixos-install copies the system from a Nix database that knows its closure.
        export NIX_STATE_DIR=$TMPDIR/state
        nix-store --load-db < ${closureInfo}/registration

        # One directory per subvolume, with the mount points in the root subvolume. Nix
        # refuses to install into a store below a directory others cannot read.
        chmod 755 $TMPDIR
        tree=$TMPDIR/tree
        mkdir -p $tree/${rootSubvolume}
        nixos-install --root $tree/${rootSubvolume} --no-bootloader --no-root-passwd \
          --no-channel-copy --system ${toplevel} --substituters ""
        ${lib.concatMapAttrsStringSep "\n" (mountPoint: subvolume: ''
          mkdir -p $tree/${rootSubvolume}${mountPoint}
          mv $tree/${rootSubvolume}${mountPoint} $tree/${subvolume}
          mkdir $tree/${rootSubvolume}${mountPoint}
        '') otherSubvolumes}
        mkdir $tree/${rootSubvolume}/boot

        # In the user namespace the build user is root, so the files are owned by root.
        unshare --map-root-user mkfs.btrfs --label ${label} --rootdir $tree \
          ${lib.concatMapStringsSep " " (subvolume: "--subvol ${subvolume}") (lib.attrValues subvolumes)} \
          --compress zstd --shrink lanos.btrfs
        # The staged copy of the system is as big as the image; free the space early.
        chmod -R u+w $tree
        rm -rf $tree

        mib=$((1024 * 1024))
        espStart=1
        lanosStart=$((espStart + ${toString espSizeMiB}))
        lanosSize=$((($(stat -c %s lanos.btrfs) + mib - 1) / mib + ${toString headroomMiB}))
        diskImage=lanos.img
        # 1 MiB at the end for the backup GPT.
        truncate -s $(((lanosStart + lanosSize + 1) * mib)) $diskImage
        sfdisk --quiet $diskImage << EOF
        label: gpt
        start=''${espStart}MiB, size=${toString espSizeMiB}MiB, type=uefi, uuid=${partUuid.esp}, name=ESP
        start=''${lanosStart}MiB, size=''${lanosSize}MiB, type=linux, uuid=${partUuid.lanos}, name=${label}
        EOF
        dd if=lanos.btrfs of=$diskImage bs=1M seek=$lanosStart conv=notrunc,sparse status=none
        rm lanos.btrfs
      '';

      # The block map lets bmaptool skip the unused parts of the image when flashing.
      postVM = ''
        mv $diskImage $out/lanos.img
        bmaptool create $out/lanos.img -o $out/lanos.bmap
      '';
    }
    ''
      mkfs.vfat -n ESP /dev/vda1
      # bootctl finds the ESP's disk through /dev/block, which only udev creates.
      mkdir /dev/block
      ln -s /dev/vda1 /dev/block/$(cat /sys/class/block/vda1/dev)

      mkdir /mnt
      mount -o subvol=${rootSubvolume},${mountOptions} /dev/vda2 /mnt
      btrfs filesystem resize max /mnt
      ${lib.concatMapAttrsStringSep "\n" (mountPoint: subvolume: ''
        mount -o subvol=${subvolume},${mountOptions} /dev/vda2 /mnt${mountPoint}
      '') otherSubvolumes}
      mount /dev/vda1 /mnt/boot

      # systemd-boot-builder.py lists the generations with nix-env, which writes below
      # $HOME; the default /homeless-shelter would end up in the image.
      export HOME=$TMPDIR
      NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt -- \
        /nix/var/nix/profiles/system/bin/switch-to-configuration boot

      umount -R /mnt
    ''
)
