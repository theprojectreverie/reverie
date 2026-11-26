extends RefCounted

static func definition(id: String) -> Dictionary:
	for banner in ContentDB.banners.values():
		var mob: Dictionary = banner.get("common_rewards", {}).get(id, {})
		if not mob.is_empty():
			return mob
	return {}

static func texture(mob: Dictionary) -> Texture2D:
	var source := load(str(mob.get("art", ""))) as Texture2D
	if source == null:
		return null
	var cell: Array = mob.get("cell", [64, 64])
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(0, 0, int(cell[0]), int(cell[1]))
	atlas.filter_clip = true
	return atlas

static func description(items: Dictionary) -> String:
	var parts: Array[String] = []
	for id in items:
		parts.append("%s x%d" % [str(ContentDB.get_item(id).get("name", id)), int(items[id])])
	return ", ".join(parts)
