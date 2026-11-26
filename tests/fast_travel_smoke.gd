extends Node
const TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
const CP = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
const TRANSFER = preload("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
var ok := true

func check(value: bool, label: String) -> void:
	print("TRAVEL_TEST ", label, "=", value)
	ok = ok and value

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("TRAVEL_TEST_DATA_DIR ", OS.get_user_data_dir())
	if not OS.get_user_data_dir().to_lower().contains("reverie_travel_test"):
		push_error("Test must run in an isolated save directory")
		get_tree().quit(1)
		return
	var tree := get_tree()
	var runner := Node.new()
	tree.root.add_child(runner)
	reparent(runner)
	GameState.quest_domain.flags["tutorial_complete"] = true
	GameState.quest_domain.flags["village_gerald_defeated"] = true
	GameState.quest_domain.flags[TRAVEL.FLAG] = []
	TRANSFER.pending_arrival = &"FastTravel"
	tree.change_scene_to_file(CP.SCENES["StandaloneZone01"])
	await tree.scene_changed
	await tree.physics_frame
	var zone := tree.current_scene as Node2D
	check("StandaloneZone01" in TRAVEL.discovered(), "first_visit_unlock")
	check(TRAVEL.unavailable_reason(zone,"StandaloneZone02") == "Visit this area to unlock", "unvisited_locked")
	check(TRAVEL.unavailable_reason(zone,"StandaloneZone01") == "Current location", "same_zone_locked")
	var binding := zone.get_node("ZoneUIBinding")
	zone.get_node("UI/HUD/Minimap/TravelButton").pressed.emit()
	await tree.process_frame
	var panel := zone.find_child("FastTravelPanel", true, false)
	check(panel != null and panel.get_node("Body/Scroll/Destinations/StandaloneZone02").disabled, "map_panel_locked_button")
	zone.get_node("OverlayRouter").close_active()
	await tree.process_frame
	GameState.quest_domain.flags[TRAVEL.FLAG] = CP.SCENES.keys()
	var combat: Node = zone.get("checkpoint_player").get_node("WorldCombatComponent")
	combat.attack_pending = true
	check(TRAVEL.unavailable_reason(zone, "StandaloneVillage") == "Unavailable during combat", "world_combat_lock")
	combat.attack_pending = false
	combat.hurt_cooldown = 1.0
	check(not TRAVEL.travel(zone, "StandaloneVillage"), "hurt_lock")
	combat.hurt_cooldown = 0.0
	for id in CP.SCENES.keys():
		zone = tree.current_scene as Node2D
		if str(zone.name) != id:
			var moved := false
			if true:
				zone.get_node("UI/HUD/Minimap/TravelButton").pressed.emit()
				await tree.process_frame
				var travel_panel := zone.find_child("FastTravelPanel", true, false)
				travel_panel._select(id)
				check(not travel_panel.get_node("Confirm").disabled, "available_destination_confirm")
				if id == "StandaloneZone02" and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("user://fast_travel_review.png")
				travel_panel.get_node("Confirm").pressed.emit()
				moved = tree.root.has_node("FastTravelTransition")
				check(bool(zone.get_meta("fast_travel_visual_pending", false)), "departure_lock")
				check(not zone.get("checkpoint_player").input_enabled, "departure_input_lock")
			else:
				moved = TRAVEL.travel(zone,id)
			check(moved,"request_"+id)
			if not moved:
				break
			await tree.scene_changed
			if true:
				await tree.process_frame
				check(tree.root.has_node("FastTravelTransition"), "arrival_fade_survives_scene")
				check(not tree.current_scene.get("checkpoint_player").input_enabled, "arrival_input_lock")
				for frame in range(180):
					if not tree.root.has_node("FastTravelTransition"):
						break
					await tree.process_frame
				check(not tree.root.has_node("FastTravelTransition"), "transition_cleanup")
				check(tree.current_scene.get("checkpoint_player").input_enabled, "arrival_input_restored")
			await tree.physics_frame
			await tree.physics_frame
		zone = tree.current_scene as Node2D
		var player := zone.get("checkpoint_player") as CharacterBody2D
		var marker := zone.get_node("TransferPoints/FastTravelArrival") as Marker2D
		print("ARRIVAL_COORDS ",id," actual=",player.position," target=",marker.position)
		check(str(zone.name) == id and player.position.distance_to(marker.position) < 4.0,"arrival_"+id)
		check(CP.safe_position(zone, player.position), "safe_trigger_distance_"+id)
		var stone := zone.get_node("Waystone") as Interactable
		check(stone.global_position.distance_to(player.global_position) <= stone.interaction_radius, "waystone_reachable_"+id)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = stone.global_position
		query.collision_mask = 1
		var hits := zone.get_world_2d().direct_space_state.intersect_point(query, 16)
		var blocked := false
		for hit in hits:
			if not stone.is_ancestor_of(hit.collider):
				blocked = true
		check(not blocked, "waystone_site_clear_"+id)
		var interaction := player.get_node("InteractionComponent") as CharacterInteractionComponent
		interaction.refresh_nearest()
		check(interaction.get_current() == stone, "waystone_selected_by_player_"+id)
		check(interaction.try_interact(), "waystone_normal_interact_"+id)
		await tree.process_frame
		check(zone.find_child("FastTravelPanel", true, false) != null, "waystone_interaction_"+id)
		zone.get_node("OverlayRouter").close_active()
		await tree.process_frame
		var overlap := player.test_move(player.global_transform, Vector2(0.01,0.0))
		check(not overlap, "collision_clear_"+id)
		check(str(GameState.quest_domain.flags.get("six_zone_checkpoint",{}).get("zone","")) == id,"checkpoint_"+id)
		if DisplayServer.get_name() != "headless":
			for i in range(6):
				await tree.process_frame
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png("user://waystone_review_" + id + ".png")
	print("FAST_TRAVEL_TEST_PASS=",ok)
	tree.quit(0 if ok else 1)
