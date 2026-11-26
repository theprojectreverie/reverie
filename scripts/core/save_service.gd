extends Node
## Versioned local save service.
##
## IMPORTANT: this is a local, non-authoritative save used while the game is
## offline/single-player. Phase 12 replaces it with server-owned state. The
## format is intentionally plain JSON so it can be migrated and inspected.

var SAVE_PATH := "user://project_fantasy_save.json"
var BACKUP_PATH := "user://project_fantasy_save.backup.json"
const SAVE_VERSION := 1


const STORY_PREVIEW_PATH := "scenes/qa/gerald_story_preview.tscn"
var story_preview_mode := false

func _ready() -> void:
	# SaveService starts before GameState and AuthGateway. F6 supplies the
	# scene path as a positional command-line argument.
	for arg in OS.get_cmdline_args():
		if arg.replace("\\", "/").ends_with(STORY_PREVIEW_PATH):
			story_preview_mode = true
			OS.set_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE", "1")
			print("[GeraldPreview] Read-only preview: saves and remembered login disabled.")
			break

func has_save() -> bool:
	if story_preview_mode:
		return false
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_PATH + ".previous.tmp") or FileAccess.file_exists(SAVE_PATH + ".last_good")

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	return data if validate_save_data(data).is_empty() else {}

func load_save() -> Dictionary:
	if story_preview_mode:
		return {}
	# Never discard a save just because another writer is replacing it.
	for path in [SAVE_PATH, SAVE_PATH + ".previous.tmp", SAVE_PATH + ".last_good"]:
		var data := _read_valid(path)
		if not data.is_empty():
			return data
	# An invalid primary with no valid fallback must be preserved for recovery.
	if FileAccess.file_exists(SAVE_PATH) and _read_valid(SAVE_PATH).is_empty():
		_backup_corrupt_file()
	return {}


## Validate the typed containers GameState consumes before assigning them.
## Optional fields remain optional for backward compatibility with older saves.
func validate_save_data(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not data.has("profile") or typeof(data.get("profile")) != TYPE_DICTIONARY:
		errors.append("profile must be a dictionary")
	elif (data.get("profile") as Dictionary).is_empty():
		errors.append("profile must not be empty")
	for key in ["roster", "party"]:
		if data.has(key) and typeof(data[key]) != TYPE_ARRAY:
			errors.append("%s must be an array" % key)
	for key in ["inventory", "quests", "pity", "flags", "position", "region_positions", "stored_gear"]:
		if data.has(key) and typeof(data[key]) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % key)
	if data.has("gear_levels") and typeof(data["gear_levels"]) != TYPE_DICTIONARY:
		errors.append("gear_levels must be a dictionary")
	if data.has("roster") and typeof(data["roster"]) == TYPE_ARRAY:
		for i in data["roster"].size():
			if typeof(data["roster"][i]) != TYPE_DICTIONARY:
				errors.append("roster entry %d must be a dictionary" % i)
	if data.has("inventory") and typeof(data["inventory"]) == TYPE_DICTIONARY:
		var inventory: Dictionary = data["inventory"]
		for item_id in inventory.keys():
			var count: Variant = inventory[item_id]
			if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or float(count) < 0.0:
				errors.append("inventory count for %s must be a non-negative number" % str(item_id))
	return errors


func write_save(data: Dictionary) -> bool:
	# Multiplayer E2E clients load the local profile read-only. Multiple test
	# processes must never race to replace the user's single-player save file.
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1":
		return true
	data["version"] = SAVE_VERSION
	data["saved_at"] = Time.get_datetime_string_from_system()
	var text := JSON.stringify(data, "\t")
	var temp_path := SAVE_PATH + "." + str(OS.get_process_id()) + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveService] Could not open save file for writing.")
		return false
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("[SaveService] Could not flush the temporary save file (error %d)." % write_error)
		return false

	# Preserve the last known-good save until the new file is safely in place.
	# Renaming the old save away first also permits replacement on Windows,
	# where rename-over-existing is not consistently supported.
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var previous_absolute := ProjectSettings.globalize_path(SAVE_PATH + ".previous.tmp")
	var had_previous := FileAccess.file_exists(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH + ".previous.tmp"):
		if not had_previous:
			# Recover the last known-good file if the process was interrupted
			# after moving it aside but before installing the replacement.
			var recovery_error := DirAccess.rename_absolute(previous_absolute, save_absolute)
			if recovery_error != OK:
				push_error("[SaveService] Could not recover interrupted save replacement (error %d)." % recovery_error)
				return false
			had_previous = true
		else:
			# A current save exists, so this is only a stale backup from a prior
			# successful replacement whose cleanup was interrupted.
			DirAccess.remove_absolute(previous_absolute)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(save_absolute, previous_absolute)
		if backup_error != OK:
			push_error("[SaveService] Could not protect the previous save (error %d)." % backup_error)
			return false
	var error := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if error != OK:
		if had_previous:
			var restore_error := DirAccess.rename_absolute(previous_absolute, save_absolute)
			if restore_error != OK:
				push_error("[SaveService] CRITICAL: new save failed and previous save could not be restored (error %d)." % restore_error)
		push_error("[SaveService] Could not finalize save file (error %d)." % error)
		return false
	if had_previous and FileAccess.file_exists(SAVE_PATH + ".previous.tmp"):
		var good_path := ProjectSettings.globalize_path(SAVE_PATH + ".last_good")
		if not _read_valid(SAVE_PATH + ".previous.tmp").is_empty():
			DirAccess.copy_absolute(previous_absolute, good_path)
		DirAccess.remove_absolute(previous_absolute)
	return true


func delete_save() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1":
		return
	# A reset must remove interrupted-write artifacts too; otherwise the next
	# write could recover an old .previous.tmp and resurrect deleted progress.
	for path in [SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".previous.tmp", SAVE_PATH + ".last_good"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _backup_corrupt_file() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var source_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		var remove_old_error := DirAccess.remove_absolute(backup_absolute)
		if remove_old_error != OK:
			push_error("[SaveService] Could not replace the old corrupt-save backup (error %d); original save was kept." % remove_old_error)
			return
	var copy_error := DirAccess.copy_absolute(source_absolute, backup_absolute)
	if copy_error != OK:
		push_error("[SaveService] Could not back up the corrupt save (error %d); original save was kept." % copy_error)
		return
	var remove_error := DirAccess.remove_absolute(source_absolute)
	if remove_error != OK:
		push_error("[SaveService] Backup was created, but the corrupt save could not be removed (error %d)." % remove_error)

func select_player(player_id: String) -> void:
	var valid := RegEx.new()
	valid.compile("^[0-9a-fA-F-]{36}$")
	var suffix := "_" + player_id.to_lower() if valid.search(player_id) != null else ""
	SAVE_PATH = "user://project_fantasy_save" + suffix + ".json"
	BACKUP_PATH = "user://project_fantasy_save" + suffix + ".backup.json"