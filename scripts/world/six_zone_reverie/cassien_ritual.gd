extends Interactable
const QUEST := "cassien_resurrection"
const PREP := "forsaken_braziers"
const objective_id := "cassien_altar"
var chosen := false
var owns_dialogue := false
var awakened := false
var engaged := false
var coop_hp := 600.0
var coop_max_hp := 600.0
var coop_warning: Dictionary = {}
var coop_guarded := false
var coop_defeated := false
var coop_panel: Control
var coop_feedback := "Stand against Cassien together."
var ritual_cues: Dictionary = {}
var ritual_view_active := false
var ritual_clip_active := false
var ritual_departure_tween: Tween
var ritual_departing := false
signal departure_finished
var previous_hud_visible := true
var previous_dim := Color.WHITE
const GROUP_ID := "cassien_encounter"
@onready var zone := get_parent()
@onready var dialogue := zone.get_node("UI/Dialogue") as DialogueBox
@onready var label: Label = $ObjectiveLabel
@onready var cassien_visual: AnimatedSprite2D = $CassienVisual
@onready var departure_visual: AnimatedSprite2D = zone.get_node("ReviennaDeparture")
@onready var departure_route: Node2D = zone.get_node("ReviennaDepartureRoute")
@onready var ritual_camera: Camera2D = zone.get_node("RitualCamera")
@onready var ritual_visual: AnimatedSprite2D = zone.get_node("RaviennaCourtyard/RaviennaStoneTomb/ReviennaRitualVisual")
@onready var tomb_animation: AnimationPlayer = zone.get_node("RaviennaCourtyard/RaviennaStoneTomb/RitualAnimation")
func _ready() -> void:
	super._ready()
	interaction_radius = 150.0
	add_to_group("quest_exploration_targets")
	add_to_group("world_minimap_npcs")
	EventBus.quest_updated.connect(_refresh)
	dialogue.choice_selected.connect(_choice)
	dialogue.closed.connect(_closed)
	dialogue.node_shown.connect(_ritual_cue)
	ritual_visual.animation_finished.connect(_on_ritual_clip_finished)
	departure_visual.frame_changed.connect(_on_departure_step)
	get_viewport().size_changed.connect(_layout_ritual_view)
	EventBus.battle_finished.connect(_battle_finished)
	zone.get_node("CombatRouter").combat_closed.connect(_combat_closed)
	_refresh()
	if not _is_coop() and (GameState.quest_domain.quest_step_index(QUEST) > 0 or GameState.quest_domain.quest_state(QUEST) == "complete"):
		awakened = true
		cassien_visual.pause()
		cassien_visual.animation = &"awakening"
		cassien_visual.frame = cassien_visual.sprite_frames.get_frame_count(&"awakening") - 1
func _is_coop() -> bool:
	return not MultiplayerGateway.standalone_expedition_id.is_empty() and MultiplayerGateway.standalone_expedition_region == "six_zone_forsaken_ruins"

func refresh_shared_objective() -> void:
	var sync = zone.get_node_or_null("CoopWorldSync")
	var ritual_ready: bool = sync != null and sync.next_exploration_objective() == "cassien_resurrection"
	if coop_defeated:
		global_position = zone.get_node("CassienTombPosition").global_position
	cassien_visual.show()
	enabled = not engaged and not owns_dialogue and (not coop_defeated or ritual_ready)
	prompt = "Begin resurrection" if coop_defeated else "Speak to Cassien"
	label.text = prompt
	label.visible = enabled

func _refresh(_id: String = "") -> void:
	if _is_coop():
		refresh_shared_objective()
		return
	var state := GameState.quest_domain.quest_state(QUEST)
	var step := GameState.quest_domain.quest_step_index(QUEST)
	if step > 0 or state == "complete":
		global_position = zone.get_node("CassienTombPosition").global_position
	enabled = state == "active" and (step == 0 or GameState.quest_domain.quest_state(PREP) == "complete") and MultiplayerGateway.standalone_expedition_id.is_empty()
	prompt = "Speak to Cassien" if step == 0 else "Begin resurrection"
	label.text = prompt
	label.visible = enabled
	cassien_visual.visible = MultiplayerGateway.standalone_expedition_id.is_empty()
