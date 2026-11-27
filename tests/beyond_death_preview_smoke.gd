extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/bond_skills/beyond_death/beyond_death_preview.tscn").instantiate()
	root.add_child(scene)
	var a: AnimationPlayer = scene.get_node("AnimationPlayer")
	var g: Sprite2D = scene.get_node("Gerald")
	var l: Sprite2D = scene.get_node("Lilith")
	var o: Sprite2D = scene.get_node("Orange")
	var c: Sprite2D = scene.get_node("Cyan")
	a.play("beyond_death")
	a.seek(0.0,true)
	var ok: bool = g.frame == 0 and l.frame == 0 and o.modulate.a == 0.0
	a.seek(2.9,true)
	ok = ok and g.frame >= 12 and l.frame >= 12 and l.position.x < 620 and o.modulate.a > 0.8 and c.modulate.a > 0.5
	a.seek(4.8,true)
	ok = ok and g.frame >= 20 and l.position.y < 250 and c.scale.x > 2.0
	a.seek(6.39,true)
	ok = ok and g.frame == 23 and l.frame == 20 and c.modulate.a < 0.02 and o.modulate.a < 0.02
	print("BEYOND DEATH PREVIEW: ",ok," duration=",a.current_animation_length," Gerald=",g.frame," Lilith=",l.frame)
	quit(0 if ok else 1)

