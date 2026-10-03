"""Installing games from the group's library. Packages are Nix store paths; the library
serves them as a signed binary cache next to an index, games.json, that names the
current package of each game."""

import json
import subprocess
import urllib.request
from pathlib import Path

from . import instance
from .manifest import MANIFEST_NAME, Game, load, load_installed

INDEX_NAME = "games.json"
INDEX_FORMAT = 1
DESKTOP_PREFIX = "lanbox-"


class LibraryError(Exception):
    pass


def parse_index(text: str) -> dict[str, str]:
    """Store path of each game's current package, by game id."""
    data = json.loads(text)
    if data.get("format") != INDEX_FORMAT:
        raise LibraryError(f"library index format {data.get('format')} is not supported")
    return {game_id: game["path"] for game_id, game in data["games"].items()}


def fetch_index(url: str) -> dict[str, str]:
    try:
        with urllib.request.urlopen(f"{url.rstrip('/')}/{INDEX_NAME}", timeout=10) as response:
            return parse_index(response.read().decode())
    except (OSError, ValueError, KeyError) as error:
        raise LibraryError(f"Cannot read the game library at {url}: {error}") from None


def install(packages: Path, instances: Path, game_id: str, store_path: str) -> None:
    """Make store_path the installed package of game_id. Nix fetches it from the library
    if the stick does not have it yet, and the link in packages keeps it from being
    garbage collected. The game's instance is prepared right away, so its first start
    does not have to copy files."""
    packages.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["nix-store", "--realise", store_path, "--add-root", str(packages / game_id)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise LibraryError(f"Cannot install {game_id}: {result.stderr.strip()}")
    manifest = packages / game_id / MANIFEST_NAME
    if not manifest.is_file():
        raise LibraryError(f"{store_path} is not a game package")
    instance.prepare(load(manifest), instances / game_id)


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
