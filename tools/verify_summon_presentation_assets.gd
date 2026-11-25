extends SceneTree

const ICONS := {
	"gold": "res://assets/ui/currencies/gold.png",
	"crystals": "res://assets/ui/currencies/summoning_crystals.png",
	"ancient_coins": "res://assets/ui/currencies/ancient_coins.png",
	"gems": "res://assets/ui/currencies/gems.png",
	"guild_tokens": "res://assets/ui/currencies/guild_tokens.png",
	"event_tokens": "res://assets/ui/currencies/event_tokens.png"
}
const STREAMS := [
	"res://assets/cinematics/summoning/summoning_opening_fade.ogv",
	"res://assets/cinematics/summoning/summoning_standard_silver_blue.ogv",
	"res://assets/cinematics/summoning/summoning_rare_violet.ogv",
	"res://assets/cinematics/summoning/summoning_highest_gold_crimson.ogv"
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var file := FileAccess.open("res://resources/data/banners.json", FileAccess.READ)
	if file == null:
		push_error("SUMMON_BANNERS_JSON_MISSING")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("BANNERS_JSON_INVALID")
	else:
		for banner_id in parsed.keys():
			var cost: Dictionary = parsed[banner_id].get("cost", {})
			if int(cost.get("single", -1)) != 120 or int(cost.get("ten", -1)) != 1200:
				failures.append("COST_" + str(banner_id))
			else:
				print("SUMMON_COST_OK ", banner_id, " single=120 ten=1200")
	for currency_id in ICONS:
		var path: String = ICONS[currency_id]
		var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			failures.append("CURRENCY_ICON_" + currency_id)
		else:
			print("CURRENCY_ICON_OK ", currency_id, " size=", texture.get_width(), "x", texture.get_height())
	var chip_scene := load("res://scenes/ui/components/currency_chip.tscn") as PackedScene
	if chip_scene == null:
		failures.append("CURRENCY_CHIP_SCENE_MISSING")
	else:
		var chip := chip_scene.instantiate()
		var content_node := chip.get_node_or_null("Content")
		var value_label := chip.get_node_or_null("Content/ValueLabel") as Label
		if content_node == null or value_label == null:
			failures.append("CURRENCY_CHIP_STRUCTURE")
		else:
			var labels := content_node.find_children("*", "Label", true, false)
			if labels.size() != 1:
				failures.append("CURRENCY_CHIP_HAS_EXTRA_TEXT_LABELS")
			else:
				print("CURRENCY_CHIP_ICON_AND_AMOUNT_ONLY_OK")
		chip.free()
	for path in STREAMS:
		var stream := load(path) as VideoStream
		if stream == null:
			failures.append("REVEAL_STREAM_" + path.get_file())
		else:
			print("REVEAL_STREAM_RESOURCE_OK ", path.get_file())
	var reveal_scene := load("res://scenes/ui/components/summon_reveal_overlay.tscn") as PackedScene
	if reveal_scene == null:
		failures.append("REVEAL_SCENE_MISSING")
	else:
		var reveal := reveal_scene.instantiate()
		if reveal.get_node_or_null("CinematicPlayer") == null or reveal.get_node_or_null("CloseSummonButton") == null:
			failures.append("REVEAL_SCENE_CONTROLS")
		else:
			print("REVEAL_SCENE_CONTROLS_OK")
		reveal.free()
	if failures.is_empty():
		print("SUMMON_PRESENTATION_ASSETS_OK")
	else:
		push_error("SUMMON_PRESENTATION_FAILURES=" + ",".join(failures))
	quit(1 if not failures.is_empty() else 0)
