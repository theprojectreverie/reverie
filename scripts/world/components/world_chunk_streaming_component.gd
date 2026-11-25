class_name WorldChunkStreamingComponent
extends Node
## Tracks nearby chunk coordinates. It does not prepare or generate visual chunks.

var world: GreenwardWorld
var streamer: ChunkStreamer
var preparer: ChunkPreparer
var prepared_nodes: Dictionary = {}


func configure(owner_world: GreenwardWorld, chunk_size: int, load_radius: int) -> void:
	world = owner_world
	streamer = ChunkStreamer.new(chunk_size, load_radius)
	# Kept as a null compatibility field for existing world teardown callers.
	preparer = null
	prepared_nodes.clear()


func update_streaming(player_grid: Vector2) -> void:
	if world == null or streamer == null:
		return
	var needed: Array = streamer.needed_chunks(player_grid)
	var needed_set: Dictionary = {}
	for coord in needed:
		needed_set[coord] = true
	for coord in world.loaded_chunks.keys():
		if not needed_set.has(coord):
			world._unload_chunk(coord)
	for coord in needed:
		if not world.loaded_chunks.has(coord):
			world._load_chunk(coord)


func prepare_one_chunk(_player_grid: Vector2) -> void:
	# Procedural chunk preparation has been removed.
	return


func reconcile_prepared_cache() -> void:
	prepared_nodes.clear()


func clear_prepared() -> void:
	prepared_nodes.clear()


func _exit_tree() -> void:
	clear_prepared()


func free_chunk_data(_data: Dictionary) -> void:
	# No generated chunk nodes are retained or prepared.
	return
