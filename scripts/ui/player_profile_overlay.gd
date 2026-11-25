extends Control

func _ready() -> void:
	var profile: Dictionary = GameState.profile
	var player := AuthGateway.current_player()
	$Center/Panel/Margin/Content/Name.text = str(player.get("name", profile.get("name", "Traveler")))
	$Center/Panel/Margin/Content/Level.text = "LEVEL %02d" % int(profile.get("level", 1))
	$Center/Panel/Margin/Content/Experience.text = "Experience  •  %d XP" % int(profile.get("xp", 0))
	$Center/Panel/Margin/Content/Crystals.text = "Summon crystals  •  " + UIFactory.number(int(profile.get("crystals", 0)))
	$Center/Panel/Margin/Content/Moonstones.text = "Moonstones  •  " + UIFactory.number(int(profile.get("paid_moonstones", 0)))
	$Center/Panel/Margin/Content/Close.pressed.connect(queue_free)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
