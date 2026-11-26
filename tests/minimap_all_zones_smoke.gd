extends Node2D
const MAPS := [
	"res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn",
	"res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn",
	"res://scenes/world/village/imported_village/village_playable.tscn",
]
func _ready() -> void:
	var ok := true
	for path in MAPS:
		var zone := (load(path) as PackedScene).instantiate()
		# Keep the actual scene tree and minimap, without starting gameplay or writing save files.
		var ui := zone.get_node("UI")
		var map := ui.get_node("HUD/Minimap") as Minimap
		for child in zone.get_children():
			if child.name in ["ZoneUIBinding","OverlayRouter","CombatRouter","ReviennaEncounter","CassienRitual"]:
				zone.remove_child(child)
				child.free()
		zone.set_script(null)
		add_child(zone)
		await get_tree().process_frame
		var valid := map._six_zone == zone and map._zone_art.size() > 0 and map._zone_bounds.size.x > 0 and map._zone_bounds.size.y > 0
		print("MINIMAP ",zone.name," entries=",map._zone_art.size()," bounds=",map._zone_bounds," valid=",valid)
		ok = ok and valid
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var preview: Image = map._art_viewport.get_texture().get_image()
			var rendered := preview != null and not preview.is_empty() and preview.get_used_rect().size.x > 0
			print("MINIMAP_RENDER ",zone.name,"=",rendered)
			ok = ok and rendered
		if path == MAPS[0]:
			var prior_quality: int = GraphicsSettings.quality
			var prior_fps: int = GraphicsSettings.frame_limit
			GraphicsSettings.apply_preferences(0, 0)
			await get_tree().process_frame
			var low_size := map._art_viewport.size
			GraphicsSettings.apply_preferences(1, 60)
			await get_tree().process_frame
			var balanced_size := map._art_viewport.size
			GraphicsSettings.apply_preferences(2, 60)
			await get_tree().process_frame
			var high_size := map._art_viewport.size
			var quality_ok := maxi(low_size.x, low_size.y) <= 512 and maxi(balanced_size.x, balanced_size.y) <= 768 and high_size.x > balanced_size.x and map._zone_art.size() > 0
			print("MINIMAP_QUALITY ", low_size, " ", balanced_size, " ", high_size, " valid=", quality_ok)
			ok = ok and quality_ok
			GraphicsSettings.apply_preferences(prior_quality, prior_fps)
		map._toggle_collapse()
		ok = ok and map._collapsed and not map._canvas.visible
		map._toggle_collapse()
		ok = ok and not map._collapsed and map._canvas.visible
		map._request_full_map()
		ok = ok and not map._overview
		map._request_full_map()
		ok = ok and map._overview
		remove_child(zone)
		zone.free()
		await get_tree().process_frame
	print("ALL_MINIMAPS_TEST=",ok)
	get_tree().quit(0 if ok else 1)
