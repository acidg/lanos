"""Installed games: each package in the Nix store carries a game.json, generated and
type-checked by lanos.lib.mkGame when the package is built."""

import json
from dataclasses import dataclass
from pathlib import Path

MANIFEST_NAME = "game.json"
# The game.json layout this launcher understands; mkGame writes the same number.
FORMAT = 1
CONFIG_ROOTS = ("home", "instance", "install")


class ManifestError(Exception):
    pass


@dataclass(frozen=True)
class Resolution:
    width: int
    height: int


@dataclass(frozen=True)
class ConfigFile:
    template: Path
    target: str
    # What target is relative to: the player's home, the game's writable directory on
    # this stick, or the stick's writable copy of the game's files.
    root: str


@dataclass(frozen=True)
class Game:
    id: str
    name: str
    version: str
    command: tuple[str, ...]
    env: dict[str, str]
    # Working directory, a template like the command.
    directory: str
    gamescope: bool
    # None means the display's native resolution.
    resolution: Resolution | None
    configs: tuple[ConfigFile, ...]
    configure_hook: Path | None
    # Game files the stick gets a writable copy of, for games that write next to
    # themselves.
    install: Path | None


def _parse(data: dict) -> Game:
    if data.get("format") != FORMAT:
        raise ManifestError(f"format {data.get('format')} is not supported, expected {FORMAT}")
    resolution = data["resolution"]
    configs = tuple(
        ConfigFile(Path(config["template"]), config["target"], config["root"])
        for config in data["configs"]
    )
    for config in configs:
        if config.root not in CONFIG_ROOTS:
            raise ManifestError(f"unknown config root '{config.root}'")
    return Game(
        id=data["id"],
        name=data["name"],
        version=data["version"],
        command=tuple(data["command"]),
        env=dict(data["env"]),
        directory=data["directory"],
        gamescope=data["gamescope"],
        resolution=Resolution(**resolution) if resolution else None,
        configs=configs,
        configure_hook=Path(data["configure"]) if data["configure"] else None,
        install=Path(data["install"]) if data["install"] else None,
    )


def load(path: Path) -> Game:
    """Load one game.json."""
    try:
        return _parse(json.loads(path.read_text()))
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise ManifestError(f"{path}: {error}") from None


def load_installed(packages: Path) -> dict[str, Game]:
    """The games installed below packages/<id>, keyed and sorted by id."""
    games = [load(path) for path in sorted(packages.glob(f"*/{MANIFEST_NAME}"))]
    return {game.id: game for game in games}
