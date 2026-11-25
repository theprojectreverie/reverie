extends GeraldCinematicSequenceComponent

const BEFORE_FALL_PATH := "res://assets/cinematics/gerald_story/before_the_fall_sequence.json"

func load_sequence() -> bool:
    shots.clear()
    if not FileAccess.file_exists(BEFORE_FALL_PATH):
        push_error("[GeraldBeforeFall] Missing sequence: " + BEFORE_FALL_PATH)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BEFORE_FALL_PATH))
    if not parsed is Dictionary:
        return false
    for item in parsed.get("shots", []):
        if item is Dictionary:
            shots.append(item)
    return not shots.is_empty()