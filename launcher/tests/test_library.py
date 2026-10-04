import json

import pytest
from conftest import write_package

from lanbox import instance, library
from lanbox.library import Package


def index(**games):
    return json.dumps({"format": 1, "games": games})


def install_link(packages, store, game_id, **overrides):
    """An installed game as on a stick: packages/<id> links to its package."""
    package = write_package(store, id=game_id, **overrides)
    packages.mkdir(exist_ok=True)
    (packages / game_id).symlink_to(package)
    return package


def test_index_maps_games_to_their_packages():
    text = index(cs16={"name": "Counter-Strike 1.6", "version": "1.0", "path": "/nix/store/abc-cs16"})

    assert library.parse_index(text) == {"cs16": Package("Counter-Strike 1.6", "1.0", "/nix/store/abc-cs16")}


def test_index_of_unknown_format_is_rejected():
    with pytest.raises(library.LibraryError):
        library.parse_index(json.dumps({"format": 2, "games": {}}))


def test_installed_games_name_their_packages(packages, tmp_path):
    package = install_link(packages, tmp_path / "store", "cs16", name="Counter-Strike 1.6", version="2.0")

    assert library.installed(packages) == {"cs16": Package("Counter-Strike 1.6", "2.0", str(package))}


def test_uninstall_removes_the_game_and_its_instance(packages, tmp_path):
    package = install_link(packages, tmp_path / "store", "cs16")
    instances = tmp_path / "instances"
    (instances / "cs16" / "prefix").mkdir(parents=True)

    library.uninstall(packages, instances, "cs16")

    assert not (packages / "cs16").exists()
    assert not (instances / "cs16").exists()
    assert package.is_dir()


def test_running_game_is_not_uninstalled(packages, tmp_path):
    install_link(packages, tmp_path / "store", "cs16")
    instances = tmp_path / "instances"

    with instance.lock(instances / "cs16"), pytest.raises(library.LibraryError, match="running"):
        library.uninstall(packages, instances, "cs16")

    assert (packages / "cs16").is_symlink()


def test_menu_has_one_entry_per_installed_game(packages, tmp_path):
    applications = tmp_path / "applications"
    applications.mkdir()
    (applications / "lanbox-removed.desktop").write_text("old")
    (applications / "other.desktop").write_text("keep")
    write_package(packages, id="cs16", name="Counter-Strike 1.6")

    library.update_menu(packages, applications)

    entries = sorted(path.name for path in applications.iterdir())
    assert entries == ["lanbox-cs16.desktop", "other.desktop"]
    entry = (applications / "lanbox-cs16.desktop").read_text()
    assert "Name=Counter-Strike 1.6\n" in entry
    assert "Exec=lanbox run cs16\n" in entry
