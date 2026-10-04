import json

import pytest
from conftest import write_package

from lanbox.manifest import ManifestError, Resolution, load, load_installed


def test_game_json_is_parsed(packages):
    package = write_package(
        packages,
        configs=[{"template": "/store/user.cfg", "target": "cfg/user.cfg", "root": "home"}],
        configure="/store/hooks/configure",
    )

    game = load(package / "game.json")

    assert game.name == "Test Game"
    assert game.command[0] == "/bin/game"
    assert game.resolution == Resolution(1024, 768)
    assert game.configs[0].root == "home"
    assert str(game.configure_hook) == "/store/hooks/configure"


def test_native_resolution_is_none(packages):
    package = write_package(packages, resolution=None)

    assert load(package / "game.json").resolution is None


def test_game_json_without_fps_counter_shows_none(packages):
    package = write_package(packages)
    manifest = package / "game.json"
    data = json.loads(manifest.read_text())
    del data["fps_counter"]
    manifest.write_text(json.dumps(data))

    assert load(manifest).fps_counter is False


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"format": 2}, "format 2"),
        ({"configs": [{"template": "/t", "target": "x", "root": "etc"}]}, "root"),
        ({"command": None}, "game.json"),
    ],
)
def test_unusable_game_json_is_rejected(packages, overrides, message):
    package = write_package(packages, **overrides)

    with pytest.raises(ManifestError, match=message):
        load(package / "game.json")


def test_installed_games_are_sorted_by_id(packages):
    write_package(packages, id="zeta")
    write_package(packages, id="alpha")

    assert list(load_installed(packages)) == ["alpha", "zeta"]


def test_no_packages_means_no_games(packages):
    assert load_installed(packages) == {}
