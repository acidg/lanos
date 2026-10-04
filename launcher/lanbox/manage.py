"""Choosing the games on the stick. The player ticks the library's games to have, and the
launcher installs, updates and removes games to match, so the stick only holds what the
player wants and what fits."""

from dataclasses import dataclass

from .dialogs import Choice
from .library import Package

GIGABYTE = 1000**3


@dataclass(frozen=True)
class Changes:
    install: list[str]
    remove: list[str]


def size(num_bytes: int) -> str:
    return f"{num_bytes / GIGABYTE:.1f} GB"


def _label(game_id: str, offered: Package | None, current: Package | None, needed: dict[str, int]) -> str:
    if offered is None:
        return f"{current.name} {current.version}: nicht in der Bibliothek / not in the library"
    if current is None:
        return f"{offered.name} {offered.version}: {size(needed[game_id])}"
    if current.path != offered.path:
        return f"{offered.name}: Update {current.version} → {offered.version}, {size(needed[game_id])}"
    return f"{offered.name} {offered.version}: installiert / installed"


def choices(available: dict[str, Package], installed: dict[str, Package], needed: dict[str, int]) -> list[Choice]:
    """One entry per game of the library or the stick, ticked if installed. needed is
    the space each game the stick lacks or has in another version takes."""
    game_ids = sorted(available.keys() | installed.keys())
    return [
        Choice(game_id, _label(game_id, available.get(game_id), installed.get(game_id), needed), game_id in installed)
        for game_id in game_ids
    ]


def changes(available: dict[str, Package], installed: dict[str, Package], chosen: set[str]) -> Changes:
    """Install the chosen games the stick lacks or has in another version than the
    library, remove the installed games that are not chosen."""
    install = [
        game_id
        for game_id, offered in sorted(available.items())
        if game_id in chosen and (game_id not in installed or installed[game_id].path != offered.path)
    ]
    remove = [game_id for game_id in sorted(installed) if game_id not in chosen]
    return Changes(install, remove)
