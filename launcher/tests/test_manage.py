from lanbox import manage
from lanbox.dialogs import Choice
from lanbox.library import Package

CS_NEW = Package("Counter-Strike 1.6", "2", "/nix/store/new-cs16")
CS_OLD = Package("Counter-Strike 1.6", "1", "/nix/store/old-cs16")
KW = Package("Kane's Wrath", "1", "/nix/store/kw")
GONE = Package("Gone", "1", "/nix/store/gone")


def test_checklist_ticks_installed_games_and_shows_what_they_take():
    available = {"cs16": CS_NEW, "kw": KW}
    installed = {"cs16": CS_OLD, "gone": GONE}
    needed = {"cs16": 1_200_000_000, "kw": 5_500_000_000}

    assert manage.choices(available, installed, needed) == [
        Choice("cs16", "Counter-Strike 1.6: Update 1 → 2, 1.2 GB", True),
        Choice("gone", "Gone 1: nicht in der Bibliothek / not in the library", True),
        Choice("kw", "Kane's Wrath 1: 5.5 GB", False),
    ]


def test_current_game_is_shown_as_installed():
    assert manage.choices({"cs16": CS_NEW}, {"cs16": CS_NEW}, {}) == [
        Choice("cs16", "Counter-Strike 1.6 2: installiert / installed", True),
    ]


def test_ticked_games_are_installed_or_updated_and_unticked_removed():
    available = {"cs16": CS_NEW, "kw": KW}
    installed = {"cs16": CS_OLD, "gone": GONE}

    changes = manage.changes(available, installed, {"cs16", "kw"})

    assert changes == manage.Changes(install=["cs16", "kw"], remove=["gone"])


def test_current_and_unlisted_games_that_stay_ticked_are_left_alone():
    installed = {"cs16": CS_NEW, "gone": GONE}

    changes = manage.changes({"cs16": CS_NEW}, installed, {"cs16", "gone"})

    assert changes == manage.Changes(install=[], remove=[])