func interact() -> void:
	if not can_interact() or owns_dialogue or engaged or ritual_departing or dialogue.visible:
		return
	var player := zone.get("checkpoint_player") as Player
	if player == null or not player.input_enabled or player.network_recovery_paused or player.global_position.distance_to(global_position) > interaction_radius:
		return
	chosen = false
	ritual_cues.clear()
	owns_dialogue = true
	zone.set_meta("cassien_ritual_active", true)
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	TouchInput.release()
	if not awakened:
		awakened = true
		cassien_visual.play(&"awakening")
		await cassien_visual.animation_finished
		if not is_inside_tree() or not owns_dialogue:
			return
	if (not coop_defeated if _is_coop() else GameState.quest_domain.quest_step_index(QUEST) == 0):
		dialogue.open("cassien_meeting")
	else:
		_begin_ritual_view()
		dialogue.open("cassien_ritual")
func _choice(id: String, choice: Dictionary) -> void:
	if owns_dialogue:
		chosen = (id == "cassien_meeting" and str(choice.get("text")) == "I will help you prepare the ritual.") or (id == "cassien_ritual" and str(choice.get("text")) == "Follow Ravienna to the tower")
func _closed(id: String) -> void:
	if not owns_dialogue:
		return
	owns_dialogue = false
	if id == "cassien_ritual" and chosen:
		# Keep the cinematic lock until Revienna has actually reached the road.
		chosen = false
		_depart_after_dialogue()
		return
	if id == "cassien_ritual":
		_reset_ritual_visual()
		_end_ritual_view()
		tomb_animation.stop()
		tomb_animation.play("RESET")
		tomb_animation.advance(0)
	zone.remove_meta("cassien_ritual_active")
	if chosen and id == "cassien_meeting":
		chosen = false
		engaged = true
		_begin_battle.call_deferred()
		return

	chosen = false
	var player := zone.get("checkpoint_player") as Player
	if is_instance_valid(player):
		player.input_enabled = true
	_refresh()

func _begin_battle() -> void:
	if _is_coop():
		_open_coop_panel()
		return
	EventBus.encounter_requested.emit(GROUP_ID, self)
	if zone.get_node("CombatRouter").active_combat == null:
		engaged = false
		_resume_after_battle()

func _open_coop_panel() -> void:
	if coop_defeated:
		engaged = false
		_resume_after_battle()
		return
	if is_instance_valid(coop_panel):
		return
	coop_panel = preload("res://scenes/ui/components/coop_cassien_battle.tscn").instantiate()
	zone.get_node("UI/Combat").add_child(coop_panel)
	coop_panel.call("apply_state", coop_hp, false, false)
	var box = coop_panel.get_node("Center/Panel/Content")
	box.get_node("Attack").pressed.connect(_coop_strike)
	box.get_node("Guard").pressed.connect(_coop_guard)
	box.get_node("Leave").pressed.connect(_close_coop_panel)
	zone.set_meta("coop_boss_panel_open", true)
	var player := zone.get("checkpoint_player") as Player
	if is_instance_valid(player):
		player.input_enabled = false
		player.velocity = Vector2.ZERO
	_update_coop_panel()

func _coop_strike() -> void:
	if not coop_defeated and is_instance_valid(coop_panel) and not coop_panel.get_node("Center/Panel/Content/Attack").disabled:
		MultiplayerGateway.request_monster_attack(GROUP_ID)

func _coop_guard() -> void:
	if is_instance_valid(coop_panel) and not coop_panel.get_node("Center/Panel/Content/Guard").disabled:
		MultiplayerGateway.request_monster_attack(GROUP_ID, true)

func apply_coop_guard_confirmation(event: Dictionary) -> void:
	var sync = zone.get_node_or_null("CoopWorldSync")
	if sync != null and str(event.get("playerId", "")) == sync.local_player_id and not coop_warning.is_empty() and int(event.get("resolveAt", 0)) == int(coop_warning.get("resolveAt", -1)):
		coop_guarded = true
		_update_coop_panel()

