extends Node

var transition_count := 0
var transition_region := ""
var transition_entry := ""
var prompt_change_count := 0
var latest_prompt := ""

func _on_region_change(region_id: String, entry_point: String) -> void:
	transition_count += 1
	transition_region = region_id
	transition_entry = entry_point

func _on_prompt_changed(prompt: String) -> void:
	prompt_change_count += 1
	latest_prompt = prompt

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var player_scene := load("res://scenes/characters/player.tscn") as PackedScene
	var player := player_scene.instantiate() as Player if player_scene != null else null
	if player == null:
		push_error("Could not instantiate production Player scene")
		get_tree().quit(1)
		return
	player.position = Vector2(140, 220)
	get_tree().root.add_child(player)
	var portal_scene := load("res://scenes/world/region_portal.tscn") as PackedScene
	var portal := portal_scene.instantiate() as RegionPortal
	portal.setup("elderwood_grove", {"id":"qa_live_interaction_route","to":"willow_fields","entry":"from_elderwood","label":"Willow Fields"})
	portal.position = player.position + Vector2(30, 0)
	get_tree().root.add_child(portal)
	await get_tree().process_frame
	if player.interaction_component == null:
		failures.append("production Player did not bind its authored interaction component")
	if not portal.is_in_group("interactables"):
		failures.append("portal did not register in interactables group")
	player._scan_for_interactable()
	if player.nearby_interactable != portal:
		failures.append("production Player scan did not select nearby portal")
	if player.current_prompt() != "Travel to Willow Fields":
		failures.append("wrong unlocked prompt: %s" % player.current_prompt())
	EventBus.region_change_requested.connect(_on_region_change)
	player.try_interact()
	if transition_count != 1 or transition_region != "willow_fields" or transition_entry != "from_elderwood":
		failures.append("unlocked route emitted wrong event: count=%d region=%s entry=%s" % [transition_count, transition_region, transition_entry])
	player.interaction_component.interaction_prompt_changed.connect(_on_prompt_changed)
	portal.required_quest = "__qa_unfinished_quest__"
	portal.locked_message = "QA gate remains sealed."
	await get_tree().create_timer(0.2).timeout
	if player.current_prompt() != "Sealed: Willow Fields":
		failures.append("locked route did not update player prompt: %s" % player.current_prompt())
	if latest_prompt != "Sealed: Willow Fields" or prompt_change_count != 1:
		failures.append("same-target quest gate change did not emit exactly one updated prompt: count=%d prompt=%s" % [prompt_change_count, latest_prompt])
	player.try_interact()
	if transition_count != 1:
		failures.append("locked route incorrectly emitted a region transition")
	portal.enabled = false
	player._scan_for_interactable()
	if player.nearby_interactable == portal:
		failures.append("disabled portal remained the player's active target")
	if transition_count != 1:
		failures.append("disabled portal changed transition count")
	portal.enabled = true
	player._scan_for_interactable()
	if player.nearby_interactable != portal:
		failures.append("portal could not be selected again before removal")
	portal.queue_free()
	await get_tree().process_frame
	if player.nearby_interactable != null or player.current_prompt() != "":
		failures.append("freed interactable remained cached by production Player")
	EventBus.region_change_requested.disconnect(_on_region_change)
	if player.interaction_component.interaction_prompt_changed.is_connected(_on_prompt_changed):
		player.interaction_component.interaction_prompt_changed.disconnect(_on_prompt_changed)
	if failures.is_empty():
		print("PLAYER PORTAL INTERACTION QA: PASS (production Player, unlocked travel, live quest-lock prompt, disabled-target rejection, freed-target cleanup)")
	else:
		for failure in failures:
			push_error(failure)
		print("PLAYER PORTAL INTERACTION QA: FAIL (%d issues)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
