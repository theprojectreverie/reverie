from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
def update(rel,fn):
 f=p/rel;t=f.read_text(encoding='utf-8-sig');b=Path(str(f)+'.before_continue_reliability')
 if not b.exists(): shutil.copy2(f,b)
 f.write_text(fn(t),encoding='utf-8')
def save(t):
 a=t.index('func has_save()');b=t.index('## Validate',a)
 t=t[:a]+'''func has_save() -> bool:
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
	# Never discard a save just because another writer is replacing it.
	for path in [SAVE_PATH, SAVE_PATH + ".previous.tmp", SAVE_PATH + ".last_good"]:
		var data := _read_valid(path)
		if not data.is_empty():
			return data
	return {}


'''+t[b:]
 t=t.replace('var temp_path := SAVE_PATH + ".tmp"','var temp_path := SAVE_PATH + "." + str(OS.get_process_id()) + ".tmp"')
 t=t.replace('if had_previous and FileAccess.file_exists(SAVE_PATH + ".previous.tmp"):\n\t\tDirAccess.remove_absolute(previous_absolute)','if had_previous and FileAccess.file_exists(SAVE_PATH + ".previous.tmp"):\n\t\tvar good_path := ProjectSettings.globalize_path(SAVE_PATH + ".last_good")\n\t\tif not _read_valid(SAVE_PATH + ".previous.tmp").is_empty():\n\t\t\tDirAccess.copy_absolute(previous_absolute, good_path)\n\t\tDirAccess.remove_absolute(previous_absolute)')
 t=t.replace('[SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".previous.tmp"]','[SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".previous.tmp", SAVE_PATH + ".last_good"]')
 return t
update('scripts/core/save_service.gd',save)
def startup(t):
 t=t.replace('elif action in ["continue", "load"] and SaveService.has_save():\n\t\tvar data := SaveService.load_save()\n\t\tif not data.is_empty():\n\t\t\tGameState._load_from_dict(data)\n\t\tGameState.session_domain.loaded_from_save = true','elif action in ["continue", "load"]:\n\t\tvar data := SaveService.load_save()\n\t\tif data.is_empty():\n\t\t\tvar notice := AcceptDialog.new()\n\t\t\tnotice.title = "Save unavailable"\n\t\t\tnotice.dialog_text = "Your save could not be read. Please retry Continue. Progress has not been reset."\n\t\t\thost.add_child(notice)\n\t\t\tnotice.confirmed.connect(notice.queue_free)\n\t\t\tnotice.popup_centered()\n\t\t\treturn\n\t\tGameState._load_from_dict(data)\n\t\tGameState.session_domain.loaded_from_save = true')
 return t
update('scripts/game/components/main_startup_flow_component.gd',startup)
def persist(t):
 t=t.replace('state.flags = data.get("flags", {})','state.flags = data.get("flags", {})\n\tvar checkpoint: Variant = state.flags.get("six_zone_checkpoint", {})\n\tif checkpoint is Dictionary and str(checkpoint.get("zone", "")) in ["StandaloneZone01", "StandaloneZone02", "StandaloneZone03", "StandaloneZone04", "StandaloneZone05", "StandaloneZone06"]:\n\t\tstate.flags["tutorial_complete"] = true')
 return t
update('scripts/core/components/game_state_persistence_component.gd',persist)
# Avoid writing a fresh profile over an unreadable existing save at startup.
def life(t):
 t=t.replace('var active_player_id := ""','var active_player_id := ""\nvar save_recovery_blocked := false')
 t=t.replace('if state.profile.is_empty():\n\t\tnew_game()','if state.profile.is_empty():\n\t\tsave_recovery_blocked = SaveService.has_save()\n\t\tnew_game()',1)
 t=t.replace('if state == null or state.profile.is_empty():','if state == null or state.profile.is_empty() or save_recovery_blocked:',1)
 t=t.replace('func reset_progress() -> void:\n\tSaveService.delete_save()','func reset_progress() -> void:\n\tsave_recovery_blocked = false\n\tSaveService.delete_save()')
 t=t.replace('var data := SaveService.load_save()\n\tif data.is_empty():\n\t\tnew_game','var data := SaveService.load_save()\n\tsave_recovery_blocked = data.is_empty() and SaveService.has_save()\n\tif data.is_empty():\n\t\tnew_game')
 return t
update('scripts/core/components/game_state_lifecycle_component.gd',life)
print('Recovery, non-destructive Continue and checkpoint migration installed.')
