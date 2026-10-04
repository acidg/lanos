"""Configures and starts a game, wrapped in gamescope, and logs the run."""

import os
import shlex
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from . import configure, instance
from .display import Mode
from .manifest import Game
from .profile import Profile


class LaunchError(Exception):
    pass


@dataclass(frozen=True)
class Locations:
    instances: Path
    home: Path
    log_dir: Path

    def roots(self, game: Game) -> dict[str, Path]:
        """The directories config targets are relative to, by config root name."""
        game_instance = self.instances / game.id
        return {
            "home": self.home,
            "instance": game_instance,
            "install": instance.install_dir(game_instance),
        }


@dataclass(frozen=True)
class Prepared:
    command: list[str]
    env: dict[str, str]
    cwd: Path


def gamescope_command(native: Mode, values: dict[str, str], fps_counter: bool) -> list[str]:
    """Fullscreen at the native resolution, with the game rendering at the resolution
    it asked for; gamescope scales it, so the display never switches modes. gamescope
    draws the frame rate itself, which works whatever the game renders with."""
    command = [
        "gamescope",
        "-W", str(native.width),
        "-H", str(native.height),
        "-w", values["width"],
        "-h", values["height"],
        "-r", str(native.refresh),
        "-f",
    ]  # fmt: skip
    if fps_counter:
        command.append("--mangoapp")
    return command + ["--"]


def prepare(game: Game, profile: Profile, native: Mode, where: Locations) -> Prepared:
    """Render the game's configs and return how to start it."""
    roots = where.roots(game)
    instance.prepare(game, roots["instance"])
    values = configure.variables(game, profile, native, roots)
    configure.write_configs(game, values, roots)
    configure.run_hook(game, values, roots["instance"])

    command = configure.render_command(game, values)
    if game.gamescope:
        command = gamescope_command(native, values, game.fps_counter) + command
    directory = Path(configure.render(game.directory, values, f"{game.id} directory"))
    return Prepared(command, configure.render_env(game, values), directory)


def run(game: Game, profile: Profile, native: Mode, where: Locations) -> Path:
    """Start the game and wait until it exits. Its output goes to a log file, which is
    returned; a nonzero exit raises LaunchError naming that log."""
    try:
        with instance.lock(where.roots(game)["instance"]):
            return _run(game, profile, native, where)
    except instance.InstanceBusy:
        raise LaunchError(f"{game.name} is already running.") from None


def _run(game: Game, profile: Profile, native: Mode, where: Locations) -> Path:
    prepared = prepare(game, profile, native, where)

    where.log_dir.mkdir(parents=True, exist_ok=True)
    log_path = where.log_dir / f"{game.id}-{datetime.now():%Y%m%d-%H%M%S}.log"
    with log_path.open("w") as log:
        log.write(f"# {game.name} {game.version}\n")
        log.write(f"# command: {shlex.join(prepared.command)}\n")
        for key, value in prepared.env.items():
            log.write(f"# env: {key}={value}\n")
        log.flush()
        result = subprocess.run(
            prepared.command,
            cwd=prepared.cwd,
            env={**os.environ, **prepared.env},
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
        log.write(f"# exit code: {result.returncode}\n")
    if result.returncode != 0:
        raise LaunchError(f"{game.name} exited with code {result.returncode}, see {log_path}.")
    return log_path
