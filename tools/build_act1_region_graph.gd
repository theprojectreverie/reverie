extends SceneTree

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var path := "res://resources/data/regions.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open regions.json")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("regions.json is not a dictionary")
		quit(1)
	var data: Dictionary = parsed
	var regions := {
		"royal_gate": {
			"name":"Royal Gate","subtitle":"The last golden threshold before the open country",
			"chunk_size":16,"tile_width":64,"tile_height":32,"load_radius":1,"noise_seed":61001,
			"spawn_grid":[8,8],"clearing_radius":5.0,
			"biome":{"water_level":-0.76,"deep_water_level":-0.90,"grass_colors":["#526b43","#74854c","#9a9857","#6d7844"],"path_color":"#b49b78","water_shallow":"#64949a","water_deep":"#315a67"},
			"props":[{"type":"blossom_tree","weight":0.28,"min_elevation":-0.1},{"type":"glade_tree","weight":0.18,"min_elevation":-0.1},{"type":"flower_cluster","weight":0.34,"min_elevation":-0.1},{"type":"rock","weight":0.08,"min_elevation":-0.05},{"type":"bush","weight":0.2,"min_elevation":-0.1}],
			"pois":[{"id":"royal_gate_landmark","name":"Royal Gate","grid":[8,8],"type":"landmark"},{"id":"road_warden","name":"Road Warden Elowen","grid":[10,6],"type":"npc","npc_id":"road_warden_elowen","dialogue_id":"road_warden_elowen","race":"Human","role":"Royal Warden","palette":{"hair":"#d9b7a2","primary":"#536b7a","secondary":"#b69a69","accent":"#f2d7a5","skin":"#e8c5ad"}},{"id":"old_milestone","name":"The King's Milestone","grid":[20,12],"type":"ruin"}],
			"spawns":[{"group":"glade_mossling_pack","grid":[23,5],"radius":2.5,"count":1}],
			"world_origin":[12288,0],"environment":{"zone":"royal_road","weather_bias":["clear","mist"],"fog_density":0.1,"ambient_tint":"#f0d6a5","ambient_music":""},
			"entry_points":{"gate_arrival":[8,8],"garden_return":[5,8],"willow_road":[34,14]},
			"connections":[{"id":"royal_gate_return","to":"castle_royal_gardens","via":"garden_return","entry":"boss_path","kind":"gate","label":"Return to Royal Gardens"},{"id":"royal_gate_to_willow","to":"willow_fields","via":"willow_road","entry":"royal_gate","kind":"road","label":"Willow Fields"}]
		},
		"willow_fields": {
			"name":"Willow Fields","subtitle":"A warm pastoral valley of wheat, windmills and flowering hedgerows",
			"chunk_size":16,"tile_width":64,"tile_height":32,"load_radius":1,"noise_seed":61002,
			"spawn_grid":[8,8],"clearing_radius":5.0,
			"biome":{"water_level":-0.78,"deep_water_level":-0.92,"grass_colors":["#6d8748","#9b9b50","#c2ad5b","#7f8e49"],"path_color":"#c0a174","water_shallow":"#65999a","water_deep":"#315d68"},
			"props":[{"type":"glade_tree","weight":0.12,"min_elevation":-0.1},{"type":"blossom_tree","weight":0.1,"min_elevation":-0.1},{"type":"flower_cluster","weight":0.42,"min_elevation":-0.1},{"type":"tall_grass","weight":0.34,"min_elevation":-0.1},{"type":"bush","weight":0.25,"min_elevation":-0.1},{"type":"rock","weight":0.04,"min_elevation":0.0}],
			"pois":[{"id":"willow_fields_windmill","name":"Willow Fields Windmill","grid":[22,10],"type":"landmark"},{"id":"golden_meadow","name":"Golden Meadow","grid":[14,20],"type":"landmark"},{"id":"millpond","name":"Millpond","grid":[32,22],"type":"landmark"},{"id":"miller_ada","name":"Miller Ada","grid":[24,12],"type":"npc","npc_id":"miller_ada","dialogue_id":"miller_ada","race":"Human","role":"Windmill Keeper","palette":{"hair":"#9a604b","primary":"#9a7049","secondary":"#e0c078","accent":"#f2d9a1","skin":"#e9c3a5"}}],
			"spawns":[{"group":"glade_mossling_pack","grid":[36,5],"radius":3,"count":1},{"group":"thornhound_hunt","grid":[40,26],"radius":3,"count":1}],
			"world_origin":[16384,0],"environment":{"zone":"pastoral_fields","weather_bias":["clear","rain"],"fog_density":0.08,"ambient_tint":"#f3e4a8","ambient_music":""},
			"entry_points":{"royal_gate":[8,8],"gate_return":[5,8],"grove_entry":[48,18]},
			"connections":[{"id":"willow_to_gate","to":"royal_gate","via":"gate_return","entry":"willow_road","kind":"road","label":"Royal Gate"},{"id":"willow_to_grove","to":"elderwood_grove","via":"grove_entry","entry":"willow_entry","kind":"road","label":"Elderwood Grove"}]
		},
		"elderwood_grove": {
			"name":"Elderwood Grove","subtitle":"A violet-canopied ancient woodland where the first blight takes root",
			"chunk_size":16,"tile_width":64,"tile_height":32,"load_radius":1,"noise_seed":61003,
			"spawn_grid":[8,8],"clearing_radius":4.5,
			"biome":{"water_level":-0.74,"deep_water_level":-0.90,"grass_colors":["#334b3b","#455b43","#625d52","#3d4d43"],"path_color":"#8d806d","water_shallow":"#416f79","water_deep":"#203e52"},
			"props":[{"type":"ancient_tree","weight":0.22,"min_elevation":0.0},{"type":"willow_tree","weight":0.22,"min_elevation":-0.1},{"type":"glade_tree","weight":0.16,"min_elevation":-0.1},{"type":"moss_rock","weight":0.18,"min_elevation":-0.1},{"type":"glow_mushroom","weight":0.28,"min_elevation":-0.1},{"type":"spirit_bloom","weight":0.14,"min_elevation":-0.05},{"type":"fern","weight":0.38,"min_elevation":-0.1}],
			"pois":[{"id":"elderwood_heart","name":"Elderwood Heart","grid":[26,18],"type":"ruin"},{"id":"ancient_watch","name":"The Watcher Tree","grid":[18,10],"type":"landmark"},{"id":"moonwell","name":"Moonwell Spring","grid":[36,28],"type":"shrine"},{"id":"grove_keeper","name":"Grove Keeper Thalen","grid":[23,20],"type":"npc","npc_id":"grove_keeper_thalen","dialogue_id":"grove_keeper_thalen","race":"Fae","role":"Elderwood Keeper","palette":{"hair":"#c6d2bd","primary":"#405b4a","secondary":"#8b6c9c","accent":"#c6a7e8","skin":"#dfc4ae"}}],
			"spawns":[{"group":"fae_ambush","grid":[15,18],"radius":3,"count":1},{"group":"thornhound_hunt","grid":[35,12],"radius":3,"count":2}],
			"world_origin":[20480,0],"environment":{"zone":"corrupted_grove","weather_bias":["mist","rain"],"fog_density":0.28,"ambient_tint":"#b49ad2","ambient_music":""},
			"entry_points":{"willow_entry":[8,8],"willow_return":[5,8],"ruins_path":[48,18]},
			"connections":[{"id":"grove_to_willow","to":"willow_fields","via":"willow_return","entry":"grove_entry","kind":"road","label":"Willow Fields"},{"id":"grove_to_ruins","to":"forsaken_ruins","via":"ruins_path","entry":"grove_entry","kind":"road","label":"Forsaken Ruins"}]
		},
		"forsaken_ruins": {
			"name":"Forsaken Ruins","subtitle":"A shattered royal aqueduct and forgotten shrine overtaken by crimson corruption",
			"chunk_size":16,"tile_width":64,"tile_height":32,"load_radius":1,"noise_seed":61004,
			"spawn_grid":[8,8],"clearing_radius":4.0,
			"biome":{"water_level":-0.72,"deep_water_level":-0.90,"grass_colors":["#3e4642","#554d52","#66505a","#41434a"],"path_color":"#82777d","water_shallow":"#495d73","water_deep":"#252c43"},
			"props":[{"type":"dead_tree","weight":0.18,"min_elevation":-0.1},{"type":"ruin_pillar","weight":0.28,"min_elevation":-0.1},{"type":"crystal","weight":0.16,"min_elevation":-0.1},{"type":"moss_rock","weight":0.22,"min_elevation":-0.1},{"type":"glow_mushroom","weight":0.12,"min_elevation":-0.1},{"type":"flower_cluster","weight":0.06,"min_elevation":-0.1}],
			"pois":[{"id":"forsaken_arch","name":"Forsaken Arch","grid":[22,16],"type":"ruin"},{"id":"fallen_aqueduct","name":"Fallen Aqueduct","grid":[34,10],"type":"ruin"},{"id":"corrupted_shrine","name":"Corrupted Shrine","grid":[34,28],"type":"shrine"},{"id":"ruin_scout","name":"Scout Merrow","grid":[18,14],"type":"npc","npc_id":"scout_merrow","dialogue_id":"scout_merrow","race":"Human","role":"Royal Scout","palette":{"hair":"#554b48","primary":"#59616d","secondary":"#8e505a","accent":"#9cc8d7","skin":"#d8b39d"}}],
			"spawns":[{"group":"fae_ambush","grid":[15,25],"radius":3,"count":1},{"group":"corrupted_treant","grid":[32,20],"radius":1,"count":1}],
			"world_origin":[24576,0],"environment":{"zone":"gothic_ruins","weather_bias":["mist","rain"],"fog_density":0.36,"ambient_tint":"#c08bc5","ambient_music":""},
			"entry_points":{"grove_entry":[8,8],"grove_return":[5,8],"tower_approach":[48,16]},
			"connections":[{"id":"ruins_to_grove","to":"elderwood_grove","via":"grove_return","entry":"ruins_path","kind":"road","label":"Elderwood Grove"},{"id":"ruins_to_tower","to":"ruined_tower","via":"tower_approach","entry":"ruins_entry","kind":"road","label":"Ruined Tower"}]
		},
		"ruined_tower": {
			"name":"Ruined Tower","subtitle":"The final violet spire above the shattered road, guarding the sealed keep",
			"chunk_size":16,"tile_width":64,"tile_height":32,"load_radius":1,"noise_seed":61005,
			"spawn_grid":[8,8],"clearing_radius":4.0,
			"biome":{"water_level":-0.76,"deep_water_level":-0.92,"grass_colors":["#343747","#494154","#5a455d","#343b4b"],"path_color":"#82748b","water_shallow":"#4d5e7c","water_deep":"#211f3d"},
			"props":[{"type":"dead_tree","weight":0.2,"min_elevation":-0.1},{"type":"ruin_pillar","weight":0.24,"min_elevation":-0.1},{"type":"crystal","weight":0.3,"min_elevation":-0.1},{"type":"moss_rock","weight":0.16,"min_elevation":-0.1},{"type":"glow_mushroom","weight":0.18,"min_elevation":-0.1}],
			"pois":[{"id":"ruined_tower_landmark","name":"Ruined Tower","grid":[24,10],"type":"landmark"},{"id":"moon_shard","name":"Moon Shard Obelisk","grid":[34,22],"type":"shrine"},{"id":"tower_sentinel","name":"Tower Sentinel","grid":[20,12],"type":"npc","npc_id":"tower_sentinel","dialogue_id":"tower_sentinel","race":"Fae","role":"Violet Sentinel","palette":{"hair":"#ded4e8","primary":"#4b4268","secondary":"#8c6ab0","accent":"#d7a5ff","skin":"#e6c6bb"}}],
			"spawns":[{"group":"fallen_aqueduct_sentinels","grid":[18,22],"radius":2,"count":1}],
			"world_origin":[28672,0],"environment":{"zone":"gothic_ruins","weather_bias":["mist","clear"],"fog_density":0.42,"ambient_tint":"#b69aff","ambient_music":""},
			"entry_points":{"ruins_entry":[8,8],"ruins_return":[5,8],"sealed_keep":[42,8]},
			"connections":[{"id":"tower_to_ruins","to":"forsaken_ruins","via":"ruins_return","entry":"tower_approach","kind":"road","label":"Forsaken Ruins"},{"id":"tower_to_keep","to":"gothic_castle_boss_zone","via":"sealed_keep","entry":"royal_gate","kind":"gate","label":"The Sealed Keep"}]
		}
	}
	for id in regions:
		data[id] = regions[id]
	# The Royal Gardens now lead into the six-stop Act I road progression.
	var gardens: Dictionary = data.get("castle_royal_gardens", {})
	gardens["entry_points"]["greenward_return"] = [10,12]
	gardens["connections"] = [
		{"id":"gardens_to_royal_gate","to":"royal_gate","via":"boss_path","entry":"gate_arrival","kind":"gate","label":"The Royal Road"},
		{"id":"gardens_to_greenward","to":"greenward","via":"greenward_return","entry":"royal_road","kind":"gate","label":"Return to Greenward"}
	]
	data["castle_royal_gardens"] = gardens
	var greenward: Dictionary = data.get("greenward", {})
	greenward["entry_points"]["royal_road"] = [18,10]
	var greenward_connections: Array = greenward.get("connections", [])
	for connection_index in range(greenward_connections.size() - 1, -1, -1):
		if str(greenward_connections[connection_index].get("id", "")) == "greenward_to_royal_gardens":
			greenward_connections.remove_at(connection_index)
	greenward_connections.append({"id":"greenward_to_royal_gardens","to":"castle_royal_gardens","via":"royal_road","entry":"greenward_return","kind":"gate","label":"Royal Gardens"})
	greenward["connections"] = greenward_connections
	data["greenward"] = greenward
	# The Gothic Castle's return gate now leads to the final approach region.
	var gothic: Dictionary = data.get("gothic_castle_boss_zone", {})
	gothic["world_origin"] = [32768, 0]
	gothic["entry_points"]["tower_return"] = [4,0]
	gothic["connections"] = [{"id":"keep_to_ruined_tower","to":"ruined_tower","via":"tower_return","entry":"sealed_keep","kind":"gate","label":"Return to the Ruined Tower"}]
	data["gothic_castle_boss_zone"] = gothic
	for region_id in data.keys():
		var region_def: Dictionary = data[region_id]
		for connection in region_def.get("connections", []):
			if str(connection.get("kind", "")) == "road":
				connection["kind"] = "path"
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(data, "\t"))
	out.close()
	print("ACT1_REGIONS_WRITTEN ", regions.size(), " total_regions=", data.size())
	quit()
