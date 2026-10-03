import json
from pathlib import Path

import pytest

from lanbox.display import Mode
from lanbox.launch import Locations
from lanbox.profile import Profile

NATIVE = Mode(2560, 1440, 144)


def game_json(**overrides) -> dict:
    """A game.json as lanos.lib.mkGame writes it."""
    data = {
        "format": 1,
        "id": "test",
        "name": "Test Game",
        "version": "1.0",
        "command": ["/bin/game", "-width", "$width", "+name", "$player_name"],
        "env": {},
        "directory": "$instance",
        "gamescope": False,
        "resolution": {"width": 1024, "height": 768},
        "configs": [],
        "configure": None,
        "install": None,
    }
    return {**data, **overrides}


def write_package(packages: Path, **overrides) -> Path:
    """An installed package: packages/<id>/game.json."""
    data = game_json(**overrides)
    package = packages / data["id"]
    package.mkdir(parents=True)
    (package / "game.json").write_text(json.dumps(data))
    return package


@pytest.fixture
def packages(tmp_path: Path) -> Path:
    return tmp_path / "packages"


@pytest.fixture
def locations(tmp_path: Path) -> Locations:
    return Locations(instances=tmp_path / "instances", home=tmp_path / "home", log_dir=tmp_path / "logs")


@pytest.fixture
def player() -> Profile:
    return Profile(player_name="Bene")
