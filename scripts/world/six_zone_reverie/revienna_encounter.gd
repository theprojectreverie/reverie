extends Interactable
const GROUP_ID := "revienna_encounter"
const DEFEATED := "revienna_defeated"
const ENDING_PENDING := "ravienna_ending_pending"
const ENDING_SEEN := "ravienna_ending_seen"
var engaged := false
var coop_hp := 1800.0
var coop_phase := 1
var coop_warning: Dictionary = {}
var coop_feedback := "Prepare to strike."
var coop_guard_ack := 0
var coop_special_count := 0
var coop_guard_count := 0
var coop_panel: Control
var group_id := GROUP_ID
var defeated := false
var challenge_selected := false
var owns_dialogue := false
var victory_pending := false
var ending_confirmed := false
var ending_view_active := false
var previous_ending_hud := true
var previous_ending_dim := Color.WHITE
var previous_ending_camera: Camera2D
@onready var zone := get_parent()
@onready var dialogue := zone.get_node("UI/Dialogue") as DialogueBox
@onready var combat := zone.get_node("CombatRouter") as GameCombatRouterComponent

func _ready() -> void:
	super._ready()
	prompt = "Speak to Revienna"
	interaction_radius = 150.0
	dialogue.choice_selected.connect(_choice)
	dialogue.closed.connect(_dialogue_closed)
	EventBus.battle_finished.connect(_result)
	combat.combat_closed.connect(_combat_closed)
	_refresh()

func _refresh() -> void:
	enabled = not defeated if _is_coop() else (not bool(GameState.quest_domain.flags.get(DEFEATED, false)) or _ending_pending()) and not engaged and not victory_pending
	prompt = "Speak to Ravienna" if _ending_pending() and not _is_coop() else "Speak to Revienna"

func _ending_pending() -> bool:
	return bool(GameState.quest_domain.flags.get(ENDING_PENDING, false)) and not bool(GameState.quest_domain.flags.get(ENDING_SEEN, false))

func can_interact() -> bool:
	return super.can_interact() and not owns_dialogue and combat.active_combat == null

func interact() -> void:
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if not can_interact() or not is_instance_valid(player) or not bool(player.get("input_enabled")) or player.global_position.distance_to(global_position) > interaction_radius:
		return
	if _ending_pending() and not _is_coop():
		_show_victory()
		return
	challenge_selected = false
	owns_dialogue = true
	player.set("input_enabled", false)
	player.velocity = Vector2.ZERO
	TouchInput.release()
	dialogue.open("revienna_challenge")

func _choice(id: String, choice: Dictionary) -> void:
	if owns_dialogue and id == "revienna_challenge":
		challenge_selected = str(choice.get("text", "")) == "Challenge Revienna"
	elif owns_dialogue and id == "revienna_victory":
		ending_confirmed = str(choice.get("text", "")) == "Continue"

func _dialogue_closed(id: String) -> void:
	if not owns_dialogue or id not in ["revienna_challenge", "revienna_victory"]:
		return
	owns_dialogue = false
	if id == "revienna_challenge" and challenge_selected:
		challenge_selected = false
		engaged = true
		_refresh()
		_begin_battle.call_deferred()
	else:
		if id == "revienna_victory":
			if ending_confirmed:
				GameState.quest_domain.flags[ENDING_SEEN] = true
				GameState.quest_domain.flags.erase(ENDING_PENDING)
				if GameState.quest_domain.flags.get("chapter_manual_quest", "") == "ravienna_finale":
					GameState.quest_domain.flags.erase("chapter_manual_quest")
				StoryMilestoneTelemetry.record_chapter_complete()
				EventBus.quest_updated.emit("ravienna_finale")
				GameState.save_now()
			_end_ending_view()
			dialogue.set_ending_landscape_layout(false)
			zone.remove_meta("ravienna_ending_active")
			ending_confirmed = false
			_refresh()
		_resume()

func _begin_battle() -> void:
	if _is_coop():
		_open_coop_panel()
		return
	EventBus.encounter_requested.emit(GROUP_ID, self)
	if combat.active_combat == null:
		engaged = false
		_refresh()
		_resume()

