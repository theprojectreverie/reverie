class_name PlayerLocomotionComponent
extends Node
## Reusable locomotion component for a CharacterBody2D player actor.

const WALK_SPEED := 235.0
const RUN_SPEED := 350.0
const ACCELERATION := 1700.0
const FRICTION := 2100.0
const TURN_BRAKE_MULT := 1.8
const SPEED_BLEND_RATE := 10.0
const STOP_SNAP_SPEED := 18.0
const TOUCH_SPRINT_ENTER := 0.92
const TOUCH_SPRINT_EXIT := 0.80

## Subtle, readable weight differences; keep the party within one traversal
## speed band so avatar switching never changes level pacing dramatically.
const AVATAR_MOVEMENT := {
	"kael": {"walk": 235.0, "run": 350.0, "accel": 1700.0, "friction": 2100.0, "turn": 1.8},
	"gerald": {"walk": 218.0, "run": 322.0, "accel": 1480.0, "friction": 2280.0, "turn": 2.05},
	"lilith": {"walk": 246.0, "run": 362.0, "accel": 1840.0, "friction": 1940.0, "turn": 1.65},
}

@export_range(0.1, 2.0, 0.05) var movement_speed_multiplier: float = 1.0

var body: CharacterBody2D
var _speed_target: float = WALK_SPEED
var _touch_sprint: bool = false
var _in_water: bool = false
var _step_timer := 0.0
var _water_step_timer := 0.0
var _water_transition_cooldown := 0.0


func _ready() -> void:
	body = get_parent() as CharacterBody2D
	_speed_target = float(movement_profile(_avatar_id()).get("walk", WALK_SPEED)) * movement_speed_multiplier


static func movement_profile(character_id: String) -> Dictionary:
	return (AVATAR_MOVEMENT.get(character_id, AVATAR_MOVEMENT["kael"]) as Dictionary).duplicate(true)


func _avatar_id() -> String:
	return str(body.get("avatar_id")) if body != null else "kael"


func _physics_process(delta: float) -> void:
	physics_step(delta)


