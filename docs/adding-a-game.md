# Adding a game

How to get a game from an install you own onto the sticks of your group: find out what
it needs, write its recipe, import its files, publish and debug it. It assumes a group
flake and a master as described in the [README](../README.md#games).

The work happens in four places:

| What | Where |
|---|---|
| Recipe: how to start the game, its config templates, the hash of its files | `games/<id>/` in the group flake (git) |
| Game files, built packages, Wine and everything else they need | the library store on the master |
| The game's state on a stick: Wine prefix, writable copy, saved settings | `/games/instances/<id>/` on the stick |
| Launch logs | `~/.local/state/lanbox/logs/` on the stick |

Sticks never install anything themselves. A recipe names the exact Wine, libraries
and helper files the game needs, and the stick receives them together with the game.

## 1. Find out what the game needs

Answer these before writing the recipe. [PCGamingWiki](https://www.pcgamingwiki.com)
answers most of them for most games: it lists config file locations, command line
arguments, launcher and DRM requirements and known fixes.

1. **Which files**: the game's install directory, and which version. If you want to run
   a Windows version in Wine, import the Windows files, not a native Linux build of the
   same game.
2. **Native or Wine**: prefer a native Linux build if it supports LAN play with the
   Windows version others might run; otherwise use Wine.
3. **Launchers and online checks**: does the game start without its store client,
   launcher or an online login? If not, the recipe has to replace that part. How is up
   to the group; keep it in the group's repository.
4. **Command line**: arguments for resolution, fullscreen, skipping intros, choosing a
   mod or connecting to a server.
5. **What it writes, and where**: settings, saves, player name. This decides which files
   to exclude from the import, whether the game needs a writable copy of its files and
   which config templates you need.
6. **Multiplayer**: how players find a LAN game (broadcast, a server address) and which
   ports it uses. The sticks have no firewall.

## 2. Explore the game in Wine

Try the game on any Linux PC with Nix before writing a recipe, from a copy of its files
and in a throwaway Wine prefix, with the same Wine the sticks will use:

```sh
nix shell nixpkgs#wineWow64Packages.stable
cp -r ~/.steam/steam/steamapps/common/SomeGame /tmp/somegame
cd /tmp/somegame
export WINEPREFIX=/tmp/somegame-prefix WINEDLLOVERRIDES="mscoree,mshtml="
wine game.exe -windowed
```

`wineWow64Packages` comes from the binary cache and runs 32-bit and 64-bit games;
`wineWowPackages` is built from source, which takes hours. `WINEDLLOVERRIDES` keeps Wine
from offering to download Mono and Gecko, which few games need.

### Which DLLs the game needs

List the DLLs an executable imports directly:

```sh
winedump -j import game.exe | grep -i dll
```

Wine has its own version of most system and runtime DLLs, including the Visual C++
runtimes (`msvcp140.dll`, `vcruntime140.dll`, `api-ms-win-crt-*`). Only a DLL that
neither Wine nor the game's directory provides is missing.

DLLs the game loads at runtime do not show up there. Watch what it actually loads:

```sh
WINEDEBUG=err+all,+loaddll wine game.exe 2>&1 | tee /tmp/game.log
grep -E "err:|Loaded" /tmp/game.log
```

- `Loaded L"...\\d3dx9_43.dll" : builtin` means Wine's own DLL was used, `native` the
  game's or one you added.
- `err:module:import_dll Library XYZ.dll ... not found` names a DLL that is missing.
- Wine prints many harmless `err:` lines. The ones right before the game exits usually
  are the reason it exits.
- `nodrv_CreateWindow` errors mean Wine found no display: run it in the desktop
  session, not over plain SSH.

Other useful channels: `+seh` (crashes and exceptions), `+file` (which files the game
opens, e.g. to find its config), `+d3d` (Direct3D problems). `+relay` logs every call
and is only useful for very short runs.

### Fixing a missing or broken DLL

1. Look for the redistributable in the game's own files first (often `redist/`,
   `_CommonRedist/` or `DirectX/`) and put the DLL next to the game's executable.
2. Otherwise download it in the recipe with `fetchurl` and a fixed hash, never at run
   time: a LAN often has no internet.
3. Tell Wine to prefer the game's copy: `WINEDLLOVERRIDES="xyz=n,b"` (native, then
   builtin).

`winetricks` is useful to find out which redistributable fixes a game, but it
downloads at run time and changes the prefix by hand, so the recipe must reproduce what
it did instead of calling it.

### Direct3D

