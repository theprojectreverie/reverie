#!/usr/bin/env python3
"""Non-destructive QA for authored Mossling animation strips.

Expected input: assets/enemies/mossling/animations/<state>/<direction>.png
This tool validates sources only. It never generates, edits, pads, or imports art.
"""
from pathlib import Path
from PIL import Image
import sys

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / "assets" / "enemies" / "mossling" / "animations"
DIRECTIONS = (
    "down", "down_right", "right", "up_right",
    "up", "up_left", "left", "down_left",
)
STATES = {
    "idle": 5,
    "walk": 16,
    "run": 16,
    "interact": 6,
    "attack": 6,
    "damage": 2,
    "victory": 8,
    "defeat": 6,
    "cast": 7,
}


def validate_strip(path: Path, frame_count: int) -> list[str]:
    problems: list[str] = []
    expected = (frame_count * 96, 128)
    try:
        with Image.open(path) as source:
            image = source.convert("RGBA")
            if image.size != expected:
                problems.append(f"size {image.size}, expected {expected}")
                return problems
            if image.getpixel((0, 0))[3] != 0:
                problems.append("top-left canvas pixel must be fully transparent")
            frame_hashes: set[bytes] = set()
            for index in range(frame_count):
                frame = image.crop((index * 96, 0, (index + 1) * 96, 128))
                if frame.getbbox() is None:
                    problems.append(f"frame {index} is fully transparent")
                digest = frame.tobytes()
                if digest in frame_hashes:
                    problems.append(f"frame {index} duplicates an earlier frame exactly")
                frame_hashes.add(digest)
    except Exception as exc:  # Pillow reports malformed and unreadable image data here.
        problems.append(f"cannot read PNG: {exc}")
    return problems


def main() -> int:
    errors: list[str] = []
    checked = 0
    missing = 0
    for state, frame_count in STATES.items():
        for direction in DIRECTIONS:
            path = ROOT / state / f"{direction}.png"
            if not path.is_file():
                errors.append(f"MISSING: {path.relative_to(PROJECT)}")
                missing += 1
                continue
            checked += 1
            for issue in validate_strip(path, frame_count):
                errors.append(f"INVALID: {path.relative_to(PROJECT)}: {issue}")

    print(f"Mossling source QA: {checked}/72 strips present; {missing} missing.")
    if errors:
        for error in errors:
            print(error)
        print("RESULT: NOT READY — no files were changed.")
        return 1
    print("RESULT: PASS — all strips satisfy dimensions, alpha, visibility and distinct-frame checks.")
    print("No files were changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
