"""A game's writable state on the stick, below /games/instances/<id>: its settings and
Wine prefix, and for games that write next to themselves a writable copy of their
files."""

import fcntl
import shutil
import subprocess
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from .manifest import Game

INSTALL_NAME = "install"
LOCK_NAME = ".running"


class InstanceBusy(Exception):
    """The game is running, so its instance must not be started or changed."""


@contextmanager
def lock(instance: Path) -> Iterator[None]:
    """Hold the instance while a game runs from it or it is being prepared. The lock
    ends with the process, so a crashed game never leaves it behind."""
    instance.mkdir(parents=True, exist_ok=True)
    with (instance / LOCK_NAME).open("w") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise InstanceBusy() from None
        yield


def install_dir(instance: Path) -> Path:
    return instance / INSTALL_NAME


def refresh_install(source: Path, target: Path) -> None:
    """Give the stick a writable copy of the game's files, renewed when the package
    changes. On btrfs the copy shares its data with the Nix store until the game
    changes a file."""
    marker = target.with_name(target.name + ".source")
    if marker.is_file() and marker.read_text() == str(source):
        return
    if target.exists():
        shutil.rmtree(target)
    # The package links to the files of several store paths; the copy holds the files.
    subprocess.run(["cp", "-rL", "--reflink=auto", str(source), str(target)], check=True)
    subprocess.run(["chmod", "-R", "u+w", str(target)], check=True)
    marker.write_text(str(source))


def prepare(game: Game, instance: Path) -> None:
    """Create the game's instance, including the copy of its files if it needs one."""
    instance.mkdir(parents=True, exist_ok=True)
    if game.install is not None:
        refresh_install(game.install, install_dir(instance))
