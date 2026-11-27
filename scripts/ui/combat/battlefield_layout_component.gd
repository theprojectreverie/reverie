class_name BattlefieldLayoutComponent
extends Node
## Owns arena setup, combatant actor lifecycle and responsive battlefield placement.

var battlefield: Battlefield
var actors: Array = []
var by_uid: Dictionary = {}
var stage: Node2D
var embers: CPUParticles2D
# Canonical body heights in cm; authored idle silhouettes measured without transparent padding.
const GERALD_HEIGHT_CM := 400.0
const CASSIEN_HEIGHT_CM := 190.0
const RAVIENNA_HEIGHT_CM := 170.0
const LILITH_HEIGHT_CM := 140.0
const KAEL_HEIGHT_CM := 177.0
const KAEL_IDLE_PX := 108.0
const GERALD_PLAYER_IDLE_PX := 110.0
const GERALD_BOSS_IDLE_PX := 111.0
const CASSIEN_IDLE_PX := 105.0
const RAVIENNA_IDLE_PX := 115.0
const LILITH_IDLE_PX := 100.0
const GERALD_TO_RAVIENNA_SCALE := (GERALD_HEIGHT_CM / RAVIENNA_HEIGHT_CM) * RAVIENNA_IDLE_PX / GERALD_PLAYER_IDLE_PX

static func is_playable_gerald(actor: BattlefieldActor) -> bool:
	return actor.is_player and actor.unit != null and (actor.unit.def_id=="gerald" or actor.unit.def_id.begins_with("gerald_"))


func bind(owner: Battlefield) -> void:
	battlefield = owner
	actors = battlefield._actors
	by_uid = battlefield._by_uid


static func battle_background_path_for_group(group_id: String) -> String:
	var group_data: Dictionary = ContentDB.get_enemy_group(group_id)
	var region_id := str(group_data.get("region", "greenward"))
	match group_id:
		"gerald_boss_encounter":
			return "res://assets/ui/battle/backgrounds/gerald_twilight_battlefield.png"
		"tutorial_fairy_spar":
			return "res://assets/ui/battle/backgrounds/frozen_castle_courtyard.png"
		"fallen_matron_encounter":
			return "res://assets/backgrounds/withered_estate_battle.svg"
		"corrupted_treant":
			return "res://assets/ui/battle/backgrounds/crimson_castle_ruins.png"
		"elder_hollow":
			return "res://assets/backgrounds/greenward_battle.svg"
		"baltoria_encounter", "revienna_encounter":
			return "res://assets/ui/battle/backgrounds/gothic_cathedral_hall.png"
	match region_id:
		"castle_royal_gardens":
			return "res://assets/ui/battle/backgrounds/moonlit_royal_garden.png"
		"gothic_castle_boss_zone", "royal_gate", "training_ground":
			return "res://assets/ui/battle/backgrounds/frozen_castle_courtyard.png"
		"forsaken_ruins", "ruined_tower":
			return "res://assets/ui/battle/backgrounds/crimson_castle_ruins.png"
	return "res://assets/backgrounds/greenward_battle.svg"


