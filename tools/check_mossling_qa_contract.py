#!/usr/bin/env python3
"""Compare Mossling QA source declarations with Godot animation catalog."""
from pathlib import Path
import ast
import re
import sys

PROJECT = Path(__file__).resolve().parents[1]
CATALOG = PROJECT / "scripts/world/character_animation_spec_catalog.gd"
QA = PROJECT / "tools/validate_mossling_art_sources.py"

def block(text, marker):
    start = text.find(marker)
    if start < 0:
        raise ValueError("missing declaration: " + marker)
    start = text.find("{", start)
    end = text.find("}", start)
    if start < 0 or end < 0:
        raise ValueError("malformed declaration: " + marker)
    return text[start + 1:end]

def pairs(text):
    return {int(k): v.strip().strip('"') for k, v in re.findall(r'(\d+)\s*:\s*("[^"]+"|[0-9.]+|true|false)', text)}

def main():
    catalog = CATALOG.read_text(encoding="utf-8")
    qa = QA.read_text(encoding="utf-8")
    importer = (PROJECT / "tools/import_mossling_spriteframes.gd").read_text(encoding="utf-8")
    runtime_validator = (PROJECT / "scripts/art/sprite_frames_actor_source.gd").read_text(encoding="utf-8")

    # Guard against a future importer silently introducing a second animation
    # contract instead of consuming the authoritative runtime catalog.
    importer_requirements = (
        "CharacterAnimator.EXTENDED_STATES",
        "CharacterAnimator.ALL_DIRECTIONS",
        "CharacterAnimator.state_name(state)",
        "CharacterAnimator.frame_count_for(state)",
        "CharacterAnimator.fps_for(state)",
        "CharacterAnimator.looping_for(state)",
        "CharacterAnimationSpecCatalog.DIRECTION_NAMES",
    )
    missing_importer = [item for item in importer_requirements if item not in importer]
    if missing_importer:
        print("FAIL: importer no longer consumes catalog contract:", missing_importer)
        return 1
    if "const STATE_FRAMES" in importer or "const STATE_FPS" in importer or "const STATE_LOOPING" in importer:
        print("FAIL: importer contains a duplicate timing table")
        return 1
    importer_art_checks = (
        "frame_region.get_used_rect()",
        "frame_region.get_data()",
        "duplicate_frames",
        "fully transparent frame(s)",
        "exact duplicate frame(s)",
    )
    missing_import_checks = [item for item in importer_art_checks if item not in importer]
    if missing_import_checks:
        print("FAIL: importer preflight is missing source-art safeguards:", missing_import_checks)
        return 1

    # The importer must validate the assembled SpriteFrames before its sole
    # production save call. This prevents a build-stage regression from
    # overwriting a previously valid world_sheet.tres.
    postbuild_checks = (
        "var build_errors: Array[String] = []",
        "frames.get_animation_names().size()",
        "frames.get_frame_count(animation_name)",
        "frames.get_animation_speed(animation_name)",
        "frames.get_animation_loop(animation_name)",
        "frames.get_frame_texture(animation_name, frame_index)",
        "build_errors.is_empty()",
        "Mossling import cancelled after build validation. No output was written.",
    )
    missing_postbuild = [item for item in postbuild_checks if item not in importer]
    if missing_postbuild:
        print("FAIL: importer is missing post-build validation:", missing_postbuild)
        return 1
    save_token = "ResourceSaver.save(frames, OUTPUT)"
    if importer.count(save_token) != 1:
        print("FAIL: importer must have exactly one production save call")
        return 1
    if importer.index("build_errors.is_empty()") > importer.index(save_token):
        print("FAIL: production save occurs before post-build validation")
        return 1

    qa_art_checks = (
        "frame_hashes: set[bytes]",
        "frame.getbbox()",
        "duplicates an earlier frame exactly",
        "top-left canvas pixel must be fully transparent",
    )
    missing_qa_checks = [item for item in qa_art_checks if item not in qa]
    if missing_qa_checks:
        print("FAIL: Python QA is missing source-art safeguards:", missing_qa_checks)
        return 1

    # The runtime registration gate must validate the same exact count, frame
    # count, FPS, loop flag, and canvas dimensions as the importer produces.
    validator_requirements = (
        "CharacterAnimator.EXTENDED_STATES.size() * CharacterAnimator.ALL_DIRECTIONS.size()",
        "CharacterAnimator.frame_count_for(s)",
        "CharacterAnimator.fps_for(s)",
        "CharacterAnimator.looping_for(s)",
        "get_animation_speed(anim)",
        "get_animation_loop(anim)",
        "get_frame_texture(anim, i)",
        "tex.get_width()",
        "tex.get_height()",
    )
    missing_validator = [item for item in validator_requirements if item not in runtime_validator]
    if missing_validator:
        print("FAIL: runtime validator is missing production contract checks:", missing_validator)
        return 1

    frames = {k: int(v) for k, v in pairs(block(catalog, "const STATE_FRAMES")).items()}
    fps = {k: float(v) for k, v in pairs(block(catalog, "const STATE_FPS")).items()}
    loops = {k: v == "true" for k, v in pairs(block(catalog, "const STATE_LOOPING")).items()}
    names = pairs(block(catalog, "const EXTENDED_STATE_NAMES"))
    directions = pairs(block(catalog, "const DIRECTION_NAMES"))
    qa_state_match = re.search(r"STATES\s*=\s*\{(.*?)\}", qa, re.S)
    qa_dir_match = re.search(r"DIRECTIONS\s*=\s*\((.*?)\)", qa, re.S)
    if not qa_state_match or not qa_dir_match:
        print("FAIL: QA state or direction declaration missing")
        return 1
    qa_states = {name: int(count) for name, count in re.findall(r'"([^"]+)"\s*:\s*(\d+)', qa_state_match.group(1))}
    qa_directions = re.findall(r'"([^"]+)"', qa_dir_match.group(1))
    expected_frames = {names[k]: frames.get(k, 7 if k == 8 else None) for k in names}
    expected_directions = [directions[k] for k in range(8)]
    if qa_states != expected_frames:
        print("FAIL: frame-count mismatch", qa_states, expected_frames)
        return 1
    if qa_directions != expected_directions:
        print("FAIL: direction-order mismatch", qa_directions, expected_directions)
        return 1
    if len(fps) != 8 or len(loops) != 8 or len(names) != 9:
        print("FAIL: unexpected catalog dimensions")
        return 1

    # Pin the intended timing contract so an accidental catalog edit cannot
    # silently alter all imported art playback while parity still appears valid.
    expected_core_frames = {
        0: 5, 1: 16, 2: 16, 3: 6,
        4: 6, 5: 2, 6: 8, 7: 6,
    }
    expected_fps = {
        0: 9.0, 1: 12.0, 2: 16.0, 3: 12.0,
        4: 15.0, 5: 12.0, 6: 12.0, 7: 10.0,
    }
    expected_directions_by_index = {
        0: "down", 1: "down_right", 2: "right", 3: "up_right",
        4: "up", 5: "up_left", 6: "left", 7: "down_left",
    }
    if frames != expected_core_frames:
        print("FAIL: core frame-count contract changed", frames, expected_core_frames)
        return 1
    if directions != expected_directions_by_index:
        print("FAIL: direction index contract changed", directions, expected_directions_by_index)
        return 1
    expected_loops = {
        0: True, 1: True, 2: True, 3: False,
        4: False, 5: False, 6: False, 7: False,
    }
    if fps != expected_fps:
        print("FAIL: core FPS contract changed", fps, expected_fps)
        return 1
    if loops != expected_loops:
        print("FAIL: core loop contract changed", loops, expected_loops)
        return 1
    if names.get(8) != "cast":
        print("FAIL: additive state 8 must remain named cast")
        return 1
    cast_contract = (
        "const CAST_STATE := 8",
        "const CAST_FRAMES := 7",
        "const CAST_FPS := 12.0",
        "const CAST_LOOPING := false",
    )
    missing_cast = [item for item in cast_contract if item not in catalog]
    if missing_cast:
        print("FAIL: additive cast timing contract changed:", missing_cast)
        return 1

    print("PASS: source QA frame counts and direction order match the Godot catalog.")
    print("PASS: core FPS/loop timing and additive cast contract match expected values.")
    print("Importer, source QA and runtime validator safeguards are present.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
