extends Node
const CP = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
const TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
var ok := true

func check(value: bool, label: String) -> void:
	print("LAYOUT_TEST ", label, "=", value)
	ok = ok and value

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var tree := get_tree()
	if not OS.get_user_data_dir().to_lower().contains("reverie_travel_test"):
		tree.quit(1)
		return
	var runner := Node.new()
	tree.root.add_child(runner)
	reparent(runner)
	GameState.quest_domain.flags["tutorial_complete"] = true
	GameState.quest_domain.flags[TRAVEL.FLAG] = CP.SCENES.keys()
	tree.change_scene_to_file(CP.SCENES["StandaloneZone01"])
	await tree.scene_changed
	await tree.process_frame
	var zone := tree.current_scene
	var minimap := zone.get_node("UI/HUD/Minimap") as Minimap
	for dimensions in [Vector2i(720,1280), Vector2i(852,393), Vector2i(1280,720)]:
		tree.root.size = dimensions
		for frame in range(5):
			await tree.process_frame
		minimap.get_node("TravelButton").pressed.emit()
		for frame in range(5):
			await tree.process_frame
		var panel := zone.find_child("FastTravelPanel", true, false)
		check(panel != null, "opens_"+str(dimensions))
		if panel == null:
			continue
		panel._select("StandaloneZone02")
		await tree.process_frame
		await RenderingServer.frame_post_draw
		var viewport := tree.root.get_visible_rect()
		var confirm := panel.get_node("Confirm") as Button
		var scroll := panel.get_node("Body/Scroll") as ScrollContainer
		var preview := panel.get_node("Body/Preview") as Control
		var close := zone.find_child("CloseButton", true, false) as Button
		check(viewport.encloses(confirm.get_global_rect()), "confirm_in_bounds_"+str(dimensions))
		check(scroll.size.y > 100, "scroll_usable_"+str(dimensions))
		check(not confirm.disabled, "destination_select_"+str(dimensions))
		check(not preview.visible and panel.get_node("Body/Scroll/Destinations").get_child_count() == 7, "all_zones_in_grid_"+str(dimensions))
		print("LAYOUT_SIZE logical=",viewport.size," panel=",panel.size," scroll=",scroll.size," confirm=",confirm.get_global_rect())
		tree.root.get_texture().get_image().save_png("user://travel_layout_%sx%s.png" % [dimensions.x, dimensions.y])
		zone.get_node("OverlayRouter").close_active()
		await tree.process_frame
		check(minimap.get_rect().size.x >= 60 and minimap.get_node("TravelButton").visible, "minimap_restored_"+str(dimensions))
	print("FAST_TRAVEL_LAYOUT_PASS=",ok)
	tree.quit(0 if ok else 1)
