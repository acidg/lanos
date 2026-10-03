import pytest

from lanbox.profile import Profile, load, save, validate_name


def test_saved_profile_loads_again(tmp_path):
    path = tmp_path / "lanbox" / "profile.toml"

    save(path, Profile(player_name="Bene"))

    assert load(path) == Profile(player_name="Bene")


def test_missing_profile_loads_as_none(tmp_path):
    assert load(tmp_path / "profile.toml") is None


def test_name_is_stripped():
    assert validate_name("  Bene ") == "Bene"


@pytest.mark.parametrize("name", ["", "   ", "x" * 16, 'Be"ne', "Be;ne", "Be\\ne", "Be\nne"])
def test_unusable_name_is_rejected(name):
    with pytest.raises(ValueError):
        validate_name(name)


def test_profile_with_unusable_name_is_rejected(tmp_path):
    path = tmp_path / "profile.toml"
    path.write_text('player_name = ""\n')

    with pytest.raises(ValueError):
        load(path)
