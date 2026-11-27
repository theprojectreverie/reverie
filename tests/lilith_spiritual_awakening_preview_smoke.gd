extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/lilith/summoning/spiritual_awakening_preview.tscn").instantiate()
	root.add_child(scene)
	var a: AnimationPlayer = scene.get_node("AnimationPlayer")
	var w: Sprite2D = scene.get_node("Awakened")
	var s: Sprite2D = scene.get_node("Spirit")
	var v: Sprite2D = scene.get_node("Vortex")
	a.play("spiritual_transformation")
	a.seek(9.5,true)
	var ok: bool = w.modulate.a < 0.01 and s.modulate.a > 0.99 and v.modulate.a > 0
	a.seek(10.8,true)
	ok = ok and w.modulate.a > 0.99 and s.modulate.a < 0.01 and v.modulate.a < 0.01 and w.frame < 4
	a.seek(14.9,true)
	ok = ok and w.frame == 21 and w.position.y < 300
	a.seek(14.9,true)
	a.advance(0.2)
	await process_frame
	ok = ok and a.current_animation == "floating_idle"
	a.seek(0.6,true)
	var y: float = w.position.y
	a.seek(1.8,true)
	ok = ok and y < w.position.y and w.frame >= 18 and w.modulate.a > 0.99
	print("AWAKENING: ",ok," loop=",a.current_animation," float y=",w.position.y)
	quit(0 if ok else 1)