func _close_coop_panel() -> void:
	if is_instance_valid(coop_panel):
		coop_panel.queue_free()
	coop_panel = null
	zone.remove_meta("coop_boss_panel_open")
	engaged = false
	_resume_after_battle()

func apply_coop_boss_state(state: Dictionary, live: bool = false) -> void:
	coop_max_hp = maxf(1.0, float(state.get("maxHp", 600)))
	coop_hp = clampf(float(state.get("hp", coop_max_hp)), 0.0, coop_max_hp)
	coop_defeated = coop_hp <= 0.0
	if not awakened and not owns_dialogue:
		awakened = true
		cassien_visual.stop()
		cassien_visual.animation = &"awakening"
		cassien_visual.frame = cassien_visual.sprite_frames.get_frame_count(&"awakening") - 1
	var counter = state.get("counterattack")
	var warning = state.get("warning")
	var next_warning: Dictionary = warning if warning is Dictionary else {}
	if int(next_warning.get("resolveAt", -1)) != int(coop_warning.get("resolveAt", -1)):
		coop_guarded = false
	coop_warning = next_warning
	coop_guarded = coop_guarded or bool(coop_warning.get("guardAcknowledged", false))
	var special := str(state.get("resolvedSpecial", "")) if state.get("resolvedSpecial") != null else ""
	if is_instance_valid(coop_panel):
		coop_panel.call("apply_state", coop_hp, counter is Dictionary, live, special)
	if live and counter is Dictionary:
		var sync = zone.get_node_or_null("CoopWorldSync")
		coop_feedback = "%s took %d damage." % ["You" if sync != null and str(counter.get("playerId","")) == sync.local_player_id else "Your ally", int(counter.get("damage",0))]
	_refresh()
	_update_coop_panel()

func _process(_delta: float) -> void:
	if is_instance_valid(coop_panel):
		_update_coop_panel()

func _update_coop_panel() -> void:
	if not is_instance_valid(coop_panel):
		return
	var box = coop_panel.get_node("Center/Panel/Content")
	box.get_node("Health").max_value = coop_max_hp
	box.get_node("Health").value = coop_hp
	box.get_node("Phase").text = "Victory" if coop_defeated else "%d / %d HP" % [int(coop_hp), int(coop_max_hp)]
	var sync = zone.get_node_or_null("CoopWorldSync")
	var ready: bool = sync != null and sync._snapshot_ready and MultiplayerGateway.is_connected_to_lobby()
	box.get_node("Attack").disabled = not ready or coop_defeated or not coop_warning.is_empty()
	var guard: Button = box.get_node("Guard")
	var targeted: bool = sync != null and not coop_warning.is_empty() and str(coop_warning.get("targetId", "")) == sync.local_player_id
	guard.visible = not coop_warning.is_empty() and not coop_defeated
	guard.disabled = not ready or not targeted or coop_guarded or coop_defeated
	guard.text = "Defended" if targeted and coop_guarded else "Defend"
	box.get_node("Warning").text = "Shared battle - strikes and retaliation are confirmed by the server." if coop_warning.is_empty() else "%s incoming! %s" % [str(coop_warning.get("name", "Special")), "Guard confirmed." if targeted and coop_guarded else "Defend now." if targeted else "Your ally is targeted."]
	var player := zone.get("checkpoint_player") as Player
	if is_instance_valid(player):
		var world_combat = player.get_node("WorldCombatComponent")
		box.get_node("PlayerHealth").max_value = world_combat.max_hp
		box.get_node("PlayerHealth").value = world_combat.hp
		box.get_node("PlayerHealthLabel").text = "Your health: %d / %d" % [int(world_combat.hp), int(world_combat.max_hp)]
	box.get_node("CombatFeedback").text = "Reconnecting..." if not ready else "Victory - purify the three braziers." if coop_defeated else coop_feedback

func _battle_finished(result: Dictionary) -> void:
	if not engaged or str(result.get("group_id", "")) != GROUP_ID:
		return
	if bool(result.get("victory", false)) and GameState.quest_domain.quest_state(QUEST) == "active" and GameState.quest_domain.quest_step_index(QUEST) == 0:
		GameState.quest_domain.flags["cassien_defeated"] = true
		GameState.quest_domain.advance_quest(QUEST)
		GameState.quest_domain.start_quest(PREP)
		GameState.queue_save()

