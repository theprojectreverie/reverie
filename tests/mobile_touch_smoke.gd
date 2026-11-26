extends Node
var ok := true
func check(value: bool, label: String) -> void:
	print("TOUCH ",label,"=",value)
	ok = ok and value
func touch(index: int, pos: Vector2, down: bool, canceled: bool=false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index=index
	event.position=pos
	event.pressed=down
	event.canceled=canceled
	return event
func _ready() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		get_tree().quit(2)
		return
	TouchInput.using_touch=true
	get_window().size=Vector2i(390,844)
	GameState.quest_domain.flags["tutorial_complete"]=true
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn").instantiate()
	add_child(zone)
	for i in range(5): await get_tree().process_frame
	var hud: HUD=zone.get_node("UI/HUD")
	var player: Player=zone.checkpoint_player
	var joystick: TouchJoystick=hud.joystick
	var combat=hud._touch_combat
	var world=player.get_node("WorldCombatComponent")
	hud._apply_responsive_layout()
	await get_tree().create_timer(0.15).timeout
	var rect:=hud.get_viewport_rect()
	print("TOUCH viewport ",rect," combat ",combat.get_global_rect()," joystick ",joystick.get_global_rect())
	check(combat.visible and joystick.visible,"mobile_controls_visible")
	check(not hud.get_node("PartyPanel").visible,"portrait_party_hidden")
	for button in combat.get_children():
		check(rect.encloses(button.get_global_rect()),"portrait_inside_"+button.name)
		check(button.size.y>=44.0*rect.size.x/390.0-2,"portrait_target_"+button.name)
	check(not combat.get_global_rect().intersects(joystick.get_global_rect()),"portrait_separation")
	check(rect.encloses(joystick.get_global_rect()) and joystick.size.is_equal_approx(Vector2(170,170)),"portrait_joystick_bounds")
	check(not hud.get_node("ActionStack").get_global_rect().intersects(hud._minimap.get_global_rect()),"portrait_nav_map_separation")
	var center := joystick.get_global_rect().get_center()
	get_window().push_input(touch(7,center+Vector2(70,0),true),true)
	await get_tree().process_frame
	check(joystick._active_index==7 and TouchInput.move_vector.x>0.25,"viewport_touch_dispatch")
	get_window().push_input(touch(7,Vector2(0,0),false),true)
	check(joystick._active_index==-1 and TouchInput.move_vector==Vector2.ZERO,"viewport_outside_release")
	joystick._gui_input(touch(0,joystick.size*0.5+Vector2(3,0),true))
	check(TouchInput.move_vector==Vector2.ZERO,"deadzone")
	joystick._gui_input(touch(0,joystick.size*0.5,false))
	joystick._gui_input(touch(0,joystick.size*0.5+Vector2(70,0),true))
	check(TouchInput.move_vector.x>0.99,"full_strength")
	var dodge:=combat.get_node("Dodge") as Button
	dodge._input(touch(1,dodge.get_global_rect().get_center(),true))
	check(world.dodge_recovery>0 and TouchInput.move_vector.x>0.99,"second_thumb_dodge_while_moving")
	joystick._input(touch(0,Vector2(-50,-50),false,true))
	check(TouchInput.move_vector==Vector2.ZERO and joystick._active_index==-1,"outside_cancel")
	joystick._gui_input(touch(2,joystick.size*0.5+Vector2(70,0),true))
	player.input_enabled=false
	check(TouchInput.move_vector==Vector2.ZERO and joystick._active_index==-1,"dialogue_releases_capture")
	await get_tree().create_timer(0.15).timeout
	check(not combat.visible and not joystick.visible,"blocked_controls_hidden")
	player.input_enabled=true
	await get_tree().create_timer(0.15).timeout
	joystick._gui_input(touch(3,joystick.size*0.5+Vector2(70,0),true))
	player.set_network_recovery_paused(true)
	check(TouchInput.move_vector==Vector2.ZERO and joystick._active_index==-1,"reconnect_releases_capture")
	player.set_network_recovery_paused(false)
	await get_tree().create_timer(0.15).timeout
	joystick._gui_input(touch(4,joystick.size*0.5+Vector2(70,0),true))
	TouchInput._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(TouchInput.move_vector==Vector2.ZERO and joystick._active_index==-1,"focus_loss_release")
	world.dodge_time=0.0
	world.dodge_recovery=0.0
	world.cooldown=0.0
	world.skill_cooldown=0.0
	world.attack_pending=false
	await get_tree().create_timer(0.15).timeout
	var skill:=combat.get_node("Skill") as Button
	skill._input(touch(5,skill.get_global_rect().get_center(),true))
	check(world.skill_cooldown>0,"touch_skill")
	await get_tree().create_timer(1.0).timeout
	world.cooldown=0.0
	world.dodge_time=0.0
	world.attack_pending=false
	await get_tree().create_timer(0.15).timeout
	var attack:=combat.get_node("Attack") as Button
	get_window().push_input(touch(8,attack.get_global_rect().get_center(),true),true)
	check(world.cooldown>0,"viewport_touch_attack")
	get_window().push_input(touch(8,attack.get_global_rect().get_center(),false),true)
	MultiplayerGateway.standalone_expedition_id="qa-touch"
	await get_tree().create_timer(0.15).timeout
	check(skill.disabled,"coop_unsupported_skill_disabled")
	MultiplayerGateway.standalone_expedition_id=""
	var map: Minimap = hud._minimap
	var map_size := map.size
	var cached_id := map._art_viewport.get_instance_id()
	check(maxi(map._art_viewport.size.x, map._art_viewport.size.y) <= 1024, "mobile_preview_budget")
	map._toggle_collapse()
	await get_tree().process_frame
	check(map._collapsed and map.size.is_equal_approx(Vector2(60,28)), "map_collapsed")
	map._toggle_collapse()
	await get_tree().process_frame
	check(map.size.is_equal_approx(map_size) and map._art_viewport.get_instance_id() == cached_id, "map_restore_reuses_preview")
	map._toggle_collapse()
	get_window().size=Vector2i(844,390)
	for i in range(5): await get_tree().process_frame
	hud._apply_responsive_layout()
	await get_tree().create_timer(0.15).timeout
	rect=hud.get_viewport_rect()
	print("TOUCH landscape viewport ",rect," combat ",combat.get_global_rect()," joystick ",joystick.get_global_rect())
	for button in combat.get_children():
		check(rect.encloses(button.get_global_rect()),"landscape_inside_"+button.name)
	check(not combat.get_global_rect().intersects(joystick.get_global_rect()),"landscape_separation")
	check(rect.encloses(joystick.get_global_rect()) and joystick.size.is_equal_approx(Vector2(170,170)),"landscape_joystick_bounds")
	check(not hud.get_node("ActionStack").get_global_rect().intersects(hud._minimap.get_global_rect()),"landscape_nav_map_separation")
	check(map._collapsed and map.size.is_equal_approx(Vector2(60,28)), "map_rotation_preserves_collapse")
	map._toggle_collapse()
	await get_tree().process_frame
	print("MAP_RESTORE size=",map.size," rect=",map.get_global_rect()," expected=",map._expanded_size," viewport=",rect)
	check(map.size.is_equal_approx(Vector2(224,224)) and rect.encloses(map.get_global_rect()), "map_rotation_restore")
	zone.queue_free()
	for i in range(3): await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	print("TOUCH_PASS=",ok)
	get_tree().quit(0 if ok else 1)
