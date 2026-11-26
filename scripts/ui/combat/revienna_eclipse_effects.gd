extends Node2D
## Authored sprite layers; this script only synchronizes and positions them.
var _battlefield: Control
var _caster: Node2D


func start(field: Control, caster: Node2D) -> void:
	_battlefield = field
	_caster = caster
	_layout()
	field.resized.connect(_layout, CONNECT_DEFERRED)
	var sequence := create_tween()
	sequence.tween_interval(0.1)
	sequence.tween_callback(_play_group.bind($Corona, &"eclipse"))
	sequence.tween_interval(0.275)
	sequence.tween_callback(_play_group.bind($Cracks, &"cracks"))
	sequence.tween_interval(0.375)
	sequence.tween_callback(_play_group.bind($Eruptions, &"eruption"))
	sequence.tween_interval(1.3)
	sequence.tween_callback(queue_free)


func _layout() -> void:
	if not is_instance_valid(_battlefield) or not is_instance_valid(_caster):
		return
	var size := _battlefield.size
	var ground := clampf(float(_caster.home_position.y), size.y * 0.65, size.y * 0.88)
	var spacing := size.x * 0.27
	var enemy_slots: Array[Vector2] = []
	if _caster.is_player:
		for actor in _battlefield.actors():
			if not actor.is_player and not actor.dead:
				enemy_slots.append(actor.home_position)
	for i in range(3):
		var x := size.x * 0.23 + spacing * i
		var floor_y := ground - 10.0 - (i % 2) * 16.0
		if not enemy_slots.is_empty():
			var target := enemy_slots[i % enemy_slots.size()]
			x = target.x + float(i / enemy_slots.size()) * 24.0
			floor_y = target.y - 10.0
		var crack := $Cracks.get_child(i) as AnimatedSprite2D
		crack.position = Vector2(x, floor_y)
		crack.scale = Vector2(size.x / 440.0, minf(1.0, size.y / 360.0))
		var eruption := $Eruptions.get_child(i) as AnimatedSprite2D
		eruption.position = Vector2(x, floor_y)
		eruption.scale = Vector2.ONE * minf(0.95, size.y / 370.0)
	var corona := $Corona/Effect0 as AnimatedSprite2D
	corona.position = Vector2(float(_caster.home_position.x), maxf(size.y * 0.16, ground - 172.0 * _caster.scale.y))
	corona.scale = Vector2.ONE * minf(0.85, size.y / 380.0)


func _play_group(group: Node2D, clip: StringName) -> void:
	for effect in group.get_children():
		var sprite := effect as AnimatedSprite2D
		sprite.show()
		sprite.play(clip)
		sprite.animation_finished.connect(sprite.hide, CONNECT_ONE_SHOT)
