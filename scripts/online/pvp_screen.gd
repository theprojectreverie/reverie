extends Control
## Node-authored friendly PvP panel. The server remains authoritative for combat.
@onready var status_label: Label = $Center/Panel/Margins/Content/Status
@onready var match_label: Label = $Center/Panel/Margins/Content/MatchInfo
@onready var actor_option: OptionButton = $Center/Panel/Margins/Content/ActionRow/Actor
@onready var skill_option: OptionButton = $Center/Panel/Margins/Content/ActionRow/Skill
@onready var target_option: OptionButton = $Center/Panel/Margins/Content/ActionRow/Target
@onready var submit_button: Button = $Center/Panel/Margins/Content/ActionRow/SubmitButton
@onready var surrender_button: Button = $Center/Panel/Margins/Content/Buttons/SurrenderButton

var _local_player_id := ""

func _ready() -> void:
	var player := AuthGateway.current_player()
	_local_player_id = str(player.get("playerId", player.get("id", "")))
	surrender_button.disabled = true
	PvpGateway.pvp_result.connect(_on_pvp_result)
	PvpGateway.match_state_updated.connect(_on_match_state_updated)
	AuthGateway.authentication_changed.connect(_on_authentication_changed)
	
	
	
	PvpGateway.begin_polling()

func _exit_tree() -> void:
	if PvpGateway.pvp_result.is_connected(_on_pvp_result):
		PvpGateway.pvp_result.disconnect(_on_pvp_result)
	if PvpGateway.match_state_updated.is_connected(_on_match_state_updated):
		PvpGateway.match_state_updated.disconnect(_on_match_state_updated)
	if AuthGateway.authentication_changed.is_connected(_on_authentication_changed):
		AuthGateway.authentication_changed.disconnect(_on_authentication_changed)

func _join_queue() -> void:
	status_label.text = "Finding an opponent…"
	var result := PvpGateway.queue_join()
	if result != OK:
		status_label.text = "Sign in and make sure your party is ready before queueing."

func _leave_queue() -> void:
	var result := PvpGateway.queue_leave()
	if result != OK:
		status_label.text = "Unable to cancel the queue request."

func _surrender() -> void:
	if PvpGateway.active_match_id.is_empty():
		status_label.text = "There is no active duel to surrender."
		return
	var result := PvpGateway.surrender_match()
	if result != OK:
		status_label.text = "Unable to surrender right now. Wait for any pending request."
	else:
		status_label.text = "Surrender submitted. Waiting for the server to confirm…"

func _close() -> void:
	PvpGateway.stop_polling()
	queue_free()