func _combat_closed() -> void:
	if engaged:
		engaged = false
		_resume_after_battle()

func _resume_after_battle() -> void:
	var player := zone.get("checkpoint_player") as Player
	if is_instance_valid(player):
		player.input_enabled = true
	_refresh()

func _ritual_cue(id: String, node_id: String) -> void:
	if not owns_dialogue or id != "cassien_ritual" or ritual_cues.has(node_id):
		return
	ritual_cues[node_id] = true
	match node_id:
		"greet":
			_reset_ritual_visual()
			ritual_visual.show()
			AudioDirector.play_variant("magic_charge", -8.0)
		"awakening":
			tomb_animation.play("awakening")
			AudioDirector.play_variant("magic_impact", -7.0)
			_play_ritual_clip(&"resurrection")
		"fracture":
			dialogue.get_node("DialoguePanel/ContentRow/Portrait").set_portrait_texture(preload("res://assets/portraits/summon/revienna_human_ritual.png"))
			tomb_animation.play("fracture")
			_play_ritual_clip(&"possession")
		"departure":
			ritual_clip_active = false
			_ritual_continue_button().disabled = false
			ritual_visual.pause()
			ritual_visual.animation = &"possession"
			ritual_visual.frame = 11
			# Hold the transformed pose while the final dialogue is read.
			ritual_visual.show()


func _on_departure_step() -> void:
	if ritual_departing and departure_visual.visible and departure_visual.is_playing() and departure_visual.frame in [2, 6]:
		AudioDirector.play_variant("stone_step", -12.0, 0.94)


func _depart_after_dialogue() -> void:
	ritual_departing = true
	ritual_clip_active = false
	departure_visual.global_position = ritual_visual.global_position
	departure_visual.show()
	ritual_visual.hide()
	for marker in departure_route.get_children():
		if not is_inside_tree():
			return
		var destination: Vector2 = marker.global_position
		var delta := destination - departure_visual.global_position
		var directions := [&"walk_e", &"walk_se", &"walk_s", &"walk_sw", &"walk_w", &"walk_nw", &"walk_n", &"walk_ne"]
		var sector := posmod(roundi(delta.angle() / (PI / 4.0)), 8)
		if departure_visual.animation != directions[sector] or not departure_visual.is_playing():
			departure_visual.play(directions[sector])
		var seconds := maxf(0.25, delta.length() / 215.0)
		ritual_departure_tween = create_tween().set_parallel(true).set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		ritual_departure_tween.tween_property(departure_visual, "global_position", destination, seconds)
		ritual_departure_tween.tween_property(ritual_camera, "global_position", destination + Vector2(0, 48), seconds)
		await ritual_departure_tween.finished
	ritual_departure_tween = null
	departure_visual.stop()
	departure_visual.hide()
	ritual_departing = false
	_reset_ritual_visual()
	_end_ritual_view()
	tomb_animation.play("RESET")
	tomb_animation.advance(0)
	zone.remove_meta("cassien_ritual_active")
	if _is_coop():
		MultiplayerGateway.request_exploration_objective("cassien_resurrection")
	elif GameState.quest_domain.quest_state(PREP) == "complete":
		GameState.quest_domain.advance_quest(QUEST)
		if GameState.quest_domain.complete_quest(QUEST):
			GameState.quest_domain.flags["ravienna_resurrected"] = true
			GameState.save_now()
	var player := zone.get("checkpoint_player") as Player
	if is_instance_valid(player):
		player.input_enabled = true
	_refresh()
	departure_finished.emit()


func _ritual_continue_button() -> Button:
	return dialogue.get_node("DialoguePanel/ContentRow/TextColumn/Footer/ContinueButton") as Button


func _play_ritual_clip(clip: StringName) -> void:
	ritual_clip_active = true
	var button := _ritual_continue_button()
	button.disabled = true
	ritual_visual.show()
	ritual_visual.modulate = Color.WHITE
	ritual_visual.play(clip)
	ritual_visual.set_frame_and_progress(0, 0.0)


