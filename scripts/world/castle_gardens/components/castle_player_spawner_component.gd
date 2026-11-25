class_name CastlePlayerSpawnerComponent
extends Node
## Owns player instantiation and restoration for Royal Gardens.

const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
var world: CastleRoyalGardens

func bind(owner_world: CastleRoyalGardens) -> void:
	world = owner_world

func spawn_player() -> Player:
	if world == null or world.entities == null:
		push_error("CastlePlayerSpawner requires a bound world and authored Entities layer.")
		return null
	var actor := PLAYER_SCENE.instantiate() as Player
	if actor == null:
		push_error("CastlePlayerSpawner could not instantiate Player.")
		return null
	actor.name = "Player"
	var placed := false
	if not world.entry_point.is_empty():
		var entries: Variant = ContentDB.get_region(world.region_id).get("entry_points", {})
		if typeof(entries) == TYPE_DICTIONARY and (entries as Dictionary).has(world.entry_point):
			var grid: Variant = (entries as Dictionary)[world.entry_point]
			if typeof(grid) == TYPE_ARRAY and (grid as Array).size() == 2:
				actor.position = IsoMath.grid_to_world(float(grid[0]), float(grid[1]))
				placed = true
	if not placed and GameState.session_domain.player_region == world.region_id and GameState.session_domain.has_region_position(world.region_id):
		var saved := GameState.session_domain.region_position(world.region_id)
		if saved.length_squared() > 1.0:
			actor.position = saved
			placed = true
	if not placed and GameState.session_domain.has_player_position and GameState.session_domain.player_region == world.region_id:
		actor.position = GameState.session_domain.player_position
		placed = true
	if not placed:
		actor.position = world.get_spawn_position("PlayerSpawn")
	var spawn := actor.position
	world.entities.add_child(actor)
	var camera_rig := actor.get_node_or_null("Camera2D") as PlayerCameraRig
	if camera_rig != null:
		camera_rig.set_base_zoom(0.62 / maxf(world.global_scale.x, 0.001))
		# Keep the camera viewport inside the authored ground rectangle when the
		# player approaches an outer edge of the large garden map.
		# Keep the viewport edge inside the baked ground; a half-tile inset avoids
		# sampling beyond the last covered diamond at extreme camera positions.
		var bounds_min := world.to_global(CastleLayout.SCREEN_MIN + CastleLayout.CAMERA_EDGE_PADDING)
		var bounds_max := world.to_global(CastleLayout.SCREEN_MAX - CastleLayout.CAMERA_EDGE_PADDING)
		camera_rig.set_world_bounds(bounds_min, bounds_max)
	actor.global_position = world.entities.to_global(spawn)
	# A saved position can become enclosed by newly authored castle collision
	# footprints after a map revision. Restore the authored spawn if trapped.
	if _is_spawn_trapped(actor):
		push_warning("Saved Royal Gardens position is obstructed; restoring PlayerSpawn.")
		actor.position = world.get_spawn_position("PlayerSpawn")
		actor.global_position = world.entities.to_global(actor.position)
		spawn = actor.position
	if actor.has_method("reset_physics_interpolation"):
		actor.reset_physics_interpolation()
	if actor.has_method("restore_facing"):
		actor.restore_facing(GameState.session_domain.player_facing)
	if camera_rig != null:
		# Snap the first frame to the restored spawn; smoothing is for movement,
		# not for a multi-second startup pan from world origin.
		camera_rig.sync_follow_target()
		camera_rig.reset_smoothing()
	world.player = actor
	GameState.session_domain.set_player_region(world.region_id)
	GameState.session_domain.set_player_position(actor.position)
	GameState.session_domain.set_region_position(world.region_id, actor.position)
	return actor
func _is_spawn_trapped(actor: Player) -> bool:
	var clear_directions := 0
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if not actor.test_move(actor.global_transform, direction * 28.0):
			clear_directions += 1
	return clear_directions < 2





