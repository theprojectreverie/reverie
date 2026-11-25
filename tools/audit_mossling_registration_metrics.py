#!/usr/bin/env python3
"""Read-only Mossling registration diagnostics: bbox, footline, center drift, height outliers."""
from pathlib import Path
from PIL import Image
import statistics
import sys

ROOT = Path(__file__).resolve().parents[1]
SHEETS = [
    ("idle", ROOT / "assets/enemies/mossling/idle_pass_02/mossling_idle_8dir_4f_96x128.png", 4),
    ("walk", ROOT / "assets/enemies/mossling/walk_pass_04/mossling_walk_8dir_6f_96x128.png", 6),
]
DIRECTIONS = ("down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left")
W, H = 96, 128

def main():
    failures = []
    for state, path, count in SHEETS:
        if not path.exists():
            print(f"NOT AVAILABLE: {path}")
            failures.append(state)
            continue
        image = Image.open(path).convert("RGBA")
        expected = (W * count, H * 8)
        if image.size != expected:
            print(f"FAIL {state}: sheet size {image.size}, expected {expected}")
            failures.append(state)
            continue
        print(f"\n[{state.upper()}] {path.relative_to(ROOT)} — {count} frames/direction")
        for row, direction in enumerate(DIRECTIONS):
            metrics = []
            for col in range(count):
                frame = image.crop((col*W, row*H, (col+1)*W, (row+1)*H))
                bounds = frame.getchannel("A").getbbox()
                if bounds is None:
                    metrics.append(None)
                    continue
                x0,y0,x1,y1 = bounds
                metrics.append({"height": y1-y0, "bottom": y1, "center": (x0+x1)/2, "bbox": bounds})
            valid = [m for m in metrics if m]
            if len(valid) != count:
                print(f"  {direction}: EMPTY FRAME(S)")
                failures.append(f"{state}/{direction}")
                continue
            heights = [m["height"] for m in valid]
            bottoms = [m["bottom"] for m in valid]
            centers = [m["center"] for m in valid]
            med_h = statistics.median(heights)
            med_b = statistics.median(bottoms)
            med_c = statistics.median(centers)
            h_out = [i for i,v in enumerate(heights) if abs(v-med_h) > max(18, med_h*0.22)]
            b_out = [i for i,v in enumerate(bottoms) if abs(v-med_b) > 8]
            c_span = max(centers)-min(centers)
            print(f"  {direction}: height={min(heights)}-{max(heights)}px; bottom={min(bottoms)}-{max(bottoms)}px; center-span={c_span:.1f}px; height-outliers={h_out or '-'}; baseline-outliers={b_out or '-'}")
            if h_out or b_out:
                failures.append(f"{state}/{direction}")
    print("\nRESULT: " + ("REVIEW FLAGS FOUND — inspect the listed rows in Godot; no pixels changed." if failures else "NO REGISTRATION FLAGS FOUND; visual review is still required."))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
