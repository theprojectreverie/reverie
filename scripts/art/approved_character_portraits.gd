extends RefCounted
const DIRECTORY = "res://assets/portraits/profile/"
const CHARACTERS = ["ravienna", "gerald", "lilith", "cassien", "mirene"]

static func path_for(id: String, ascension: int = 0) -> String:
	var base := id
	var tier := "legendary"
	for suffix in ["human", "ascended", "mythic", "legendary", "epic", "rare", "common"]:
		if id.ends_with("_" + suffix):
			base = id.trim_suffix("_" + suffix)
			if suffix in ["human", "ascended", "mythic", "legendary"]:
				tier = suffix
			break
	if not base in CHARACTERS:
		return ""
	if tier == "mythic" and ascension >= 3:
		tier = "ascended"
	if base == "mirene" and id in ["mirene", "mirene_common", "mirene_rare", "mirene_epic"]:
		return DIRECTORY + "mirene_base.jpg"
	var key := base + "_" + tier
	return DIRECTORY + key + (".jpg" if key == "gerald_mythic" else ".png")

static func texture(id: String, ascension: int = 0) -> Texture2D:
	var path := path_for(id, ascension)
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null

static func is_approved(texture_source: Texture2D) -> bool:
	return texture_source != null and texture_source.resource_path.begins_with(DIRECTORY)
