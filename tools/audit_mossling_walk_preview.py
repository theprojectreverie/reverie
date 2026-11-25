#!/usr/bin/env python3
"""Read-only frame registration and duplicate audit for the Mossling walk preview."""
from pathlib import Path
from PIL import Image
import hashlib

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "assets/enemies/mossling/walk_pass_04/mossling_walk_8dir_6f_96x128.png"
DIRECTIONS = ("down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left")
FRAME_W, FRAME_H, FRAMES = 96, 128, 6


def main() -> int:
    image = Image.open(SOURCE).convert("RGBA")
    expected = (FRAME_W * FRAMES, FRAME_H * len(DIRECTIONS))
    if image.size != expected:
        print(f"FAIL: image is {image.size}; expected {expected}")
        return 1
    print(f"Source: {SOURCE.relative_to(PROJECT)}")
    print(f"Canvas: {image.size}; RGBA")
    all_ok = True
    for row, direction in enumerate(DIRECTIONS):
        entries = []
        hashes = {}
        for col in range(FRAMES):
            frame = image.crop((col * FRAME_W, row * FRAME_H,
                                (col + 1) * FRAME_W, (row + 1) * FRAME_H))
            alpha = frame.getchannel("A")
            bounds = alpha.getbbox()
            digest = hashlib.sha256(frame.tobytes()).hexdigest()[:12]
            duplicate = hashes.get(digest)
            hashes[digest] = col
            if bounds is None:
                entries.append(f"f{col}:EMPTY")
                all_ok = False
                continue
            x0, y0, x1, y1 = bounds
            entries.append(f"f{col}:bbox=({x0},{y0},{x1},{y1})")
            if duplicate is not None:
                entries[-1] += f" DUPLICATE_OF_{duplicate}"
                all_ok = False
        print(f"{row} {direction}: " + " | ".join(entries))
    print("RESULT: frame-level duplicate/empty check " + ("PASS" if all_ok else "REVIEW REQUIRED"))
    print("Read-only audit; source image and Godot preview resource were not modified.")
    return 0 if all_ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
