"""Questions and errors for the player: in the terminal when there is one, otherwise as
desktop dialogs, since games are usually started from the application menu."""

import subprocess
import sys
from dataclasses import dataclass

TITLE = "LANOS"


@dataclass(frozen=True)
class Choice:
    """An entry of a checklist, returned by its key when ticked."""

    key: str
    label: str
    ticked: bool


class Terminal:
    def ask(self, question: str, default: str = "") -> str | None:
        """The answer, the default for an empty answer, or None if input ended."""
        suffix = f" [{default}]" if default else ""
        try:
            answer = input(f"{question}{suffix}: ").strip()
        except EOFError:
            return None
        return answer or default

    def error(self, message: str) -> None:
        print(message, file=sys.stderr)

    def info(self, message: str) -> None:
        print(message)


class Desktop:
    def ask(self, question: str, default: str = "") -> str | None:
        """The answer, or None if the player cancelled."""
        result = subprocess.run(
            ["kdialog", "--title", TITLE, "--inputbox", question, default],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return None
        return result.stdout.strip()

    def choose(self, text: str, choices: list[Choice]) -> list[str] | None:
        """The keys of the ticked choices, or None if the player cancelled."""
        command = ["kdialog", "--title", TITLE, "--separate-output", "--checklist", text]
        for choice in choices:
            command += [choice.key, choice.label, "on" if choice.ticked else "off"]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            return None
        return result.stdout.split()

    def error(self, message: str) -> None:
        # Also on stderr, which ends up in the session journal.
        print(message, file=sys.stderr)
        subprocess.run(["kdialog", "--title", TITLE, "--error", message], check=False)

    def info(self, message: str) -> None:
        print(message)
        subprocess.run(["kdialog", "--title", TITLE, "--msgbox", message], check=False)


def for_this_process() -> Terminal | Desktop:
    if sys.stdin.isatty():
        return Terminal()
    return Desktop()
