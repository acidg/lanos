from pathlib import Path

import pytest
from conftest import NATIVE, write_package

from lanbox import launch
from lanbox.configure import ConfigureError
from lanbox.manifest import load


def make_game(packages, tmp_path, template='name "$player_name"\nrate $refresh\n', **overrides):
    template_file = tmp_path / "user.cfg"
    template_file.write_text(template)
    overrides.setdefault(
        "configs", [{"template": str(template_file), "target": "cfg/user.cfg", "root": "instance"}]
    )
    package = write_package(packages, **overrides)
    return load(package / "game.json")


def test_configs_are_rendered_with_player_and_display(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path)

    launch.prepare(game, player, NATIVE, locations)

    config = locations.instances / "test" / "cfg" / "user.cfg"
    assert config.read_text() == 'name "Bene"\nrate 144\n'


def test_configs_can_target_the_home_directory(packages, tmp_path, locations, player):
    configs = [{"template": str(tmp_path / "user.cfg"), "target": ".game/user.cfg", "root": "home"}]
    game = make_game(packages, tmp_path, configs=configs)

    launch.prepare(game, player, NATIVE, locations)

    assert (locations.home / ".game" / "user.cfg").is_file()


def test_unknown_template_variable_is_an_error(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, template="$nickname\n")

    with pytest.raises(ConfigureError, match="nickname"):
        launch.prepare(game, player, NATIVE, locations)


def test_command_and_env_are_rendered(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, env={"WINEPREFIX": "$instance/prefix"})

    prepared = launch.prepare(game, player, NATIVE, locations)

    instance = locations.instances / "test"
    assert prepared.command == ["/bin/game", "-width", "1024", "+name", "Bene"]
    assert prepared.env == {"WINEPREFIX": f"{instance}/prefix"}
    assert prepared.cwd == instance


def test_game_can_start_in_another_directory(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, directory="/nix/store/engine/lib")

    assert launch.prepare(game, player, NATIVE, locations).cwd == Path("/nix/store/engine/lib")


def test_gamescope_scales_game_resolution_to_native(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, gamescope=True)

    command = launch.prepare(game, player, NATIVE, locations).command

    separator = command.index("--")
    assert command[:separator] == [
        "gamescope", "-W", "2560", "-H", "1440", "-w", "1024", "-h", "768", "-r", "144", "-f",
    ]  # fmt: skip
    assert command[separator + 1] == "/bin/game"


def test_native_resolution_renders_at_display_size(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, resolution=None)

    command = launch.prepare(game, player, NATIVE, locations).command

    assert command[2] == "2560"


def test_configure_hook_gets_variables(packages, tmp_path, locations, player):
    hook = tmp_path / "configure"
    hook.write_text('#!/bin/sh\necho "$LANBOX_PLAYER_NAME $LANBOX_WIDTH" > hook.out\n')
    hook.chmod(0o755)
    game = make_game(packages, tmp_path, configure=str(hook))

    launch.prepare(game, player, NATIVE, locations)

    assert (locations.instances / "test" / "hook.out").read_text() == "Bene 1024\n"


def game_script(tmp_path, body):
    script = tmp_path / "game.sh"
    script.write_text(f"#!/bin/sh\n{body}\n")
    script.chmod(0o755)
    return [str(script), "-width", "$width", "+name", "$player_name"]


def test_run_logs_command_and_game_output(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, command=game_script(tmp_path, 'echo "started as $4"'))

    log = launch.run(game, player, NATIVE, locations)

    text = log.read_text()
    assert log.parent == locations.log_dir
    assert log.name.startswith("test-")
    assert "# command: " in text
    assert "started as Bene\n" in text
    assert text.endswith("# exit code: 0\n")


def test_failing_game_reports_its_log(packages, tmp_path, locations, player):
    game = make_game(packages, tmp_path, command=game_script(tmp_path, "exit 3"))

    with pytest.raises(launch.LaunchError, match="code 3"):
        launch.run(game, player, NATIVE, locations)
