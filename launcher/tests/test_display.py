import json
from pathlib import Path

import pytest

from lanbox.display import DisplayError, Mode, parse_kscreen


def output(name, priority, current, modes, enabled=True):
    return {
        "name": name,
        "enabled": enabled,
        "priority": priority,
        "currentModeId": current,
        "modes": [
            {"id": mode_id, "size": {"width": w, "height": h}, "refreshRate": rate}
            for mode_id, w, h, rate in modes
        ],
    }


def kscreen(*outputs):
    return json.dumps({"outputs": list(outputs)})


def test_current_mode_of_primary_output_is_used():
    text = kscreen(
        output("HDMI-A-1", 2, "1", [("1", 1920, 1080, 60.0)]),
        output("DP-1", 1, "7", [("6", 1920, 1080, 60.0), ("7", 2560, 1440, 143.86)]),
    )

    assert parse_kscreen(text) == Mode(2560, 1440, 144)


def test_output_of_a_real_laptop_is_parsed():
    text = (Path(__file__).parent / "kscreen-laptop.json").read_text()

    assert parse_kscreen(text) == Mode(1920, 1200, 60)


def test_disabled_outputs_are_ignored():
    text = kscreen(
        output("eDP-1", 1, "1", [("1", 1920, 1200, 60.0)], enabled=False),
        output("DP-1", 2, "2", [("2", 1280, 1024, 75.02)]),
    )

    assert parse_kscreen(text) == Mode(1280, 1024, 75)


def test_no_enabled_output_is_an_error():
    with pytest.raises(DisplayError):
        parse_kscreen(kscreen(output("DP-1", 0, "1", [("1", 800, 600, 60.0)], enabled=False)))
