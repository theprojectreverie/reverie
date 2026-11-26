extends Node

func _ready() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func extent(t: Texture2D) -> Rect2i:
	if t is AtlasTexture:
		return t.atlas.get_image().get_region(Rect2i(t.region)).get_used_rect()
	return t.get_image().get_used_rect()

func body_height(a: BattlefieldActor) -> float:
	var t: Texture2D
	var body_scale: float
	if is_instance_valid(a.gerald_art):
		t = a.gerald_art.sprite_frames.get_frame_texture("idle",0)
		body_scale = a.gerald_art.scale.y
	elif is_instance_valid(a.cassien_art):
		t = a.cassien_art.sprite_frames.get_frame_texture("idle",0)
		body_scale = a.cassien_art.scale.y
	elif is_instance_valid(a.ravienna_art):
		var sprite := a.ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
		t = sprite.sprite_frames.get_frame_texture("idle",0)
		body_scale = a.ravienna_art.scale.y * sprite.scale.y
	else:
		t = a.visual._sprite.texture
		body_scale = a.visual._sprite.scale.y
	return float(extent(t).size.y) * body_scale * a.scale.y

func run() -> void:
	var field: Battlefield = load("res://scenes/ui/battlefield.tscn").instantiate()
	add_child(field)
	for encounter in ["revienna_encounter","cassien_encounter","gerald_boss_encounter"]:
		field.arena_id = encounter
		var players: Array[Combatant] = []
		for id in ["gerald_mythic","cassien_legendary","ravienna_mythic","lilith_mythic"]:
			var c := CharacterInstance.new()
			c.char_id = id
			var u := CombatFactory.build_from_character(c)
			if u == null:
				fail("Missing "+id)
				return
			u.uid = id
			players.append(u)
		var enemies := CombatFactory.enemy_units(encounter,"story_tower")
		if enemies.is_empty():
			fail("Missing boss "+encounter)
			return
		field.setup(players,enemies)
		await get_tree().process_frame
		for dims in [Vector2(1280,400),Vector2(960,320),Vector2(640,240)]:
			field.size = dims
			field._layout()
			var queen := field.actor_for_uid("ravienna_mythic")
			var reference := body_height(queen)
			for id in ["gerald_mythic","cassien_legendary","lilith_mythic",enemies[0].uid]:
				var actor := field.actor_for_uid(id)
				var expected: float = 400.0/170.0 if actor.unit.def_id.begins_with("gerald") else (190.0/170.0 if actor.unit.def_id.begins_with("cassien") else (140.0/170.0 if actor.unit.def_id.begins_with("lilith") else 1.0))
				var actual := body_height(actor)/reference
				print("HEIGHT ",encounter," ",dims," ",actor.unit.def_id," ",actual," expected ",expected)
				if absf(actual-expected)>0.035:
					fail("Height ratio "+actor.unit.def_id)
					return
				if actor.home_position.y-body_height(actor)<0:
					fail("Clipped body "+actor.unit.def_id)
					return
		var dialogue = ContentDB.get_dialogue("revienna_challenge")
		if dialogue.nodes.greet.speaker!="Ravienna":
			fail("Dialogue name")
			return
	print("PASS canonical battle height ratios")
	field.queue_free()
	await get_tree().process_frame
	get_tree().quit()
