extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://assets/characters/bond_skills/eternal_eclipse/eternal_eclipse_preview.tscn").instantiate()
	root.add_child(scene)
	var a: AnimationPlayer = scene.get_node("AnimationPlayer")
	var g: Sprite2D = scene.get_node("Cassien/Art")
	var r: Sprite2D = scene.get_node("Ravienna/Art")
	var red: Sprite2D = scene.get_node("Crimson")
	var purple: Sprite2D = scene.get_node("Violet")
	var eclipse: Sprite2D = scene.get_node("Eclipse")
	var impact: Sprite2D = scene.get_node("Impact")
	var cleanse: Sprite2D = scene.get_node("Purification")
	a.play("eternal_eclipse")
	a.seek(0.0,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	var ok: bool = g.frame == 0 and r.frame == 0 and red.modulate.a == 0.0
	a.seek(1.3,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	ok = ok and g.frame >= 8 and r.frame >= 8 and scene.get_node("Cassien").rotation > 0.2
	a.seek(2.8,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	ok = ok and red.modulate.a > 0.8 and purple.modulate.a > 0.8
	a.seek(3.8,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	ok = ok and eclipse.modulate.a > 0.9 and eclipse.frame >= 4
	a.seek(4.8,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	ok = ok and impact.modulate.a > 0.9 and impact.scale.x > 1.5
	a.seek(6.0,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	ok = ok and cleanse.modulate.a > 0.9 and cleanse.frame >= 8
	a.seek(6.49,true)
	print("STATE ",a.current_animation_position," g=",g.frame," r=",r.frame," rot=",scene.get_node("Cassien").rotation," red=",red.modulate.a," purple=",purple.modulate.a," eclipse=",eclipse.modulate.a," ef=",eclipse.frame," impact=",impact.modulate.a," iscale=",impact.scale.x," cleanse=",cleanse.modulate.a," cf=",cleanse.frame)
	ok = ok and cleanse.modulate.a < 0.05 and impact.modulate.a == 0 and red.modulate.a == 0 and purple.modulate.a == 0 and eclipse.modulate.a == 0
	ok = ok and is_equal_approx(a.current_animation_length, 6.5)
	print("ETERNAL ECLIPSE PREVIEW: ",ok," duration=",a.current_animation_length)
	scene.queue_free()
	await process_frame
	quit(0 if ok else 1)

