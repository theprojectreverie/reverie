extends SceneTree

const MAPS := [
	"res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn"
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var state := root.get_node("GameState")
	var graphics := root.get_node("GraphicsSettings")
	var audio := root.get_node("AudioDirector")
	state.quest_domain.flags["tutorial_complete"] = true
	state.quest_domain.flags["village_gerald_defeated"] = true
	graphics.apply_preferences(0, 60)
	var baseline_nodes := 0
	var baseline_orphans := 0
	var baseline_memory := 0.0
	for cycle in range(4):
		for path in MAPS:
			var previous: WeakRef = weakref(current_scene) if is_instance_valid(current_scene) else null
			assert(change_scene_to_file(path) == OK)
			await scene_changed
			for frame in range(3):
				await process_frame
			assert(previous == null or previous.get_ref() == null)
			var router := current_scene.get_node("OverlayRouter")
			for id in ["inventory", "quests", "settings"]:
				assert(router.open_screen(id))
				var overlay: WeakRef = weakref(router.active_overlay)
				await process_frame
				router.close_active()
				for frame in range(3):
					await process_frame
				assert(overlay.get_ref() == null and router.active_overlay == null)
			var map = current_scene.get_node("UI/HUD/Minimap")
			assert(map._zone_art.size() > 0)
			assert(map._zone_art[0].size() == 8)
		await create_timer(0.6).timeout
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var memory := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		if cycle == 0:
			baseline_nodes = nodes
			baseline_orphans = orphans
			baseline_memory = memory
		print("SESSION_MEMORY cycle=", cycle + 1, " nodes=", nodes, " orphans=", orphans, " engine_MiB=", memory)
		assert(nodes <= baseline_nodes + 10 and orphans <= baseline_orphans + 2)
		print("SESSION_MEMORY_DELTA_MiB ", memory - baseline_memory)
	current_scene.queue_free()
	await process_frame
	audio.stop_all_audio_immediately()
	await create_timer(0.5).timeout
	print("SESSION_MEMORY_SMOKE_PASS maps=8 overlays=24")
	quit()
