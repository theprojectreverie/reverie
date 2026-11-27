extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/lilith/summoning/dark_summoning_preview.tscn").instantiate()
	root.add_child(scene)
	var anim: AnimationPlayer = scene.get_node("AnimationPlayer")
	var lilith: Sprite2D = scene.get_node("Lilith")
	var portal: Sprite2D = scene.get_node("Portal")
	anim.play("dark_summoning")
	var ok: bool = lilith.hframes == 12 and portal.hframes == 10
	anim.seek(0.4, true)
	ok = ok and lilith.modulate.a == 0.0 and portal.modulate.a > 0.9
	anim.seek(1.9, true)
	ok = ok and lilith.modulate.a > 0.9 and portal.modulate.a > 0.9 and lilith.frame > 0
	anim.seek(3.6, true)
	ok = ok and lilith.frame == 11 and lilith.position.x > 680.0
	anim.seek(5.95, true)
	ok = ok and portal.modulate.a < 0.01 and lilith.modulate.a > 0.99 and lilith.frame == 11
	print("LILITH DARK SUMMONING: ",ok," portal closed=",portal.modulate.a," human frame=",lilith.frame," timeline=",anim.current_animation_length)
	quit(0 if ok else 1)

