extends SceneTree

const Telemetry = preload("res://scripts/online/story_milestone_telemetry.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var expected := {
		"res://scenes/world/village/imported_village/village_playable.tscn": "village",
		"res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn": "royal_gardens",
		"res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn": "royal_gate",
		"res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn": "willow_fields",
		"res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn": "elderwood_grove",
		"res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn": "forsaken_ruins",
		"res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn": "ruined_tower"
	}
	var failures: Array[String] = []
	for scene_path in expected:
		if Telemetry.milestone_for_scene(scene_path) != expected[scene_path]:
			failures.append("scene milestone mapping: " + scene_path)
	if Telemetry.milestone_for_scene("res://scenes/main.tscn") != "":
		failures.append("unrelated scene must not produce a story milestone")
	if not Telemetry.should_record(true, "chapter_complete"):
		failures.append("authenticated chapter completion must be accepted")
	if Telemetry.should_record(false, "village"):
		failures.append("unsigned play must not be recorded")
	if Telemetry.should_record(true, "unknown_milestone"):
		failures.append("unknown milestone must not be recorded")
	for script_path in [
		"res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd",
		"res://scripts/world/six_zone_reverie/fast_travel.gd",
		"res://scripts/world/tutorial_prologue/training_ground_layout.gd",
		"res://scripts/world/six_zone_reverie/revienna_encounter.gd"
	]:
		var loaded_script: Script = load(script_path)
		if loaded_script == null or not loaded_script.can_instantiate():
			failures.append("could not compile milestone hook: " + script_path)
	if failures.is_empty():
		print("PASS story milestone telemetry mappings and signed-in gating")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
