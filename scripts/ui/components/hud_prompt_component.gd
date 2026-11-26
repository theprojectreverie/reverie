class_name HUDPromptComponent
extends Node
## Owns the HUD's throttled interaction-prompt and quest-refresh lifecycle.

var hud: HUD
var _prompt_timer: float = 0.0
var _refresh_timer: float = 0.0
var _last_prompt: String = ""

func bind(owner: HUD) -> void:
	hud = owner

func _process(delta: float) -> void:
	if not is_instance_valid(hud) or not hud.is_visible_in_tree():
		return
	_prompt_timer += delta
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		hud.refresh_quest()
	if _prompt_timer < 0.12:
		return
	_prompt_timer = 0.0
	var prompt := ""
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("current_prompt") and bool(player.get("input_enabled")) and not bool(player.get("network_recovery_paused")):
		var prompt_text: String = player.current_prompt()
		if not prompt_text.is_empty():
			var target := "target"
			if player.nearby_interactable != null and "display_name" in player.nearby_interactable:
				target = str(player.nearby_interactable.display_name)
			var prefix := "" if TouchInput.using_touch else "[E]  "
			prompt = prefix + prompt_text if target == "target" or prompt_text.to_lower().contains(target.to_lower()) else prefix + prompt_text + "  " + target
	if prompt != _last_prompt:
		_last_prompt = prompt
		if hud._prompt_label != null:
			hud._prompt_label.text = prompt
		if hud._prompt_panel != null:
			hud._prompt_panel.visible = not prompt.is_empty()