func _result(result: Dictionary) -> void:
	if str(result.get("group_id", "")) != GROUP_ID or not engaged:
		return
	victory_pending = bool(result.get("victory", false))
	if victory_pending:
		GameState.quest_domain.flags[DEFEATED] = true
		GameState.quest_domain.flags[ENDING_PENDING] = true
		zone.set_meta("ravienna_ending_active", true)
		EventBus.quest_updated.emit("ravienna_finale")
		GameState.save_now()
	engaged = false
	_refresh()

func _combat_closed() -> void:
	if victory_pending:
		victory_pending = false
		_show_victory.call_deferred()
	else:
		engaged = false
		_refresh()

func _show_victory() -> void:
	zone.set_meta("ravienna_ending_active", true)
	ending_confirmed = false
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if is_instance_valid(player):
		player.set("input_enabled", false)
		player.velocity = Vector2.ZERO
	owns_dialogue = true
	_begin_ending_view()
	dialogue.set_ending_landscape_layout(get_window().size.x < 1000 and get_window().size.x > get_window().size.y)
	dialogue.open("revienna_victory")

func _resume() -> void:
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if is_instance_valid(player):
		player.set("input_enabled", true)

func _is_coop() -> bool:
	return MultiplayerGateway.standalone_expedition_region == "six_zone_ruined_tower"

func _open_coop_panel() -> void:
	if defeated:
		engaged = false
		_resume()
		return
	if is_instance_valid(coop_panel):
		return
	coop_panel = preload("res://scenes/ui/components/coop_revienna_battle.tscn").instantiate()
	zone.get_node("UI/Combat").add_child(coop_panel)
	coop_panel.call("apply_state", coop_hp, false, false, "", coop_phase, coop_warning)
	coop_panel.get_node("Center/Panel/Content/Attack").pressed.connect(_coop_strike)
	coop_panel.get_node("Center/Panel/Content/Guard").pressed.connect(_coop_guard)
	coop_panel.get_node("Center/Panel/Content/Leave").pressed.connect(_close_coop_panel)
	zone.set_meta("coop_boss_panel_open", true)
	var player = zone.get("checkpoint_player")
	if is_instance_valid(player):
		player.input_enabled = false
		player.velocity = Vector2.ZERO
	_update_coop_panel()

func _close_coop_panel() -> void:
	if is_instance_valid(coop_panel):
		coop_panel.queue_free()
	coop_panel = null
	zone.set_meta("coop_boss_panel_open", false)
	engaged = false
	_refresh()
	_resume()

func apply_coop_boss_state(state: Dictionary, live: bool = false) -> void:
	coop_hp = clampf(float(state.get("hp",1800)), 0.0, 1800.0)
	coop_phase = clampi(int(state.get("phase",1)), 1, 3)
	var previous_deadline := int(coop_warning.get("resolveAt", 0))
	var previous_target := str(coop_warning.get("targetId", ""))
	coop_warning = state.get("warning", {}) if state.get("warning") is Dictionary else {}
	if coop_warning.is_empty() or not _is_warning_target() or previous_deadline != int(coop_warning.get("resolveAt", 0)) or previous_target != str(coop_warning.get("targetId", "")):
		coop_guard_ack = 0
	if bool(coop_warning.get("guardAcknowledged", false)) and _is_warning_target():
		coop_guard_ack = int(coop_warning.get("resolveAt", 0))
	var counter = state.get("counterattack")
	if counter is Dictionary:
		var sync = zone.get_node_or_null("CoopWorldSync")
		var mine: bool = sync != null and str(counter.get("playerId","")) == sync.local_player_id
		coop_feedback = ("You" if mine else "Your ally") + " took %d damage." % int(counter.get("damage",0))
		if bool(state.get("guarded",false)):
			coop_feedback += " Guard successful."
	if live and state.get("resolvedSpecial") != null:
		coop_special_count += 1
		if bool(state.get("guarded",false)):
			coop_guard_count += 1
	defeated = coop_hp <= 0
	if is_instance_valid(coop_panel):
		var special := str(state.get("resolvedSpecial", "")) if state.get("resolvedSpecial") != null else ""
		coop_panel.call("apply_state", coop_hp, counter is Dictionary, live, special, coop_phase, coop_warning)
	_refresh()
	_update_coop_panel()

func _process(_delta: float) -> void:
	if is_instance_valid(coop_panel):
		_update_coop_panel()

