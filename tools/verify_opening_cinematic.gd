extends Node

var did_finish := false

func _ready() -> void:
	var intro := load("res://scenes/ui/opening_cinematic.tscn").instantiate() as OpeningCinematic
	intro.finished.connect(_on_finished)
	add_child(intro)
	await get_tree().process_frame
	var caption := intro.get_node_or_null("Caption") as Label
	var skip_button := intro.get_node_or_null("SkipButton") as Button
	if caption == null or skip_button == null:
		push_error("[opening] Missing caption or skip control.")
		get_tree().quit(1)
		return
	skip_button.pressed.emit()
	await intro.finished
	if not did_finish:
		push_error("[opening] Skip did not finish the cinematic.")
		get_tree().quit(1)
		return
	print("[opening] OK — prologue renders, captions exist, and Skip advances.")
	intro.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _on_finished() -> void:
	did_finish = true
