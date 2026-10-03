"""Prepares a game for the player and the display before each launch: renders its config
templates, command and environment, then runs its optional configure hook."""

import os
import subprocess
from pathlib import Path
from string import Template

from .display import Mode
from .manifest import Game
from .profile import Profile

HOOK_ENV_PREFIX = "LANBOX_"


class ConfigureError(Exception):
    pass


def variables(game: Game, profile: Profile, native: Mode, roots: dict[str, Path]) -> dict[str, str]:
    """What templates may use, e.g. $player_name or $instance. width and height are the
    resolution the game renders at; gamescope scales it to the native one."""
    resolution = game.resolution or native
    values = {
        "player_name": profile.player_name,
        "width": resolution.width,
        "height": resolution.height,
        "native_width": native.width,
        "native_height": native.height,
        "refresh": native.refresh,
        **roots,
    }
    return {key: str(value) for key, value in values.items()}


def render(text: str, values: dict[str, str], where: str) -> str:
    try:
        return Template(text).substitute(values)
    except (KeyError, ValueError) as error:
        raise ConfigureError(f"{where}: unknown or malformed variable {error}") from None


def render_command(game: Game, values: dict[str, str]) -> list[str]:
    return [render(arg, values, f"{game.id} command") for arg in game.command]


def render_env(game: Game, values: dict[str, str]) -> dict[str, str]:
    return {key: render(value, values, f"{game.id} env {key}") for key, value in game.env.items()}


def write_configs(game: Game, values: dict[str, str], roots: dict[str, Path]) -> list[Path]:
    """Render every config template of the game; roots maps each config root name to
    its directory. Returns the written files."""
    written = []
    for config in game.configs:
        target = roots[config.root] / config.target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render(config.template.read_text(), values, str(config.template)))
        written.append(target)
    return written


def run_hook(game: Game, values: dict[str, str], cwd: Path) -> None:
    """Run the game's configure hook with the template variables as LANBOX_* environment
    variables, e.g. LANBOX_PLAYER_NAME, LANBOX_INSTANCE."""
    if game.configure_hook is None:
        return
    env = dict(os.environ)
    for key, value in values.items():
        env[HOOK_ENV_PREFIX + key.upper()] = value
    result = subprocess.run([game.configure_hook], cwd=cwd, env=env, check=False)
    if result.returncode != 0:
        raise ConfigureError(f"{game.configure_hook} failed with exit code {result.returncode}")