func _update_coop_panel() -> void:
	if not is_instance_valid(coop_panel):
		return
	var box = coop_panel.get_node("Center/Panel/Content")
	box.get_node("Health").value = coop_hp
	box.get_node("Phase").text = "Victory" if defeated else "Phase %d / 3 - %d / 1800 HP" % [coop_phase,int(coop_hp)]
	var sync = zone.get_node_or_null("CoopWorldSync")
	var ready: bool = sync != null and sync._snapshot_ready and MultiplayerGateway.is_connected_to_lobby()
	box.get_node("Attack").disabled = not ready or defeated or not coop_warning.is_empty()
	var acknowledged := not coop_warning.is_empty() and coop_guard_ack == int(coop_warning.get("resolveAt",-1))
	box.get_node("Guard").disabled = not ready or defeated or not _is_warning_target() or acknowledged
	box.get_node("Guard").text = "Guard ready" if acknowledged else "Guard"
	var player = zone.get("checkpoint_player")
	if is_instance_valid(player):
		var world_combat = player.get_node_or_null("WorldCombatComponent")
		if world_combat != null:
			box.get_node("PlayerHealth").max_value = world_combat.max_hp
			box.get_node("PlayerHealth").value = world_combat.hp
			box.get_node("PlayerHealthLabel").text = "Your health: %d / %d" % [int(world_combat.hp),int(world_combat.max_hp)]
	box.get_node("CombatFeedback").text = "Reconnecting to your party..." if not ready else "Victory - rewards credited to your account." if defeated else coop_feedback
	box.get_node("Warning").text = "Incoming: " + str(coop_warning.get("name", "")) + (" - Guard now!" if _is_warning_target() else " - Targeting your ally!") if not coop_warning.is_empty() and not defeated else "Watch for the Sovereign's next attack."
func _coop_strike() -> void:
	_update_coop_panel()
	if not defeated and is_instance_valid(coop_panel) and not coop_panel.get_node("Center/Panel/Content/Attack").disabled:
		MultiplayerGateway.request_monster_attack(GROUP_ID)

func _coop_guard() -> void:
	_update_coop_panel()
	if not defeated and _is_warning_target() and is_instance_valid(coop_panel) and not coop_panel.get_node("Center/Panel/Content/Guard").disabled:
		MultiplayerGateway.request_monster_attack(GROUP_ID, true)
func _is_warning_target() -> bool:
	var sync = zone.get_node_or_null("CoopWorldSync")
	return sync != null and not coop_warning.is_empty() and str(coop_warning.get("targetId","")) == sync.local_player_id
func apply_coop_guard_confirmation(state: Dictionary) -> void:
	var sync = zone.get_node_or_null("CoopWorldSync")
	if sync != null and not defeated and _is_warning_target() and str(state.get("playerId","")) == sync.local_player_id and int(state.get("resolveAt", 0)) == int(coop_warning.get("resolveAt", -1)):
		coop_guard_ack = int(state.get("resolveAt",0))
		coop_feedback = "Guard confirmed. Awaiting impact."
		_update_coop_panel()

func _begin_ending_view() -> void:
	if ending_view_active:
		return
	ending_view_active = true
	var hud := zone.get_node("UI/HUD") as Control
	var dim := dialogue.get_node("Dim") as ColorRect
	var camera := zone.get_node("EndingCamera") as Camera2D
	previous_ending_camera = get_viewport().get_camera_2d()
	previous_ending_hud = hud.visible
	previous_ending_dim = dim.color
	hud.hide()
	dim.color = Color(0.01,0.02,0.04,0.12)
	var view := get_viewport_rect().size
	var zoom_factor := minf(0.9, view.x / 830.0)
	camera.zoom = Vector2.ONE * zoom_factor
	camera.global_position = global_position + Vector2(0, 140.0 / zoom_factor)
	camera.enabled = true
	camera.make_current()
	camera.force_update_scroll()

func _end_ending_view() -> void:
	if not ending_view_active:
		return
	ending_view_active = false
	var camera := zone.get_node("EndingCamera") as Camera2D
	zone.get_node("UI/HUD").visible = previous_ending_hud
	dialogue.get_node("Dim").color = previous_ending_dim
	if is_instance_valid(previous_ending_camera):
		previous_ending_camera.make_current()
	camera.enabled = false
	previous_ending_camera = null
