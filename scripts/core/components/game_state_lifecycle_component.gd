class_name GameStateLifecycleComponent
extends Node
## Owns GameState startup, new-journey bootstrap, autosave cadence and reset lifecycle.

var state: Node
var active_player_id := ""
var save_recovery_blocked := false
@onready var save_timer: Timer = get_node_or_null("../SaveTimer") as Timer
@onready var autosave_timer: Timer = get_node_or_null("../AutosaveTimer") as Timer


func configure(owner_state: Node) -> void:
	state = owner_state


func initialize() -> void:
	if state == null:
		return
	if save_timer == null or autosave_timer == null:
		push_error("GameStateLifecycleComponent requires authored SaveTimer and AutosaveTimer siblings")
		return
	if not save_timer.timeout.is_connected(save_now):
		save_timer.timeout.connect(save_now)
	if not autosave_timer.timeout.is_connected(save_now):
		autosave_timer.timeout.connect(save_now)
	autosave_timer.start()
	if SaveService.has_save():
		var data := SaveService.load_save()
		if not data.is_empty():
			state._load_from_dict(data)
			state.loaded_from_save = true
	if state.profile.is_empty():
		save_recovery_blocked = SaveService.has_save()
		new_game()
	elif not state.profile.has("paid_moonstones"):
		# Existing saves receive the new premium-only wallet without losing progress.
		state.profile["paid_moonstones"] = 0
		queue_save()
	print("[GameState] %s — %d characters, %d in party, %d crystals, %d gold." % [
		"loaded save" if state.loaded_from_save else "new journey",
		state.roster.size(), state.party.size(),
		state.inventory_domain.currency("crystals"),
		state.inventory_domain.currency("gold")
	])


func new_game(player_name: String = "Wanderer") -> void:
	if state == null:
		return
	state.loaded_from_save = false
	state.profile = {
		"name": player_name,
		"level": 1,
		"xp": 0,
		"gold": 500,
		"gems": 0,
		"crystals": 1500,
		"paid_moonstones": 0,
		"guild_tokens": 0,
		"ancient_coins": 0,
		"event_tokens": 0,
		"created_at": Time.get_unix_time_from_system(),
	}
	state.roster.clear()
	state.party.clear()
	state.inventory = { "glade_sap": 3, "mossweave_vest": 1 }
	state.quests = {}
	state.pity = {}
	state.daily_rewards = {}
	state.daily_quests = {}
	state.flags = {}
	state.gear_levels = {}
	state.gear_rerolls = {}
	state.roster_domain.stored_gear = {}
	state.player_position = Vector2.ZERO
	state.has_player_position = false
	state.player_facing = Vector2(0.0, 1.0)
	state.player_region = "greenward"
	state.active_world_id = "greenward"
	state.region_positions = {}
	state.roster_domain.reset_uid_counter()
	for character_id in state.STARTING_CHARACTERS:
		state.add_character(character_id)
	save_now()
	EventBus.roster_changed.emit()
	EventBus.party_changed.emit()
	EventBus.currency_changed.emit()


func save_now() -> void:
	if state == null or state.profile.is_empty() or save_recovery_blocked:
		return
	SaveService.write_save(state._to_dict())


func queue_save() -> void:
	if save_timer != null:
		save_timer.start()


func reset_progress() -> void:
	save_recovery_blocked = false
	SaveService.delete_save()
	new_game()

func switch_player(authenticated: bool, player: Dictionary) -> void:
	var next_id := str(player.get("id", "")) if authenticated else ""
	if next_id == active_player_id:
		return
	var valid := RegEx.new()
	valid.compile("^[0-9a-fA-F-]{36}$")
	if authenticated and valid.search(next_id) == null:
		push_error("Invalid account save identity")
		return
	save_timer.stop()
	save_now()
	active_player_id = next_id
	SaveService.select_player(next_id)
	var data := SaveService.load_save()
	save_recovery_blocked = data.is_empty() and SaveService.has_save()
	if data.is_empty():
		new_game(str(player.get("name", "Wanderer")))
		_apply_local_developer_grant()
	else:
		state._load_from_dict(data)
		state.loaded_from_save = true
		_apply_local_developer_grant()
		EventBus.roster_changed.emit()
		EventBus.party_changed.emit()
		EventBus.currency_changed.emit()

func _apply_local_developer_grant() -> void:
	if not OS.is_debug_build() or active_player_id != "3b0d68b4-0a85-4b21-a789-79a88be8ec1a":
		return
	if bool(state.flags.get("dev_grant_raven_20261125", false)):
		return
	state.profile["crystals"] = int(state.profile.get("crystals", 0)) + 1000000
	state.profile["paid_moonstones"] = int(state.profile.get("paid_moonstones", 0)) + 1000000
	state.flags["dev_grant_raven_20261125"] = true
	save_now()
	EventBus.currency_changed.emit()
