"""Native resolution and refresh rate of the primary display, read from KDE's screen
configuration (kscreen-doctor), which knows the primary output under Wayland."""

import json
import subprocess
from dataclasses import dataclass


# kscreen's Left, Right, Flipped90 and Flipped270: the output is turned by 90 degrees.
SIDEWAYS_ROTATIONS = {2, 8, 32, 128}


class DisplayError(Exception):
    pass


@dataclass(frozen=True)
class Mode:
    width: int
    height: int
    refresh: int


def parse_kscreen(text: str) -> Mode:
    """The current mode of the primary output in `kscreen-doctor -j` output."""
    outputs = [output for output in json.loads(text)["outputs"] if output["enabled"]]
    if not outputs:
        raise DisplayError("No display is enabled.")
    # Priority 1 is the primary output.
    primary = min(outputs, key=lambda output: output["priority"])
    for mode in primary["modes"]:
        if mode["id"] == primary["currentModeId"]:
            width, height = mode["size"]["width"], mode["size"]["height"]
            # Modes are in the panel's own orientation. Portrait panels such as the
            # Steam Deck's are turned to landscape, and games must fill the turned screen.
            if primary["rotation"] in SIDEWAYS_ROTATIONS:
                width, height = height, width
            return Mode(width, height, round(mode["refreshRate"]))
    raise DisplayError(f"Display {primary['name']} has no current mode.")


def detect() -> Mode:
    try:
        result = subprocess.run(
            ["kscreen-doctor", "-j"], capture_output=True, text=True, check=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise DisplayError(f"Cannot read the display configuration: {error}") from None
    return parse_kscreen(result.stdout)
