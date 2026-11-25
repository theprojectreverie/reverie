class_name GeraldCinematicSequenceComponent
extends Node
## Loads Gerald's editor-authored boss-story shot list.

const SEQUENCE_PATH := "res://assets/cinematics/gerald_boss/gerald_boss_sequence.json"

var shots: Array[Dictionary] = []

func load_sequence() -> bool:
	shots.clear()
	if not FileAccess.file_exists(SEQUENCE_PATH):
		push_error("[GeraldSequence] Missing sequence data: " + SEQUENCE_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEQUENCE_PATH))
	if not parsed is Dictionary:
		push_error("[GeraldSequence] Sequence JSON must contain an object.")
		return false
	for item in parsed.get("shots", []):
		if item is Dictionary:
			shots.append(item)
	if shots.is_empty():
		push_error("[GeraldSequence] No authored shots were found.")
		return false
	return true
