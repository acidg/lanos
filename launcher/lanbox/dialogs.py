"""Questions and errors for the player: in the terminal when there is one, otherwise as
desktop dialogs, since games are usually started from the application menu."""

import subprocess
import sys

TITLE = "LANOS"


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

    def error(self, message: str) -> None:
        # Also on stderr, which ends up in the session journal.
        print(message, file=sys.stderr)
        subprocess.run(["kdialog", "--title", TITLE, "--error", message], check=False)


def for_this_process() -> Terminal | Desktop:
    if sys.stdin.isatty():
        return Terminal()
    return Desktop()
