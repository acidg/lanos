import json

import pytest
from conftest import write_package

from lanbox import library


def index(**games):
    return json.dumps({"format": 1, "games": {i: {"path": p} for i, p in games.items()}})


def test_index_maps_games_to_store_paths():
    assert library.parse_index(index(cs16="/nix/store/abc-cs16")) == {"cs16": "/nix/store/abc-cs16"}


def test_index_of_unknown_format_is_rejected():
    with pytest.raises(library.LibraryError):
        library.parse_index(json.dumps({"format": 2, "games": {}}))


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
