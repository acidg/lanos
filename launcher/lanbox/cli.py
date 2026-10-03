"""Command line interface of the launcher, see `lanbox --help`."""

import argparse
import shlex
import sys
from pathlib import Path

from . import dialogs, display, launch, library, paths, profile
from .configure import ConfigureError
from .display import DisplayError
from .manifest import Game, ManifestError, load_installed
from .profile import Profile

NAME_QUESTION = "Spielername / Player name"

# Expected failures, reported to the player without a traceback.
ERRORS = (
    ConfigureError,
    DisplayError,
    ManifestError,
    launch.LaunchError,
    library.LibraryError,
    ValueError,
)


class Cancelled(Exception):
    pass


def _locations() -> launch.Locations:
    return launch.Locations(instances=paths.instances_dir(), home=Path.home(), log_dir=paths.log_dir())


def _game(game_id: str) -> Game:
    games = load_installed(paths.packages_dir())
    if game_id not in games:
        known = ", ".join(games) or "none"
        raise ValueError(f"Game '{game_id}' is not installed. Installed games: {known}")
    return games[game_id]


def _ask_name(ui, current: str = "") -> Profile:
    """Ask until the player enters a usable name, and store it."""
    while True:
        answer = ui.ask(NAME_QUESTION, current)
        if answer is None:
            raise Cancelled()
        try:
            new = Profile(player_name=profile.validate_name(answer))
        except ValueError as error:
            ui.error(str(error))
            continue
        profile.save(paths.profile_file(), new)
        return new


def _profile(ui) -> Profile:
    """The stored profile; on the first start the player is asked for a name."""
    return profile.load(paths.profile_file()) or _ask_name(ui)


def cmd_list(args, ui) -> None:
    for game in load_installed(paths.packages_dir()).values():
        print(f"{game.id:<12} {game.version:<12} {game.name}")


def cmd_name(args, ui) -> None:
    if args.name is not None:
        profile.save(paths.profile_file(), Profile(profile.validate_name(args.name)))
        return
    current = profile.load(paths.profile_file())
    _ask_name(ui, current.player_name if current else "")


def cmd_configure(args, ui) -> None:
    prepared = launch.prepare(_game(args.game), _profile(ui), display.detect(), _locations())
    print(shlex.join(prepared.command))


def cmd_run(args, ui) -> None:
    log_path = launch.run(_game(args.game), _profile(ui), display.detect(), _locations())
    print(f"Log: {log_path}")


def cmd_install(args, ui) -> None:
    library.install(paths.packages_dir(), paths.instances_dir(), args.game, args.store_path)
    library.update_menu(paths.packages_dir(), paths.applications_dir())


def cmd_sync(args, ui) -> None:
    url = paths.library_url()
    if url is None:
        raise ValueError("This stick has no game library configured.")
    available = library.fetch_index(url)
    for game_id in args.games or available:
        if game_id not in available:
            raise ValueError(f"The library has no game '{game_id}'.")
        print(f"Installing {game_id}...")
        library.install(paths.packages_dir(), paths.instances_dir(), game_id, available[game_id])
    library.update_menu(paths.packages_dir(), paths.applications_dir())


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="lanbox", description="LANOS game launcher")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="list the installed games")
    name = commands.add_parser("name", help="change the player name (asks without NAME)")
    name.add_argument("name", nargs="?")
    configure = commands.add_parser("configure", help="render a game's configs, print its command")
    configure.add_argument("game")
    run = commands.add_parser("run", help="configure and start a game")
    run.add_argument("game")
    sync = commands.add_parser("sync", help="install or update games from the library")
    sync.add_argument("games", nargs="*", help="game ids (default: all)")
    install = commands.add_parser("install", help="install a game package already on this stick")
    install.add_argument("game")
    install.add_argument("store_path")
    return parser


COMMANDS = {
    "list": cmd_list,
    "name": cmd_name,
    "configure": cmd_configure,
    "run": cmd_run,
    "sync": cmd_sync,
    "install": cmd_install,
}


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    ui = dialogs.for_this_process()
    try:
        COMMANDS[args.command](args, ui)
    except Cancelled:
        return 1
    except ERRORS as error:
        ui.error(str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