Wine translates Direct3D 9 to 11 to OpenGL. [DXVK](https://github.com/doitsujin/dxvk)
translates it to Vulkan instead and is often faster and more compatible. Its DLLs are
in nixpkgs (`dxvk`, folders `x32` and `x64`); put the ones matching the game's
architecture next to its executable:

```sh
nix build nixpkgs#dxvk -o /tmp/dxvk
cp /tmp/dxvk/x32/d3d9.dll /tmp/somegame/        # a 32-bit Direct3D 9 game
WINEDLLOVERRIDES="mscoree,mshtml=;d3d9=n,b" wine game.exe
```

Whether a game is 32-bit or 64-bit: `file game.exe` says `PE32` or `PE32+`.

### What the game writes

Start the game, change a setting, quit, and list what changed:

```sh
touch /tmp/before
wine game.exe
find /tmp/somegame "$WINEPREFIX/drive_c/users" -newer /tmp/before -type f
```

- Files in the game's directory: exclude them from the import, and give the game a
  writable copy of its files (`install`, see below).
- Files below `drive_c/users`: they land in the stick's prefix, which is writable. Only
  the ones you want to set for every player need templates.

Do the same with the original install: everything there that the store client or
earlier players wrote (settings, saves, logs, downloaded content you do not want) goes
into `exclude`.

## 3. Write the recipe

A recipe is `games/<id>/default.nix` in the group flake, listed in its `flake.nix`:

```nix
games = [ ./games/cs16 ./games/somegame ];
```

It is called like a nixpkgs package: it can take any nixpkgs package as an argument,
plus `lanos`, which has `gameFiles` and `mkGame`. A Wine game looks like this:

```nix
{ lanos, runCommand, writeShellScript, wineWow64Packages, dxvk }:
let
  wine = wineWow64Packages.stable;

  # gamescope ends the game's leftover processes as soon as the game exits, which
  # kills Wine's server before Wine's services have stopped, and then the game window
  # never closes. Waiting for Wine to shut down first lets it close.
  run = writeShellScript "somegame" ''
    ${wine}/bin/wine "$@"
    status=$?
    ${wine}/bin/wineserver -w
    exit $status
  '';

  files = lanos.gameFiles {
    name = "somegame-windows";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # see step 4
    source = "Steam: Some Game, Windows version, steamapps/common/SomeGame";
    exclude = [ "settings.ini" "saves/" "*.log" ];
  };

  # Only for games that write into their own directory.
  install = runCommand "somegame-install" { } ''
    mkdir $out
    cp -rs ${files}/. $out/
    chmod -R u+w $out
    ln -s ${dxvk}/x32/d3d9.dll $out/d3d9.dll
  '';
in
lanos.mkGame {
  id = "somegame";
  name = "Some Game";
  version = "1";
  inherit files install;
  directory = "$install";
  command = [ "${run}" "game.exe" "-width" "$width" "-height" "$height" "-fullscreen" ];
  env = {
    WINEPREFIX = "$instance/prefix";
    WINEDLLOVERRIDES = "mscoree,mshtml=;d3d9=n,b";
    WINEDEBUG = "-all";
  };
  configs = [
    { template = ./settings.ini; target = "settings.ini"; root = "install"; }
  ];
}
```

Every Wine game needs the `run` wrapper. Wine creates the prefix on the first start,
which takes a few seconds longer.

### mkGame options

| Option | Default | Meaning |
|---|---|---|
| `id` | | Short name: lowercase letters, digits and `-`. Used for directories and `lanbox run <id>`. |
| `name` | | Name in the application menu. |
| `version` | | Change it with every change to the recipe, so you can tell which version a stick runs. |
| `files` | `null` | The game files from `lanos.gameFiles`, so `lanos-import` knows them. |
| `install` | `null` | A package the stick gets a writable copy of, as `$install`, for games that write into their own directory. |
| `command` | | Command line as a list, one argument per element. |
| `env` | `{ }` | Environment variables. |
| `directory` | `"$instance"` | Working directory. Many games load their DLLs or data from there; set it to the game's directory (`$install`, or a path in `files`). |
| `gamescope` | `true` | Run the game in gamescope, which shows it fullscreen at the display's resolution. |
| `fpsCounter` | `false` | Show the frame rate in a corner of the screen, drawn by gamescope with MangoHud. Needs `gamescope`. |
| `resolution` | `"native"` | Resolution the game renders at, e.g. `"1024x768"` for old games; gamescope scales it to the display. |
| `configs` | `[ ]` | Templates rendered before every start, see below. |
| `configure` | `null` | Script run before every start, for settings a template cannot express. Gets the variables as `LANBOX_PLAYER_NAME`, `LANBOX_INSTANCE` and so on. |

### Template variables

`command`, `env`, `directory` and the config templates can use:

| Variable | Value |
|---|---|
| `$player_name` | Name the player chose on the first start (at most 15 characters). |
| `$width`, `$height` | Resolution the game renders at. |
| `$native_width`, `$native_height`, `$refresh` | The display's resolution and refresh rate. |
| `$instance` | The game's writable directory on the stick, `/games/instances/<id>`. |
| `$install` | Its writable copy of `install`, `$instance/install`. |
| `$home` | The player's home. |

A literal `$` is written `$$`. An unknown variable stops the start with an error.

### Config templates

Each entry of `configs` renders `template` to `target`, a path relative to `root`:
`instance` (default), `install` or `home`. Templates are rendered before **every**
start and overwrite the file, so they should hold only what every player must have:
the player name, LAN settings, the resolution. Settings a player changes in the game
stay in files no template writes.

### Files the game writes

- **Into the prefix** (`drive_c/users/...`): nothing to do; the prefix is in
  `$instance` and stays.
- **Into its own directory**: give the recipe an `install` package and start the game
  from `$install`. The stick copies it once and replaces the copy when the package
  changes, so with every new version of the game
  the player's changes there are lost.
- `install` is the place to add or replace files of the game: extra DLLs, a fix, a
  generated default config. Link (`ln -s`, `cp -rs`) rather than copy, the stick's copy
  follows the links.

### Native Linux games

Leave out Wine and the wrapper; the command starts the game's binary. Binaries built
for other distributions do not find their libraries on NixOS: patch them in a
derivation with `autoPatchelfHook` and the libraries they need, or start them in an
environment from `buildFHSEnv`.

## 4. Import the files

Put any hash into the recipe at first. On the master, in the group flake checkout:

```sh
lanos-import somegame ~/.steam/steam/steamapps/common/SomeGame
lanos-import somegame deck@steamdeck:.local/share/Steam/steamapps/common/SomeGame
```

The files differ from the recipe, so the import prints their hash; put it into the
recipe. You do not have to import again: the files are already in the library under
the name and hash the recipe now asks for. An interrupted import resumes where it
stopped when you run it again.

From now on the hash pins exactly these files. If you change `include` or `exclude` or
want a new version of the game, import again and update the hash.

## 5. Publish and test

```sh
lanos-publish                       # build every game and the stick system, sign, publish
lanos-push lanbox-xxxxxx somegame   # install on one stick
```

A broken recipe fails in `lanos-publish`, with the build error. `lanos-push` installs
right away; no reboot. Start the game from the stick's menu or
over SSH with `lanbox run somegame`. While something is still wrong, repeat: change the
recipe, raise `version`, publish, push. Commit the recipe once the game works.

## 6. Debugging on a stick

### Logs

Every start writes `~/.local/state/lanbox/logs/<id>-<time>.log`: the full command,
the environment and everything the game printed, and its exit code at the end.

```sh
ssh -i ~/.ssh/lanos_ed25519 player@lanbox-xxxxxx
ls -t ~/.local/state/lanbox/logs/ | head -3
lanbox configure somegame     # render the configs, print the command, start nothing
```

### Starting by hand

To change Wine's debug output or try other arguments without publishing, start the
game in a terminal (Konsole) on the stick with the values from the log. The log's
command starts with gamescope and its arguments up to `--`; leave them out to run the
game in a normal window. Next comes the recipe's `run` wrapper, a script in the store;
`cat` it to see which Wine it calls, and put that Wine on the `PATH`, since the stick
has none of its own:

```sh
cat /nix/store/...-somegame
export PATH=/nix/store/...-wine-wow64-11.0/bin:$PATH
export WINEPREFIX=/games/instances/somegame/prefix WINEDLLOVERRIDES="mscoree,mshtml="
cd /games/instances/somegame/install
WINEDEBUG=err+all,+loaddll wine game.exe -windowed
```

In that shell, `wine winecfg` shows the prefix's DLL overrides and Windows version,
`wine regedit` its registry, and `wineserver -k` ends every Wine process of the prefix.

### Common problems

| Symptom | Look at |
|---|---|
| Nothing happens, the log ends right away | The exit code and the last `err:` lines. Often a missing DLL or a wrong `directory`. |
| "already running" | A previous start is still running: `pgrep -a wine`, then `wineserver -k` as in [Starting by hand](#starting-by-hand). |
| The window does not close after quitting | The `run` wrapper is missing, or a Wine process hangs: `wineserver -k`. |
| Black screen, wrong size or flicker | Try `gamescope = false` to rule out gamescope, or a fixed `resolution`. For Direct3D games try with and without DXVK. |
| Works on one GPU, not on another | Compare `glxinfo -B` and `vulkaninfo --summary` on both sticks, and the boot menu entry used. |
| The game finds no LAN games | Both sticks on the same network (`ip addr`), the game's own LAN setting, and its ports. |
| A broken prefix or copy after experiments | Remove `/games/instances/<id>/prefix` or `.../install`; the next start creates them again. Removing the whole `/games/instances/<id>` also drops the player's settings. |
