# LANOS

A bootable, git-managed Linux system for our LAN parties. It runs from a USB SSD stick
on the guests' own PCs. Players boot from the stick, pick their graphics driver and
play; known fixes live in this repo so they never have to be rediscovered.

The system is NixOS, declared in this flake and pinned to nixpkgs `nixos-26.05`.

**Status:** phase 1, bootable base image. No games or launcher yet.

## Build

Requires Nix with flakes on x86_64 Linux, with KVM (the image is installed inside a
VM during the build).

```sh
nix build .#image -o result-image
```

This produces `result-image/lanos.img` (raw disk image) and `result-image/lanos.bmap`
(block map for fast flashing).

## Test in a VM

```sh
scripts/run-vm.sh
```

Boots the image in QEMU with UEFI, attached as a 64 GB USB stick. Writes go to an
overlay in `vm/`; delete that directory to test a fresh first boot again.

## Flash a stick

```sh
scripts/flash.sh /dev/sdX
```

The script only writes to unmounted, USB-attached disks, asks for confirmation and
uses `sudo` for the write itself. Use a USB 3 SSD stick, 64 GB at the very least,
128 GB or more for the full game set.

Always create sticks by flashing the image. Never copy a stick that has already been
booted: it would carry over that stick's identity (see [First boot](#first-boot)).

## Preparing a guest PC

In the firmware setup (BIOS):

- Disable **Secure Boot**. The stick's boot loader is not signed, and we do not enroll
  keys on other people's machines.
- Make sure **USB boot** is allowed and the PC boots in UEFI mode.

Then pick the stick from the firmware's one-time boot menu (often F12, F11, F8 or Esc,
depending on the vendor). The stick never changes the PC's boot order.

## Boot menu

| Entry | Use it for |
|---|---|
| LANOS - AMD / Intel graphics (default) | AMD and Intel GPUs |
| LANOS - Nvidia RTX and GTX 16xx or newer | Nvidia Turing and newer, current driver with open kernel modules |
| LANOS - Nvidia GTX 750, 900 and 1000 series | Nvidia Maxwell, Pascal and Volta, legacy 580 driver |

Older Nvidia cards (Kepler: most of the GTX 600 and 700 series, and earlier) are not
supported by the proprietary drivers. The default entry may still work with the
open-source nouveau driver, but expect poor performance.

## First boot

On the first boot of a freshly flashed stick:

- The partitions grow to fill the stick: root is extended and `/home` and `/games`
  are created in the free space.
- systemd generates a new `/etc/machine-id`, and the hostname is set to
  `lanbox-<first 6 characters of the machine id>`. This keeps sticks distinguishable on
  the LAN.

The desktop logs in automatically as user `player`, which has no password and may use
`sudo` without one.

## Disk layout

| Partition | Filesystem | Size |
|---|---|---|
| ESP (`/boot`) | vfat | 1 GiB |
| root (`/`) | ext4 | 24 to 40 GiB |
| `/home` | ext4 | 2 to 8 GiB |
| `/games` | btrfs, zstd compression | the rest, at least 8 GiB |

The image only contains ESP and root; the rest is created on first boot (see
`hosts/lanbox/image.nix`).

## Checking a stick

On the stick, open a terminal (Konsole) and run:

```sh
glxinfo -B            # 64-bit OpenGL: renderer should be the real GPU, not llvmpipe
glxinfo32 -B          # 32-bit OpenGL
vulkaninfo --summary  # 64-bit Vulkan
vulkaninfo32 --summary
hostnamectl           # unique lanbox-xxxxxx hostname
lsblk                 # partitions grown to fill the stick
nmcli device          # wired network connected
```

## Updating a stick

From a checkout of this repo on the stick:

```sh
sudo nixos-rebuild switch --flake .#lanbox
```

## Repository layout

```
flake.nix               Pinned nixpkgs, system and image outputs
hosts/lanbox/           Base system, hardware support, disk layout and image build
modules/                graphics (boot menu GPU entries), network, session, firstboot
scripts/                flash.sh, run-vm.sh
```
