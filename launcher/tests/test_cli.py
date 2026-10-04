import pytest

from lanbox import cli, paths, profile


class FakeDialogs:
    def __init__(self, answers):
        self.answers = list(answers)
        self.errors = []

    def ask(self, question, default=""):
        return self.answers.pop(0) if self.answers else None

    def error(self, message):
        self.errors.append(message)


@pytest.fixture(autouse=True)
def isolated(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("LANBOX_PACKAGES", str(tmp_path / "packages"))
    monkeypatch.delenv("LANBOX_LIBRARY_URL", raising=False)


def use_dialogs(monkeypatch, answers):
    fake = FakeDialogs(answers)
    monkeypatch.setattr(cli.dialogs, "for_this_process", lambda: fake)
    return fake


def test_name_argument_is_stored():
    assert cli.main(["name", "Bene"]) == 0

    assert profile.load(paths.profile_file()).player_name == "Bene"


def test_name_is_asked_again_until_usable(monkeypatch):
    fake = use_dialogs(monkeypatch, ['Bad"Name', "Good"])

    assert cli.main(["name"]) == 0

    assert len(fake.errors) == 1
    assert profile.load(paths.profile_file()).player_name == "Good"


def test_cancelled_name_question_stores_nothing(monkeypatch):
    use_dialogs(monkeypatch, [])

    assert cli.main(["name"]) == 1

    assert profile.load(paths.profile_file()) is None


def test_game_that_is_not_installed_is_reported(monkeypatch):
    fake = use_dialogs(monkeypatch, [])

    assert cli.main(["run", "nope"]) == 1

    assert "'nope' is not installed" in fake.errors[0]


def test_manage_without_library_is_reported_in_a_dialog(monkeypatch):
    fake = FakeDialogs([])
    monkeypatch.setattr(cli.dialogs, "Desktop", lambda: fake)

    assert cli.main(["manage"]) == 1

    assert "no game library" in fake.errors[0]
