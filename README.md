# LANOS

A bootable, git-managed Linux system for our LAN parties. It runs from a USB SSD stick
on the guests' own PCs. Players boot from the stick, pick their graphics driver and
play; known fixes live in this repo so they never have to be rediscovered.

The system is NixOS, declared in this flake and pinned to nixpkgs `nixos-26.05`.

**Status:** phase 2, launcher and game libraries; Counter-Strike 1.6 is the first game.

LANOS contains no games. Each LAN group keeps its games in a flake of its own and
serves them from a library on the LAN; see [Games](#games).

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

A Steam Deck needs no firmware changes: with the stick plugged in, hold Volume Down
and press Power, then pick the stick from the boot manager.

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

- The btrfs partition and its filesystem grow to fill the stick.
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
| `lanos` | btrfs, zstd compression | the rest of the stick |

| btrfs subvolume | Mounted at |
|---|---|
| `@root` | `/` |
| `@nix` | `/nix` |
| `@home` | `/home` |
| `@games` | `/games`, owned by `player` |

The subvolumes share the space of one filesystem, so none of them has a fixed size,
and game files can be reflinked between the Nix store and `/games` without taking
space twice.

The image only contains the ESP and a btrfs partition just big enough for the system;
both partition and filesystem grow on first boot (see `hosts/lanbox/image.nix`, the
image build is `hosts/lanbox/disk-image.nix`).

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
lsblk                 # btrfs partition grown to fill the stick
df -h /               # filesystem grown with it
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

## Games

Three parts work together:

- **LANOS** (this repository): the stick system, the launcher `lanbox`, the master
  module and tools, and `lib` for describing games. It knows how to run games, not
  which ones.
- **A group flake**, one per LAN group: the group's games as recipes, plus where its
  library is. A recipe holds everything about a game except its files, and pins those
  files by hash, so a game's config and files always belong together. Recipes contain
  no game data.
- **A library**, one per group: a Nix store on the master, typically the organizer's
  laptop, holding the game files imported from installs the group owns, the built game
  packages and the stick system. The master serves it on the LAN as a signed binary
  cache. It never goes into git or a public cache, because it contains the games.

Every player must own the games.

To add a game, see [Adding a game](docs/adding-a-game.md): finding out what it needs,
writing its recipe, running it in Wine, and debugging it on a stick.

### Starting a group

```sh
mkdir our-games && cd our-games
nix flake init -t github:acidg/lanos#group
```

Create the library's signing key on the master and put the public key into
`flake.nix`, together with the master's hostname:

```sh
nix key generate-secret --key-name lanos-our-group-1 > /path/to/library/keys/library.secret
nix key convert-secret-to-public < /path/to/library/keys/library.secret
```

Sticks for the group are built from the group flake (`nix build .#image`), so they
know the library and trust only its key. Flash them as described above.

### Running the master

The master is a NixOS machine importing the master module:

```nix
imports = [ lanos.nixosModules.master ];
lanos.master = {
  enable = true;
  store = "/path/to/library";        # a disk with room for all games
  user = "organizer";                 # owns the library store
  signingKeyFile = "/path/to/library/keys/library.secret";
};
```

It serves the library on port 5000, announces itself as `<hostname>.local` and
installs the tools below, which run in a checkout of the group flake.

```sh
lanos-import cs16 ~/.steam/steam/steamapps/common/Half-Life
lanos-import cs16 deck@steamdeck:.local/share/Steam/steamapps/common/Half-Life
lanos-publish
lanos-push lanbox-xxxxxx cs16 [game ...]
```

- `lanos-import` copies a game's files from an install, locally or over SSH, e.g. from
  a Steam Deck with SSH enabled, into the library. If the files differ from the
  recipe, it prints their hash; put it into the recipe when this is the version you
  want.
- `lanos-publish` builds every game and the stick system into the library and
  publishes the index sticks read. Each publish is kept as a generation of the profile
  `<library>/nix/var/nix/profiles/library`.
- `lanos-push` installs games on a stick over SSH, copying only what it does not have.

### On the stick

Players choose the games on their stick with "Manage Games" from the application menu
(`lanbox manage`). It lists the library's games with the space each one takes and the
free space on the stick; ticking a game installs or updates it, unticking one removes
it with its settings and Wine prefix and frees its space. Each installed game gets its
own menu entry. On the first start the launcher asks for the player's name;
"lanbox name" changes it.

```sh
lanbox list            # installed games
lanbox run cs16        # what the menu entry runs
lanbox configure cs16  # render the configs and print the command, without starting
```

Each run is logged to `~/.local/state/lanbox/logs/`.

## Repository layout

```
flake.nix               Pinned nixpkgs; lib, modules, packages, group template
hosts/lanbox/           Base system, hardware support, disk layout and image build
modules/                clock, graphics (boot menu GPU entries), locale (language and
                        keyboard chooser), network, session, firstboot, ssh,
                        games (launcher and library), master (library server)
lib/                    mkGame, gameFiles and mkGroup for group flakes
launcher/               lanbox, the game launcher (Python)
pkgs/                   Nix packages of the launcher and the master tools
scripts/                flash.sh, add-ssh-key.sh, update-stick.sh, run-vm.sh,
                        lanos-import, lanos-publish, lanos-push
templates/group/        Starting point for a group flake
docs/                   Adding a game
```

## License

MIT, see [LICENSE](LICENSE). The license covers this repository only; the games
themselves are not part of it, and every player must own them.
