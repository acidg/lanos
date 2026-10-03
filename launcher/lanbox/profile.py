"""The player's profile, stored per stick in the player's home."""

import tomllib
from dataclasses import dataclass
from pathlib import Path

import tomli_w

# Call of Duty truncates longer names; the other games allow more.
NAME_MAX_LENGTH = 15
# Game configs quote the name and separate commands with ';', so these would break them.
NAME_FORBIDDEN = '"\\;'


@dataclass(frozen=True)
class Profile:
    player_name: str


def validate_name(name: str) -> str:
    """The name without surrounding whitespace; raises ValueError if games cannot use it."""
    name = name.strip()
    if not name:
        raise ValueError("The name must not be empty.")
    if len(name) > NAME_MAX_LENGTH:
        raise ValueError(f"The name must have at most {NAME_MAX_LENGTH} characters.")
    if not name.isprintable() or any(char in NAME_FORBIDDEN for char in name):
        raise ValueError(f"The name must not contain {' '.join(NAME_FORBIDDEN)}.")
    return name


def load(path: Path) -> Profile | None:
    """The stored profile, or None before the player has entered a name."""
    if not path.is_file():
        return None
    data = tomllib.loads(path.read_text())
    return Profile(player_name=validate_name(str(data.get("player_name", ""))))


def save(path: Path, profile: Profile) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(tomli_w.dumps({"player_name": profile.player_name}))
