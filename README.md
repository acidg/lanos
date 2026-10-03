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
overlay in `vm/`; delete that directory to test a fresh first boot again. The VM's SSH
port is forwarded to `localhost:2222`; see the script header for more options.

## SSH key

The image contains no SSH key. The PC that creates the sticks holds one key, which is
put on every stick when it is flashed, so the organizer can reach all sticks on the
LAN to debug and push fixes. Create it once:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/lanos_ed25519 -C lanos-master
```

## Flash a stick

```sh
scripts/flash.sh /dev/sdX [public key file]
```

The script only writes to unmounted, USB-attached disks, asks for confirmation and
uses `sudo` for the write itself. Afterwards it adds the SSH public key
(`~/.ssh/lanos_ed25519.pub` by default); without a key the stick has no remote access.
To add or replace the key on an already flashed stick, run
`scripts/add-ssh-key.sh /dev/sdX [public key file]`.

Use a USB 3 SSD stick, 64 GB at the very least, 128 GB or more for the full game set.

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
- systemd generates a new `/etc/machine-id`, and the hostname becomes `lanbox-` plus 6
  hex characters derived from it. This keeps sticks distinguishable on the LAN.

The desktop logs in automatically as user `player`, which has no password and may use
`sudo` without one. On the first login it asks for the language (Deutsch or English)
and the keyboard layout (German or US, Alt+Shift switches to the other), then restarts
the session once. To change them later, run "Language and Keyboard" from the
application menu.

## Remote access

Each stick runs an SSH server that only accepts the key added at flashing time, for
user `player` (no passwords, no root login). Each stick generates its own host key on
first boot.

```sh
ssh -i ~/.ssh/lanos_ed25519 player@lanbox-xxxxxx
```

Use the IP address if the LAN has no DNS for the hostnames.

## Disk layout

| Partition | Filesystem | Size |
|---|---|---|
| ESP (`/boot`) | vfat | 1 GiB |
| root (`/`) | ext4 | 24 to 40 GiB |
| `/home` | ext4 | 2 to 8 GiB |
| `/games` | btrfs, zstd compression | the rest, at least 8 GiB |

The image only contains ESP and root; the rest is created on first boot (see
`hosts/lanbox/image.nix`).

All sticks share the same partition IDs. Boot a PC with only one LANOS stick plugged
in, otherwise it may mount partitions of the other stick.

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

A stick that has booted once is updated over the network instead of being flashed
again, which keeps the player's data:

```sh
scripts/update-stick.sh lanbox-xxxxxx
```

This builds the system from the checkout, copies only what the stick does not have yet
and makes it the boot default; it takes effect on the next boot. A stick holds a single
system, so to revert, run the script again from the older checkout.

An update that leaves the stick unable to boot or reach the network can only be fixed
by flashing it again, which erases the player's data.

## Repository layout

```
flake.nix               Pinned nixpkgs, system and image outputs
hosts/lanbox/           Base system, hardware support, disk layout and image build
modules/                clock, graphics (boot menu GPU entries), locale (language and
                        keyboard chooser), network, session, firstboot, ssh
scripts/                flash.sh, add-ssh-key.sh, update-stick.sh, run-vm.sh
```

## License

MIT, see [LICENSE](LICENSE). The license covers this repository only; the games
themselves are not part of it, and every player must own them.
