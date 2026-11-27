extends Control
signal finished
const PORTAL = preload("res://assets/characters/lilith/summoning/dark_summoning_preview.tscn")
const TRANSFORM = preload("res://assets/characters/lilith/summoning/spiritual_awakening_preview.tscn")
const KAEL = preload("res://assets/characters/kael_avatar/world_sheet.tres")
const GERALD = preload("res://assets/characters/lilith/summoning/gerald_transfer.png")
const FAIRY = preload("res://assets/characters/fairy_companion/fairy_idle_west_64x64.png")
var stage: Node2D
var kael: AnimatedSprite2D
var portal_scene: Node2D
var transformation: Node2D
var finished_once := false
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)
	stage = $Stage
	_layout()
	_run.call_deferred()
func _layout() -> void:
	if not is_instance_valid(stage): return
	var ratio := minf(size.x / 1280.0, size.y / 720.0)
	stage.scale = Vector2.ONE * ratio
	stage.position = (size - Vector2(1280,720) * ratio) * 0.5
func _run() -> void:
	kael = $Stage/Kael
	kael.play(&"cast_6")
	var fairy := $Stage/Companion as Sprite2D
	var flutter := create_tween().set_loops()
	flutter.tween_property(fairy,"position:y",364.0,0.6).set_trans(Tween.TRANS_SINE)
	flutter.tween_property(fairy,"position:y",376.0,0.6).set_trans(Tween.TRANS_SINE)
	# Existing authored cast and portal artwork; no additional generated visuals.
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree(): return
	portal_scene = PORTAL.instantiate()
	stage.add_child(portal_scene)
	kael.play(&"idle_6")
	await portal_scene.get_node("AnimationPlayer").animation_finished
	if not is_inside_tree(): return
	portal_scene.hide()
	portal_scene.queue_free()
	$Stage/GeraldOpening.hide()
	transformation = TRANSFORM.instantiate()
	stage.add_child(transformation)
	await transformation.awakened
	if not is_inside_tree(): return
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree(): return
	finished_once = true
	finished.emit()