func _on_ritual_clip_finished() -> void:
	if not ritual_clip_active or not owns_dialogue or not ritual_view_active:
		return
	ritual_clip_active = false
	if ritual_visual.animation == &"possession":
		dialogue.get_node("DialoguePanel/ContentRow/Portrait").set_portrait_texture(preload("res://assets/portraits/summon/ravienna.png"))
	_ritual_continue_button().disabled = false


func _reset_ritual_visual() -> void:
	ritual_clip_active = false
	if ritual_departure_tween != null and ritual_departure_tween.is_valid():
		ritual_departure_tween.kill()
	ritual_departure_tween = null
	ritual_visual.stop()
	ritual_visual.animation = &"resurrection"
	ritual_visual.frame = 0
	ritual_visual.modulate = Color.WHITE
	ritual_visual.hide()
	_ritual_continue_button().disabled = false

func _begin_ritual_view() -> void:
	if ritual_view_active:
		return
	ritual_view_active = true
	var hud := zone.get_node("UI/HUD") as Control
	var dim := dialogue.get_node("Dim") as ColorRect
	previous_hud_visible = hud.visible
	previous_dim = dim.color
	hud.hide()
	label.hide()
	dim.color = Color(0.01, 0.02, 0.04, 0.12)
	_layout_ritual_view()
	ritual_camera.enabled = true
	ritual_camera.make_current()


func _layout_ritual_view() -> void:
	if not ritual_view_active:
		return
	var viewport_size := get_viewport_rect().size
	var portrait := viewport_size.x / viewport_size.y < 0.85
	_set_ritual_portrait_layout(portrait)
	var zoom_factor := minf(2.35 if portrait else 1.18, viewport_size.x / (520.0 if portrait else 830.0))
	var vertical_framing := 320.0 if portrait else 100.0
	ritual_camera.zoom = Vector2.ONE * zoom_factor
	if not ritual_departing:
		ritual_camera.global_position = zone.get_node("RaviennaCourtyard/RaviennaStoneTomb").global_position + Vector2(0, vertical_framing / zoom_factor)


func _end_ritual_view() -> void:
	if not ritual_view_active:
		return
	ritual_view_active = false
	_set_ritual_portrait_layout(false)
	var hud := zone.get_node("UI/HUD") as Control
	var dim := dialogue.get_node("Dim") as ColorRect
	hud.visible = previous_hud_visible
	dim.color = previous_dim
	var player := zone.get("checkpoint_player") as Player
	if is_instance_valid(player):
		var player_camera := player.get_node("Camera2D") as Camera2D
		player_camera.make_current()
	ritual_camera.enabled = false

func _set_ritual_portrait_layout(active: bool) -> void:
	if dialogue.ritual_portrait_layout == active:
		return
	dialogue.ritual_portrait_layout = active
	var panel := dialogue.get_node("DialoguePanel") as PanelContainer
	var portrait := panel.get_node("ContentRow/Portrait") as Control
	var text_column := panel.get_node("ContentRow/TextColumn") as VBoxContainer
	var speaker := text_column.get_node("Header/SpeakerLabel") as Label
	var title := text_column.get_node("Header/NameLabel") as Label
	var body := text_column.get_node("TextLabel") as RichTextLabel
	var hint := text_column.get_node("Footer/HintLabel") as Label
	var button := text_column.get_node("Footer/ContinueButton") as Button
	panel.offset_top = -740.0 if active else -314.0
	panel.offset_bottom = -60.0 if active else -26.0
	portrait.custom_minimum_size = Vector2(280, 360) if active else Vector2(196, 248)
	speaker.add_theme_font_size_override("font_size", 48 if active else 21)
	body.add_theme_font_size_override("normal_font_size", 42 if active else 16)
	body.custom_minimum_size = Vector2(0, 210 if active else 104)
	button.custom_minimum_size = Vector2(410, 144) if active else Vector2(150, 36)
	if active:
		button.add_theme_font_size_override("font_size", 42)
	else:
		button.remove_theme_font_size_override("font_size")
	title.visible = not active
	hint.visible = not active