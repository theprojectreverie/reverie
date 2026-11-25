#!/usr/bin/env python3
"""Read-only frame registration audit for the Mossling idle preview."""
from pathlib import Path
from PIL import Image
import hashlib
PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "assets/enemies/mossling/idle_pass_02/mossling_idle_8dir_4f_96x128.png"
DIRECTIONS = ("down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left")
W, H, FRAMES = 96, 128, 4

def main():
    im = Image.open(SOURCE).convert("RGBA")
    expected = (W * FRAMES, H * len(DIRECTIONS))
    if im.size != expected:
        print(f"FAIL: {im.size}, expected {expected}")
        return 1
    print(f"Source: {SOURCE.relative_to(PROJECT)}; canvas={im.size}")
    ok = True
    for row, direction in enumerate(DIRECTIONS):
        cells, seen = [], {}
        for col in range(FRAMES):
            frame = im.crop((col*W,row*H,(col+1)*W,(row+1)*H))
            bounds = frame.getchannel("A").getbbox()
            digest = hashlib.sha256(frame.tobytes()).hexdigest()[:12]
            prior = seen.get(digest)
            seen[digest] = col
            if bounds is None:
                cells.append(f"f{col}:EMPTY"); ok = False; continue
            x0,y0,x1,y1 = bounds
            item = f"f{col}:bbox=({x0},{y0},{x1},{y1})"
            if prior is not None:
                item += f" DUPLICATE_OF_{prior}"; ok = False
            cells.append(item)
        print(f"{row} {direction}: " + " | ".join(cells))
    print("RESULT: " + ("PASS" if ok else "REVIEW REQUIRED"))
    print("Read-only; source image not modified.")
    return 0 if ok else 2
if __name__ == "__main__":
    raise SystemExit(main())