func physics_step(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	_water_transition_cooldown = maxf(0.0, _water_transition_cooldown - delta)
	var visual := body.get("visual") as ActorVisual
	var camera := body.get("camera") as Camera2D
	var enabled := bool(body.get("input_enabled")) and not bool(body.get("network_recovery_paused"))
	var facing: Vector2 = body.get("facing_direction")
	var profile := movement_profile(_avatar_id())
	var friction := float(profile.get("friction", FRICTION))
	if not enabled:
		AudioDirector.tick_lilith_exploration(body, delta, false)
		_step_timer = 0.0
		body.velocity = body.velocity.move_toward(Vector2.ZERO, friction * delta)
		body.move_and_slide()
		_sync_water_state(_water_depth_at(body.global_position), false)
		_water_step_timer = 0.0
		if visual != null:
			visual.walking = false
		visual_set_idle(visual)
		_touch_sprint = false
		_update_camera_follow(camera, delta, Vector2.ZERO, 0.0)
		GameState.session_domain.set_player_facing(facing)
		return

	var depth_before := _water_depth_at(body.global_position)
	var water_before := depth_before > 0.0
	var combat := body.get_node_or_null("WorldCombatComponent")
	if combat != null and combat.dodge_time > 0.0 and not water_before:
		body.velocity = combat.dodge_direction * 310.0 * movement_speed_multiplier
		body.move_and_slide()
		_sync_water_state(_water_depth_at(body.global_position), body.get_real_velocity().length() > STOP_SNAP_SPEED)
		if visual != null:
			visual.set_move_direction(combat.dodge_direction)
			visual.play(2)
		_update_camera_follow(camera, delta, body.velocity, 1.0)
		return
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var touch_driven := TouchInput.move_vector.length_squared() > 0.01
	if touch_driven:
		input_vector = TouchInput.move_vector
	input_vector = input_vector.limit_length(1.0)
	var sprinting := Input.is_action_pressed("sprint")
	if touch_driven:
		var push := input_vector.length()
		_touch_sprint = push >= (TOUCH_SPRINT_EXIT if _touch_sprint else TOUCH_SPRINT_ENTER)
		sprinting = sprinting or _touch_sprint
	else:
		_touch_sprint = false

	var stair_surface := body.get_tree().get_first_node_in_group("elevation_surface")
	if stair_surface != null and stair_surface.has_method("is_on_ramp") and bool(stair_surface.call("is_on_ramp", body.global_position)):
		sprinting = false
	if water_before:
		sprinting = false
	var nominal_speed: float = float(profile.get("run", RUN_SPEED)) if sprinting else float(profile.get("walk", WALK_SPEED))
	nominal_speed *= movement_speed_multiplier
	var speed: float = nominal_speed
	var in_water := water_before
	if in_water:
		speed *= lerpf(0.83, 0.55, depth_before)
	_speed_target = lerpf(_speed_target, speed, 1.0 - exp(-SPEED_BLEND_RATE * delta))

	if input_vector.length_squared() > 0.001:
		var accel: float = float(profile.get("accel", ACCELERATION))
		if body.velocity.length_squared() > 25.0:
			var align := body.velocity.normalized().dot(input_vector.normalized())
			if align < 0.3:
				var turn_brake := float(profile.get("turn", TURN_BRAKE_MULT))
				accel *= lerpf(turn_brake, 1.0, clampf((align + 1.0) / 1.3, 0.0, 1.0))
		var target_velocity := input_vector * _speed_target
		if stair_surface != null and stair_surface.has_method("project_motion"):
			target_velocity = stair_surface.call("project_motion", body.global_position, target_velocity)
		body.velocity = body.velocity.move_toward(target_velocity, accel * delta)
		if visual != null and absf(input_vector.x) > 0.08:
			visual.facing = 1.0 if input_vector.x > 0.0 else -1.0
		facing = input_vector.normalized()
		body.set("facing_direction", facing)
		GameState.session_domain.set_player_facing(facing)
	else:
		body.velocity = body.velocity.move_toward(Vector2.ZERO, friction * delta)
		if body.velocity.length() < STOP_SNAP_SPEED:
			body.velocity = Vector2.ZERO

	body.move_and_slide()
	var depth := _water_depth_at(body.global_position)
	in_water = depth > 0.0
	var actual_motion := body.get_real_velocity().length() > STOP_SNAP_SPEED and input_vector.length_squared() > 0.001
	_sync_water_state(depth, actual_motion)
	_tick_water_foley(delta, actual_motion)
	if in_water:
		sprinting = false
	var movement_ratio := clampf(body.velocity.length() / maxf(1.0, nominal_speed), 0.0, 1.0)
	var moving := body.velocity.length() > STOP_SNAP_SPEED
	AudioDirector.tick_lilith_exploration(body, delta, moving and body.get_real_velocity().length() > STOP_SNAP_SPEED and input_vector.length_squared() > 0.001)
	if actual_motion and not in_water and not _avatar_id().begins_with("lilith"):
		_step_timer -= delta
		if _step_timer <= 0.0:
			var region: String = AudioDirector._region_ambience_id if not AudioDirector._region_ambience_id.is_empty() else str(GameState.player_region)
			var surface := _surface_at(body.global_position, region)
			AudioDirector.play_variant(surface, -5.0, 1.0, true)
			_step_timer = 0.30 if sprinting else 0.44
	else:
		_step_timer = 0.0
	var direction: Vector2 = body.velocity.normalized() if moving else (input_vector if input_vector.length_squared() > 0.001 else facing)
	if visual != null:
		visual.set_move_direction(direction)
		visual.walking = moving
		if moving:
			var playback := (1.40 if sprinting else 1.36) * lerpf(0.55, 1.0, movement_ratio)
			visual.play(2 if sprinting else 1, -1, playback)
			if body.velocity.length_squared() > 1.0:
				facing = body.velocity.normalized()
				body.set("facing_direction", facing)
				GameState.session_domain.set_player_facing(facing)
		else:
			visual.play(0, -1, 1.0)
	_update_camera_follow(camera, delta, body.velocity, movement_ratio)


func _sync_water_state(depth: float, actual_motion: bool) -> void:
	var wet := depth > 0.0
	if wet != _in_water:
		_in_water = wet
		_water_step_timer = 0.62 if wet else 0.0
		_step_timer = 0.30
		if actual_motion and _water_transition_cooldown <= 0.0:
			AudioDirector.play_variant("water_entry" if wet else "water_step", -8.0 if wet else -13.0, 1.0, true)
			_water_transition_cooldown = 0.30
			if wet:
				body.get_node("PresentationComponent").play_water_splash(true)
	body.call("_update_water_visual", wet, depth)


func _tick_water_foley(delta: float, actual_motion: bool) -> void:
	if not _in_water or not actual_motion:
		return
	_water_step_timer -= delta
	if _water_step_timer <= 0.0:
		var pitch := randf_range(0.90, 1.10) * (0.88 if _avatar_id().begins_with("gerald") else 1.0)
		AudioDirector.play_variant("water_step", -12.0 if _avatar_id().begins_with("lilith") else -9.0, pitch, true)
		body.get_node("PresentationComponent").play_water_splash(false)
		_water_step_timer = 0.58


func _water_at(point: Vector2) -> bool:
	return _water_depth_at(point) > 0.0


func _water_depth_at(point: Vector2) -> float:
	var bridge := get_tree().get_first_node_in_group("willow_bridge_surface")
	if bridge != null and bridge.has_method("is_on_deck") and bool(bridge.call("is_on_deck", point)):
		return 0.0
	for node in get_tree().get_nodes_in_group("wade_water_surface"):
		var pool := node as Polygon2D
		if pool == null or not pool.is_visible_in_tree():
			continue
		var local := pool.to_local(point)
		if not Geometry2D.is_point_in_polygon(local, pool.polygon):
			continue
		var edge_distance := INF
		for i in range(pool.polygon.size()):
			var nearest := Geometry2D.get_closest_point_to_segment(local, pool.polygon[i], pool.polygon[(i + 1) % pool.polygon.size()])
			edge_distance = minf(edge_distance, point.distance_to(pool.to_global(nearest)))
		return clampf(edge_distance / 48.0, 0.08, 1.0)
	var world := get_tree().get_first_node_in_group("world") as Node2D
	return 1.0 if world != null and world.has_method("is_water_world") and bool(world.call("is_water_world", world.to_local(point))) else 0.0


func _update_camera_follow(camera: Camera2D, delta: float, move_velocity: Vector2, ratio: float) -> void:
	if camera is PlayerCameraRig:
		var camera_rig := camera as PlayerCameraRig
		camera_rig.update_follow_offset(delta, move_velocity, ratio)
		# Move the top-level camera in the same physics tick as CharacterBody2D.
		# Waiting for its render-frame callback leaves a one-frame positional lag.
		camera_rig.sync_follow_target()


func visual_set_idle(visual: ActorVisual) -> void:
	if visual != null:
		visual.set_move_direction(Vector2.ZERO)
		visual.play(0)

# Cache authored terrain sprite positions in a spatial grid; no artwork changes.
var _surface_bins: Dictionary = {}
var _surface_scene: Node
var _surface_world: Node
var _surface_tile_layers: Array[TileMapLayer] = []
const SURFACE_BIN := 128.0

func _surface_at(point: Vector2, region: String) -> String:
	var bridge := get_tree().get_first_node_in_group("willow_bridge_surface")
	if bridge != null and bridge.has_method("is_on_deck") and bool(bridge.call("is_on_deck", point)):
		return "wood_step"
	var scene := get_tree().current_scene
	var world := get_tree().get_first_node_in_group("world")
	if scene != _surface_scene or world != _surface_world:
		_surface_scene = scene
		_surface_world = world
		_surface_bins.clear()
		_surface_tile_layers.clear()
		if scene != null:
			_index_surface(scene)
	var cell := Vector2i(floori(point.x / SURFACE_BIN), floori(point.y / SURFACE_BIN))
	var best := ""
	var best_z := -INF
	for item in _surface_bins.get(cell, []):
		var sprite: Sprite2D = item[0]
		if not is_instance_valid(sprite) or not sprite.is_visible_in_tree():
			continue
		var local := sprite.to_local(point)
		var rect := sprite.get_rect()
		var half := rect.size * 0.5
		if half.x <= 0 or half.y <= 0:
			continue
		var relative := local - rect.get_center()
		if absf(relative.x) / half.x + absf(relative.y) / half.y > 1.0:
			continue
		var depth: float = item[2]
		if depth >= best_z:
			best_z = depth
			best = item[1]
	for layer in _surface_tile_layers:
		if not is_instance_valid(layer):
			continue
		var kind := _tile_surface(layer, point)
		if kind.is_empty():
			continue
		var depth := _surface_depth(layer)
		if depth > best_z or (depth == best_z and (best.is_empty() or best == "grass_step" or kind != "grass_step")):
			best_z = depth
			best = kind
	if not best.is_empty():
		return best
	# Unknown terrain must not sound like foliage just because the region is green.
	return "stone_step" if region in ["training_ground", "royal_gate", "gothic_castle_boss_zone", "pearl_city"] else "dirt_step"

# Material comes from authored surface metadata first, then the specific art filename.
# Do not classify trees, fences, roofs, foliage props, or entire environment folders.
func _surface_material(path: String) -> String:
	var key := path.get_file().get_basename().to_lower()
	for token in ["wood_floor", "wooden_floor", "wood_plank", "wooden_plank", "plank_floor", "wooden_bridge", "wood_bridge", "wood_deck", "wooden_deck"]:
		if token in key and not ("rail" in key or "post" in key):
			return "wood_step"
	for token in ["dirt", "soil", "earth", "sand", "mud", "plum_ground", "bare_ground"]:
		if token in key and not ("tuft" in key or "prop" in key or "plant" in key):
			return "dirt_step"
	for token in ["stone_path", "path_stone", "stone_road", "path_cobble", "cobblestone", "marble", "paving", "pavement", "stone_floor", "arena_floor", "courtyard_floor", "decorative_floor", "path_ruined", "path_rune_tile", "path_corrupted_stone", "path_curved", "path_intersection", "cracked_stone", "mossy_stone", "floor_tile", "floor_plain", "floor_gold", "floor_star", "floor_quatrefoil", "bridge_stone", "stone_bridge"]:
		if token in key and not ("post" in key or "rail" in key or "wall" in key):
			return "stone_step"
	if "grass" in key and not ("tuft" in key or "foliage" in key or "cliff" in key or "vegetation" in key):
		return "grass_step"
	if "artist_road_transitions" in path.to_lower() or "road_polish" in path.to_lower():
		return "dirt_step"
	return ""


func _surface_override(node: Node) -> String:
	if node.has_meta("footstep_surface"):
		var kind := str(node.get_meta("footstep_surface"))
		if kind in ["wood_step", "dirt_step", "stone_step", "grass_step"]:
			return kind
	return ""


func _surface_depth(node: CanvasItem) -> int:
	var depth := 0
	var ancestor: Node = node
	while ancestor is CanvasItem:
		depth += ancestor.z_index
		if not ancestor.z_as_relative:
			break
		ancestor = ancestor.get_parent()
	return depth


func _tile_surface(layer: TileMapLayer, point: Vector2) -> String:
	if not layer.enabled or not layer.is_visible_in_tree() or layer.tile_set == null:
		return ""
	var coords := layer.local_to_map(layer.to_local(point))
	var source_id := layer.get_cell_source_id(coords)
	if source_id < 0:
		return ""
	var data := layer.get_cell_tile_data(coords)
	if data != null and layer.tile_set.get_custom_data_layer_by_name("footstep_surface") >= 0:
		var custom := str(data.get_custom_data("footstep_surface"))
		if custom in ["wood_step", "dirt_step", "stone_step", "grass_step"]:
			return custom
	var override := _surface_override(layer)
	if not override.is_empty():
		return override
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or source.texture == null:
		return ""
	return _surface_material(source.texture.resource_path)


func _index_surface(node: Node) -> void:
	if node is TileMapLayer:
		_surface_tile_layers.append(node as TileMapLayer)
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			var path := sprite.texture.resource_path.to_lower()
			var parent_path := sprite.get_parent().scene_file_path.to_lower()
			var kind := _surface_override(sprite)
			if kind.is_empty():
				kind = _surface_override(sprite.get_parent())
			if kind.is_empty():
				kind = _surface_material(path)
			if kind.is_empty():
				kind = _surface_material(parent_path)
			if not kind.is_empty():
				var rect := sprite.get_rect()
				var bounds := Rect2(sprite.to_global(rect.position), Vector2.ZERO)
				for corner in [rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y)]:
					bounds = bounds.expand(sprite.to_global(corner))
				var lo := Vector2i(floori(bounds.position.x / SURFACE_BIN), floori(bounds.position.y / SURFACE_BIN))
				var hi := Vector2i(floori(bounds.end.x / SURFACE_BIN), floori(bounds.end.y / SURFACE_BIN))
				var depth := 0
				var ancestor: Node = sprite
				while ancestor is CanvasItem:
					depth += ancestor.z_index
					if not ancestor.z_as_relative:
						break
					ancestor = ancestor.get_parent()
				for x in range(lo.x, hi.x + 1):
					for y in range(lo.y, hi.y + 1):
						var cell := Vector2i(x, y)
						if not _surface_bins.has(cell):
							_surface_bins[cell] = []
						_surface_bins[cell].append([sprite, kind, depth])
	for child in node.get_children():
		_index_surface(child)