func build_environment() -> void:
	if battlefield == null:
		return
	var art_backdrop := battlefield.get_node_or_null("ArenaArtBackdrop") as TextureRect
	var field_backdrop := battlefield.get_node_or_null("GreenwardForestBackdrop") as Control
	var boss_backdrop := battlefield.get_node_or_null("GreenwardRootArenaBackdrop") as Control
	var estate_backdrop := battlefield.get_node_or_null("WitheredEstateBackdrop") as Control
	embers = battlefield.get_node_or_null("Embers") as CPUParticles2D
	stage = battlefield.get_node_or_null("Actors") as Node2D
	if art_backdrop == null or field_backdrop == null or boss_backdrop == null or estate_backdrop == null or embers == null or stage == null:
		push_error("Battlefield scene is missing an authored backdrop, Embers, or Actors node.")
		return
	var art_path := battle_background_path_for_group(battlefield.arena_id)
	var has_dedicated_arena_art := art_path.begins_with("res://assets/ui/battle/backgrounds/")
	art_backdrop.texture = load(art_path) as Texture2D if has_dedicated_arena_art else null
	art_backdrop.visible = has_dedicated_arena_art and art_backdrop.texture != null
	field_backdrop.visible = not art_backdrop.visible and battlefield.arena_id not in ["fallen_matron_encounter", "corrupted_treant", "elder_hollow"]
	boss_backdrop.visible = not art_backdrop.visible and battlefield.arena_id in ["corrupted_treant", "elder_hollow"]
	boss_backdrop.set("arena_id", battlefield.arena_id)
	estate_backdrop.visible = not art_backdrop.visible and battlefield.arena_id == "fallen_matron_encounter"
	# Hidden alternative arenas must not animate dozens of invisible nodes.
	for backdrop in [field_backdrop, boss_backdrop, estate_backdrop]:
		backdrop.set_process(backdrop.visible)
	if battlefield.arena_id == "fallen_matron_encounter":
		embers.color = Color(0.85, 0.6, 0.95, 0.22)
	elif battlefield.arena_id == "baltoria_encounter" or has_dedicated_arena_art:
		embers.color = Color(0.78, 0.55, 0.95, 0.20)
	else:
		embers.color = Color(0.62, 0.9, 0.48, 0.20)
	battlefield._embers = embers
	battlefield._stage = stage

func setup(party: Array, enemies: Array) -> void:
	clear_actors()
	for unit in party:
		_add_actor(unit, true)
	for unit in enemies:
		_add_actor(unit, false)
	# Use the same authored combat model in ordinary and boss encounters.
	for actor in actors:
		if actor.is_player and KaelAttackPresentationComponent.is_kael(actor.unit.def_id):
			actor.enable_kael_boss_art()
	layout()
	battlefield.call_deferred("_layout")
	face_opponents()


func _add_actor(unit: Combatant, is_player: bool) -> void:
	if unit == null:
		return
	var actor := Battlefield.ACTOR_SCENE.instantiate() as BattlefieldActor
	stage.add_child(actor)
	actor.setup(unit, is_player)
	actor.clicked.connect(battlefield._on_actor_clicked)
	actors.append(actor)
	by_uid[unit.uid] = actor


func clear_actors() -> void:
	for actor in actors:
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()
	by_uid.clear()


func actor_for_uid(uid: String) -> BattlefieldActor:
	return by_uid.get(uid, null) as BattlefieldActor


