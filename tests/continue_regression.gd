extends Node
const CP = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS " + label if ok else "FAIL " + label)
	if not ok:
		failures += 1
func put(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
func _ready() -> void:
	var original: Dictionary = GameState._to_dict().duplicate(true)
	var d := original.duplicate(true)
	d["flags"] = {"tutorial_complete": true, "six_zone_checkpoint": {"zone":"StandaloneZone01","x":123.0,"y":456.0}}
	var base := "user://continue_regression_" + str(OS.get_process_id()) + ".json"
	SaveService.SAVE_PATH = base
	for i in range(10):
		put(base,d)
		var loaded := SaveService.load_save()
		GameState._load_from_dict(loaded)
		check(bool(GameState.flags.get("tutorial_complete",false)) and CP.resume_scene() == CP.SCENES["StandaloneZone01"], "Continue state " + str(i+1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base))
	put(base+".previous.tmp",d)
	check(SaveService.has_save() and SaveService.load_save().get("flags",{}).get("tutorial_complete",false),"Interrupted replacement recovery")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base+".previous.tmp"))
	put(base+".last_good",d)
	var f := FileAccess.open(base,FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	check(SaveService.load_save().get("flags",{}).get("tutorial_complete",false),"Corrupt primary recovery")
	var missing := d.duplicate(true)
	missing.flags.erase("tutorial_complete")
	GameState._load_from_dict(missing)
	check(bool(GameState.flags.get("tutorial_complete",false)),"Checkpoint repairs missing tutorial flag")
	var zone := Node2D.new()
	zone.name = "StandaloneZone01"
	add_child(zone)
	check(CP.restore(zone,Vector2.ZERO,&"") == Vector2(123,456),"Exact saved coordinates")
	check(CP.restore(zone,Vector2(9,9),&"ToPreviousZone") == Vector2(9,9),"Transfer spawn takes priority")
	for key in CP.SCENES:
		GameState.flags["six_zone_checkpoint"]["zone"] = key
		check(CP.resume_scene() == CP.SCENES[key],"Resume "+key)
	for suffix in ["",".last_good",".previous.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(base+suffix))
	GameState._load_from_dict(original)
	print("REGRESSION FAILURES: ",failures)
	get_tree().quit(failures)
