extends GeraldCinematicSequenceComponent
## Each chapter has its own authored ordered shot list.
@export_file("*.json") var sequence_path: String

func load_sequence() -> bool:
	shots.clear()
	if not FileAccess.file_exists(sequence_path):
		push_error("[CrimsonOath] Missing sequence: " + sequence_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sequence_path))
	if not parsed is Dictionary:
		return false
	for item in parsed.get("shots", []):
		if not item is Dictionary or not ResourceLoader.exists(str(item.get("image", "")), "Texture2D"):
			push_error("[CrimsonOath] Invalid shot in " + sequence_path)
			shots.clear()
			return false
		shots.append(item)
	return not shots.is_empty()