func _on_pvp_result(operation: String, success: bool, payload: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not success:
		status_label.text = "PvP: " + str(payload.get("error", "request_failed"))
		return
	match operation:
		"queue_join", "queue_status":
			var queue_status := str(payload.get("status", ""))
			if queue_status == "waiting":
				status_label.text = "Searching for an opponent…"
			elif queue_status == "matched":
				status_label.text = "Opponent found. Loading battle…"
			elif queue_status == "not_queued":
				status_label.text = "Ready for a friendly duel."
		"queue_leave":
			status_label.text = "Queue cancelled."

func _on_match_state_updated(state: Dictionary, _events: Array) -> void:
	if not is_inside_tree() or state.is_empty():
		return
	var turn_owner := str(state.get("turnPlayerId", ""))
	var turn_number := int(state.get("turn", 1))
	var sequence := int(state.get("sequence", 0))
	match_label.text = "MATCH  %s\nTURN %d  ·  ACTION %d\nActive player: %s" % [
		str(state.get("matchId", "")).substr(0, 8).to_upper(), turn_number, sequence, turn_owner.substr(0, 8)
	]
	var match_status := str(state.get("status", "active"))
	surrender_button.disabled = match_status != "active" or PvpGateway.active_match_id.is_empty()
	if match_status == "completed":
		var winner_id := str(state.get("winnerId", ""))
		status_label.text = "Duel complete. " + ("You won!" if winner_id == _local_player_id else "Opponent won." if not winner_id.is_empty() else "No winner recorded.")
		submit_button.disabled = true
		return
	if match_status in ["expired", "cancelled"]:
		status_label.text = "This duel has expired or was cancelled."
		submit_button.disabled = true
		return
	var my_turn := not _local_player_id.is_empty() and turn_owner == _local_player_id
	status_label.text = "Your turn." if my_turn else "Opponent's turn — battle state synchronized."
	_rebuild_action_options(state)
	submit_button.disabled = not my_turn or actor_option.item_count == 0

func _rebuild_action_options(state: Dictionary) -> void:
	actor_option.clear()
	skill_option.clear()
	target_option.clear()
	var units: Array = state.get("units", [])
	var selected_uid := ""
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY or int(unit.get("hp", 0)) <= 0:
			continue
		if str(unit.get("ownerId", "")) != _local_player_id:
			continue
		var index := actor_option.item_count
		actor_option.add_item(str(unit.get("charId", "Wanderer")) + " · " + str(unit.get("uid", "")).substr(0, 6))
		actor_option.set_item_metadata(index, str(unit.get("uid", "")))
		if selected_uid.is_empty():
			selected_uid = str(unit.get("uid", ""))
	if not selected_uid.is_empty():
		actor_option.select(0)
		_on_actor_selected(0)

func _on_actor_selected(index: int) -> void:
	if index < 0 or index >= actor_option.item_count:
		return
	var uid := str(actor_option.get_item_metadata(index))
	for unit in PvpGateway.match_state.get("units", []):
		if typeof(unit) == TYPE_DICTIONARY and str(unit.get("uid", "")) == uid:
			_fill_skills(unit)
			return

func _fill_skills(actor: Dictionary) -> void:
	skill_option.clear()
	var skill_ids: Array = actor.get("skillIds", [])
	for skill_id in skill_ids:
		var index := skill_option.item_count
		skill_option.add_item(str(skill_id))
		skill_option.set_item_metadata(index, str(skill_id))
	var ultimate := str(actor.get("ultimateId", ""))
	if not ultimate.is_empty():
		var index := skill_option.item_count
		skill_option.add_item(ultimate + " · ULTIMATE")
		skill_option.set_item_metadata(index, ultimate)
	if skill_option.item_count > 0:
		skill_option.select(0)
		_on_skill_selected(0)

func _on_skill_selected(index: int) -> void:
	target_option.clear()
	if index < 0 or index >= skill_option.item_count or actor_option.item_count == 0:
		return
	var skill_id := str(skill_option.get_item_metadata(index))
	var definition: SkillDef = ContentDB.get_skill(skill_id)
	if definition == null:
		return
	var actor_uid := str(actor_option.get_item_metadata(actor_option.selected))
	var actor_team := 0
	for unit in PvpGateway.match_state.get("units", []):
		if typeof(unit) == TYPE_DICTIONARY and str(unit.get("uid", "")) == actor_uid:
			actor_team = int(unit.get("team", 0))
			break
	var target_team := actor_team if definition.target in ["single_ally", "all_allies"] else 3 - actor_team
	if definition.target in ["all_enemies", "all_allies", "self"]:
		return
	for unit in PvpGateway.match_state.get("units", []):
		if typeof(unit) != TYPE_DICTIONARY or int(unit.get("hp", 0)) <= 0:
			continue
		if int(unit.get("team", 0)) != target_team:
			continue
		var target_index := target_option.item_count
		target_option.add_item(str(unit.get("charId", "Target")) + " · " + str(unit.get("uid", "")).substr(0, 6))
		target_option.set_item_metadata(target_index, str(unit.get("uid", "")))
	if target_option.item_count > 0:
		target_option.select(0)

func _submit_action() -> void:
	if actor_option.item_count == 0 or skill_option.item_count == 0:
		status_label.text = "No available combat actions in the current snapshot."
		return
	var actor_uid := str(actor_option.get_item_metadata(actor_option.selected))
	var skill_id := str(skill_option.get_item_metadata(skill_option.selected))
	var definition: SkillDef = ContentDB.get_skill(skill_id)
	if definition == null:
		status_label.text = "This skill is missing from the local content database."
		return
	var targets: Array[String] = []
	if definition.target in ["single_enemy", "single_ally"]:
		if target_option.item_count == 0:
			status_label.text = "Choose a valid target."
			return
		targets.append(str(target_option.get_item_metadata(target_option.selected)))
	var result := PvpGateway.submit_action(actor_uid, skill_id, targets)
	if result != OK:
		status_label.text = "Action not sent. Wait for the latest server snapshot or check your connection."
	else:
		submit_button.disabled = true
		status_label.text = "Action submitted. Waiting for server resolution…"

func _on_authentication_changed(authenticated: bool, player: Dictionary) -> void:
	_local_player_id = str(player.get("playerId", player.get("id", ""))) if authenticated else ""
	if not authenticated:
		status_label.text = "Sign in to use friendly PvP."
		submit_button.disabled = true
		actor_option.clear()
		skill_option.clear()
		target_option.clear()