"""Installing and removing games from the group's library. Packages are Nix store paths;
the library serves them as a signed binary cache next to an index, games.json, that names
the current package of each game."""

import json
import shutil
import subprocess
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from . import instance
from .manifest import MANIFEST_NAME, Game, load, load_installed

INDEX_NAME = "games.json"
INDEX_FORMAT = 1
DESKTOP_PREFIX = "lanbox-"


class LibraryError(Exception):
    pass


@dataclass(frozen=True)
class Package:
    """A game's package, in the library or installed on the stick."""

    name: str
    version: str
    path: str


def parse_index(text: str) -> dict[str, Package]:
    """The current package of each game, by game id."""
    data = json.loads(text)
    if data.get("format") != INDEX_FORMAT:
        raise LibraryError(f"library index format {data.get('format')} is not supported")
    return {
        game_id: Package(game["name"], game["version"], game["path"])
        for game_id, game in data["games"].items()
    }


def fetch_index(url: str) -> dict[str, Package]:
    try:
        with urllib.request.urlopen(f"{url.rstrip('/')}/{INDEX_NAME}", timeout=10) as response:
            return parse_index(response.read().decode())
    except (OSError, ValueError, KeyError) as error:
        raise LibraryError(f"Cannot read the game library at {url}: {error}") from None


def installed(packages: Path) -> dict[str, Package]:
    """The installed package of each game, by game id."""
    return {
        game.id: Package(game.name, game.version, str((packages / game.id).resolve()))
        for game in load_installed(packages).values()
    }


def needed_bytes(url: str, store_path: str) -> int:
    """Disk space installing store_path takes: the size of everything in its closure
    the stick does not have yet."""
    result = subprocess.run(
        ["nix", "path-info", "--json", "--json-format", "1", "--recursive", "--store", url, store_path],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise LibraryError(f"Cannot look up {store_path} in the library: {result.stderr.strip()}")
    closure = json.loads(result.stdout)
    return sum(info["narSize"] for path, info in closure.items() if not Path(path).exists())


def install(packages: Path, instances: Path, game_id: str, store_path: str) -> None:
    """Make store_path the installed package of game_id. Nix fetches it from the library
    if the stick does not have it yet, showing its progress on the terminal, and the link
    in packages keeps it from being garbage collected. The game's instance is prepared
    right away, so its first start does not have to copy files."""
    packages.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(["nix", "build", "--out-link", str(packages / game_id), store_path], check=False)
    if result.returncode != 0:
        raise LibraryError(f"Cannot install {game_id}, see the output of nix above.")
    manifest = packages / game_id / MANIFEST_NAME
    if not manifest.is_file():
        raise LibraryError(f"{store_path} is not a game package")
    game_instance = instances / game_id
    try:
        with instance.lock(game_instance):
            instance.prepare(load(manifest), game_instance)
    except instance.InstanceBusy:
        # The running game keeps its files; its next start renews them.
        pass


def uninstall(packages: Path, instances: Path, game_id: str) -> None:
    """Remove a game and everything it keeps on the stick: settings, Wine prefix and
    copy of its files. Its package stays in the store until collect_garbage."""
    link = packages / game_id
    if not link.is_symlink():
        raise LibraryError(f"{game_id} is not installed")
    try:
        with instance.lock(instances / game_id):
            shutil.rmtree(instances / game_id)
    except instance.InstanceBusy:
        raise LibraryError(f"{game_id} is running; quit it first.") from None
    link.unlink()


def collect_garbage() -> None:
    """Free the space of packages that no installed game and no system needs any more."""
    result = subprocess.run(["nix-store", "--gc"], stdout=subprocess.DEVNULL, check=False)
    if result.returncode != 0:
        raise LibraryError("Cannot free the space of removed games, see the output of nix above.")


def desktop_entry(game: Game) -> str:
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={game.name}\n"
        "Icon=applications-games\n"
        "Categories=Game;\n"
        f"Exec=lanbox run {game.id}\n"
    )


def update_menu(packages: Path, applications: Path) -> None:
    """One application menu entry per installed game, and none for removed ones."""
    applications.mkdir(parents=True, exist_ok=True)
    games = load_installed(packages)
    for stale in applications.glob(f"{DESKTOP_PREFIX}*.desktop"):
        if stale.stem.removeprefix(DESKTOP_PREFIX) not in games:
            stale.unlink()
    for game in games.values():
        (applications / f"{DESKTOP_PREFIX}{game.id}.desktop").write_text(desktop_entry(game))
