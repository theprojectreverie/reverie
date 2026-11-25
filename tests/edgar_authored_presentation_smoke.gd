extends Node

const EDGAR_SCENE := preload("res://scenes/world/npcs/edgar.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var edgar := EDGAR_SCENE.instantiate() as Node2D
	if edgar == null:
		_fail("Edgar scene did not instantiate")
		return
	get_tree().root.add_child(edgar)
	await get_tree().process_frame
	var artwork := edgar.get_node_or_null("EdgarArtwork") as Sprite2D
	var player := edgar.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if artwork == null or player == null:
		_fail("Edgar is missing its authored artwork or AnimationPlayer node")
		return
	if not player.is_playing() or player.current_animation != "edgar_idle_breath":
		_fail("Edgar idle animation did not autoplay")
		return
	var library := load("res://resources/characters/animations/edgar_presentation.tres") as AnimationLibrary
	if library == null or not library.has_animation(&"edgar_idle_breath"):
		_fail("Edgar reusable presentation library is missing its idle clip")
		return
	if not library.has_animation(&"edgar_talk_nod"):
		_fail("Edgar reusable presentation library is missing its talk gesture")
		return
	var talk := library.get_animation(&"edgar_talk_nod")
	if talk.loop_mode != Animation.LOOP_NONE or not is_equal_approx(talk.length, 0.55):
		_fail("Edgar talk gesture has incorrect one-shot settings")
		return
	for i in talk.get_track_count():
		if not str(talk.track_get_path(i)).begins_with("EdgarArtwork:"):
			_fail("Edgar talk gesture targets something other than his artwork node")
			return
	edgar.interact()
	if player.current_animation != "edgar_talk_nod":
		_fail("Edgar interaction did not trigger the authored talk gesture")
		return
	var animation := library.get_animation(&"edgar_idle_breath")
	if animation.loop_mode != Animation.LOOP_LINEAR or not is_equal_approx(animation.length, 2.4):
		_fail("Edgar idle clip has incorrect loop or duration settings")
		return
	for i in animation.get_track_count():
		if not str(animation.track_get_path(i)).begins_with("EdgarArtwork:"):
			_fail("Edgar idle clip targets something other than his artwork node")
			return
	if artwork.position != Vector2(-48, -128) or artwork.scale != Vector2(2, 2):
		_fail("Edgar artwork lost its 96x128 footprint or ground anchor")
		return
	print("EDGAR AUTHORED PRESENTATION SMOKE: PASS (idle clip autoplay, loop, tracks, footprint and ground anchor)")
	edgar.queue_free()
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	get_tree().quit(1)
