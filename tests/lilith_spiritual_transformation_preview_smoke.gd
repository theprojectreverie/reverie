extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/lilith/summoning/spiritual_transformation_preview.tscn").instantiate()
	root.add_child(scene)
	var a: AnimationPlayer = scene.get_node("AnimationPlayer")
	var h: Sprite2D = scene.get_node("Human")
	var s: Sprite2D = scene.get_node("Spirit")
	var v: Sprite2D = scene.get_node("Vortex")
	var g: Sprite2D = scene.get_node("Gerald")
	a.play("spiritual_transformation")
	a.seek(0.0,true)
	var ok: bool = h.modulate.a > 0.99 and s.modulate.a < 0.01
	a.seek(3.0,true)
	ok = ok and g.frame == 4 and scene.get_node("Energy").modulate.a > 0.9
	a.seek(7.5,true)
	ok = ok and s.modulate.a > 0.99 and s.position.y < 200 and v.modulate.a > 0.8 and v.rotation > 6
	a.seek(11.95,true)
	ok = ok and h.modulate.a < 0.01 and s.frame == 14 and v.modulate.a < 0.01 and s.position.y > 330
	print("SPIRITUAL TRANSFORMATION: ",ok," final frame=",s.frame," position=",s.position," length=",a.current_animation_length)
	quit(0 if ok else 1)

