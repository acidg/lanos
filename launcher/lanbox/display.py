"""Native resolution and refresh rate of the primary display, read from KDE's screen
configuration (kscreen-doctor), which knows the primary output under Wayland."""

import json
import subprocess
from dataclasses import dataclass


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
            size = mode["size"]
            return Mode(size["width"], size["height"], round(mode["refreshRate"]))
    raise DisplayError(f"Display {primary['name']} has no current mode.")


def detect() -> Mode:
    try:
        result = subprocess.run(
            ["kscreen-doctor", "-j"], capture_output=True, text=True, check=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise DisplayError(f"Cannot read the display configuration: {error}") from None
    return parse_kscreen(result.stdout)
