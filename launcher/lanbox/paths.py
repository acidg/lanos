"""Where the launcher reads and writes. Environment variables override the defaults so
the tests run without a stick."""

import os
from pathlib import Path


def _env_path(variable: str, default: str) -> Path:
    return Path(os.environ.get(variable, default))


def packages_dir() -> Path:
    """Installed games: packages/<id> links to the game's package in the Nix store and
    keeps it from being garbage collected."""
    return _env_path("LANBOX_PACKAGES", "/games/packages")


def instances_dir() -> Path:
    """Writable per-stick state of each game, e.g. its Wine prefix."""
    return _env_path("LANBOX_INSTANCES", "/games/instances")


def library_url() -> str | None:
    """The group's library, set by the system configuration; None without one."""
    return os.environ.get("LANBOX_LIBRARY_URL") or None


def _xdg(variable: str, fallback: str) -> Path:
    return Path(os.environ.get(variable) or Path.home() / fallback)


def profile_file() -> Path:
    return _xdg("XDG_CONFIG_HOME", ".config") / "lanbox" / "profile.toml"


def log_dir() -> Path:
    return _xdg("XDG_STATE_HOME", ".local/state") / "lanbox" / "logs"


def applications_dir() -> Path:
    return _xdg("XDG_DATA_HOME", ".local/share") / "applications"