func layout() -> void:
	if stage == null:
		return
	var width := battlefield.size.x
	var height := battlefield.size.y
	if width <= 0.0 or height <= 0.0:
		return
	# A shared size baseline keeps the two characters proportional on every screen.
	# Fit Gerald's tall silhouette within the stage and his boss ultimate within its width.
	var has_titan := actors.any(func(a):return is_playable_gerald(a) or is_instance_valid(a.gerald_art))
	var has_boss_titan := actors.any(func(a):return is_instance_valid(a.gerald_art))
	var queen_scale := minf(1.15, minf(height / 340.0, width / 650.0)) if has_titan else minf(1.15, height / 230.0)
	if has_boss_titan:
		queen_scale = minf(queen_scale, minf(2.12, width / 460.0) / GERALD_TO_RAVIENNA_SCALE)
	var titan_scale := queen_scale * GERALD_TO_RAVIENNA_SCALE
	var boss_titan_scale := queen_scale * (GERALD_HEIGHT_CM / RAVIENNA_HEIGHT_CM) * RAVIENNA_IDLE_PX / GERALD_BOSS_IDLE_PX
	var knight_scale := queen_scale * (CASSIEN_HEIGHT_CM / RAVIENNA_HEIGHT_CM) * RAVIENNA_IDLE_PX / CASSIEN_IDLE_PX
	var lilith_scale := queen_scale * (LILITH_HEIGHT_CM / RAVIENNA_HEIGHT_CM) * RAVIENNA_IDLE_PX / LILITH_IDLE_PX
	var kael_scale := queen_scale * (KAEL_HEIGHT_CM / RAVIENNA_HEIGHT_CM) * RAVIENNA_IDLE_PX / KAEL_IDLE_PX
	var party_slot := 0
	var front_titan := actors.any(func(a):return is_playable_gerald(a))
	var titan_placed := false
	var enemy_slot := 0
	for entry in actors:
		var actor: BattlefieldActor = entry
		if actor.is_player and battlefield.arena_id == "gerald_boss_encounter" and actor.unit != null and actor.unit.def_id == "kael":
			_apply_kael_scale(actor, kael_scale)
			actor.set_home(Vector2(width * 0.28, height * 0.82))
			party_slot += 1
		elif is_instance_valid(actor.gerald_art):
			# Leave space for the full 384px authored earthquake cell.
			actor._base_scale = boss_titan_scale
			actor._sync_gerald_body_scale()
			var right_margin := 192.0 * boss_titan_scale + 16.0
			actor.set_home(Vector2(minf(width * 0.74, width - right_margin), height * 0.84))
			var hitbox := actor.get_node("Hitbox") as Control
			hitbox.position = Vector2(-35.0, -109.0) * boss_titan_scale
			hitbox.size = Vector2(70.0, 116.0) * boss_titan_scale
		elif is_instance_valid(actor.cassien_art) and not actor.is_player:
			actor.cassien_art.scale = Vector2.ONE * knight_scale
			actor._base_scale = knight_scale
			actor.set_home(Vector2(width * 0.77, height * 0.80))
			var hitbox := actor.get_node("Hitbox") as Control
			hitbox.position = Vector2(-36.0, -105.0) * knight_scale
			hitbox.size = Vector2(72.0, 115.0) * knight_scale
			var name_label := actor.get_node("NameLabel") as Label
			name_label.position = Vector2(-105.0, 22.0)
			name_label.size = Vector2(210.0, 16.0)
		elif actor.is_player:
			if is_playable_gerald(actor):
				actor._base_scale = titan_scale
				actor.visual.set_body_scale(titan_scale)
				var hitbox := actor.get_node("Hitbox") as Control
				hitbox.position = Vector2(-35.0,-110.0)*titan_scale
				hitbox.size = Vector2(70.0,116.0)*titan_scale
			if actor.unit != null and (actor.unit.def_id == "lilith" or actor.unit.def_id.begins_with("lilith_")):
				actor._base_scale = lilith_scale
				actor.visual.set_body_scale(lilith_scale)
				var hitbox := actor.get_node("Hitbox") as Control
				hitbox.position = Vector2(-36.0, -100.0) * lilith_scale
				hitbox.size = Vector2(72.0, 106.0) * lilith_scale
			if is_instance_valid(actor.elathra_art) or is_instance_valid(actor.cassien_art) or is_instance_valid(actor.ravienna_art):
				var art_scale := queen_scale if is_instance_valid(actor.ravienna_art) else (knight_scale if is_instance_valid(actor.cassien_art) else minf(1.15, height / 230.0))
				var art: Node2D = actor.elathra_art if is_instance_valid(actor.elathra_art) else (actor.cassien_art if is_instance_valid(actor.cassien_art) else actor.ravienna_art)
				art.scale = Vector2.ONE * art_scale
				actor._base_scale = art_scale
				var hitbox := actor.get_node("Hitbox") as Control
				hitbox.position = Vector2(-36.0, -105.0) * art_scale
				hitbox.size = Vector2(72.0, 115.0) * art_scale
			if actor.unit != null and (actor.unit.def_id == "kael" or actor.unit.def_id.begins_with("kael_")):
				_apply_kael_scale(actor, kael_scale)
			var slot := party_slot
			if front_titan:
				if is_playable_gerald(actor) and not titan_placed:
					slot = 0
					titan_placed = true
				else:
					slot = party_slot + (0 if titan_placed else 1)
			actor.set_home(Vector2(
				width * (Battlefield.PARTY_X + Battlefield.PARTY_DX * float(slot)),
				height * (Battlefield.PARTY_Y + Battlefield.PARTY_DY * float(slot))))
			party_slot += 1
		elif actor.unit != null and actor.unit.is_boss:
			if is_instance_valid(actor.ravienna_art):
				actor.ravienna_art.scale = Vector2.ONE * queen_scale
				actor._base_scale = queen_scale
				var hitbox := actor.get_node("Hitbox") as Control
				hitbox.position = Vector2(-36.0,-105.0)*queen_scale
				hitbox.size = Vector2(72.0,115.0)*queen_scale
			actor.set_home(Vector2(width * Battlefield.BOSS_X, height * Battlefield.BOSS_Y))
		else:
			actor.set_home(Vector2(
				width * (Battlefield.ENEMY_X + Battlefield.ENEMY_DX * float(enemy_slot)),
				height * (Battlefield.ENEMY_Y + Battlefield.ENEMY_DY * float(enemy_slot))))
			enemy_slot += 1
		if is_instance_valid(actor.live_art):
			var id := actor.unit.def_id
			var cm := float(LiveCharacterContent.installed.get(id,{}).get("heightCm",0))
			if cm<=0.0: cm=170.0
			if id.begins_with("gerald"): cm=GERALD_HEIGHT_CM
			elif id.begins_with("cassien"): cm=CASSIEN_HEIGHT_CM
			elif id.begins_with("ravienna"): cm=RAVIENNA_HEIGHT_CM
			elif id.begins_with("lilith"): cm=LILITH_HEIGHT_CM
			elif id.begins_with("kael"): cm=KAEL_HEIGHT_CM
			var size_px := maxf(1.0,float(LiveCharacterContent.installed.get(id,{}).get("height",128.0)))
			var fit := queen_scale * cm / RAVIENNA_HEIGHT_CM * RAVIENNA_IDLE_PX / size_px
			actor.live_art.scale=Vector2.ONE*fit
			actor._base_scale=fit
			var hitbox := actor.get_node("Hitbox") as Control
			hitbox.position=Vector2(-36.0,-size_px*fit)
			hitbox.size=Vector2(72.0,size_px*fit+8.0)
		actor.scale = Vector2.ONE
		if battlefield.arena_id == "revienna_encounter" and battlefield.get_window().size.x < 1000 and battlefield.get_window().size.x > battlefield.get_window().size.y:
			actor.scale = Vector2.ONE * minf(1.0, height / 270.0)
		if is_instance_valid(actor.ravienna_art) or (not actor.dead and not actor.gerald_walk_sequence_active and not actor.kael_boss_sequence_active):
			actor.position = actor.home_position
	# Recompute paths only after every combatant has its new formation slot.
	for entry in actors:
		var actor: BattlefieldActor = entry
		if actor.gerald_walk_sequence_active:
			actor.refresh_gerald_walk_position()
	if embers != null:
		embers.position = Vector2(width * 0.5, height * 0.55)
		embers.emission_rect_extents = Vector2(width * 0.5, height * 0.4)


func face_opponents() -> void:
	for entry in actors:
		var actor: BattlefieldActor = entry
		if actor.dead:
			continue
		actor.face(Vector2(1.0, 0.0) if actor.is_player else Vector2(-1.0, 0.0))


func refresh_actors() -> void:
	for entry in actors:
		var actor: BattlefieldActor = entry
		actor.refresh()


func set_active(uid: String) -> void:
	for entry in actors:
		var actor: BattlefieldActor = entry
		actor.set_active(actor.unit != null and actor.unit.uid == uid)


func set_target_team(team: int, enabled: bool) -> void:
	for entry in actors:
		var actor: BattlefieldActor = entry
		if actor.unit == null:
			continue
		actor.set_targetable(enabled and actor.unit.team == team and actor.unit.is_alive())


func _apply_kael_scale(actor: BattlefieldActor, body_scale: float) -> void:
	actor._base_scale = body_scale
	actor.visual.set_body_scale(body_scale)
	actor._sync_kael_boss_art()
	var hitbox := actor.get_node("Hitbox") as Control
	hitbox.position = Vector2(-38.0, -108.0) * body_scale
	hitbox.size = Vector2(76.0, 116.0) * body_scale