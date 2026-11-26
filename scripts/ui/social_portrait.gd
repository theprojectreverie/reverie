extends RefCounted
const PATHS = {
    "kael_avatar": "portrait.png",
    "elathra": "portrait.png",
    "gerald": "portrait.png",
    "lilith": "portrait.png",
    "cassien": "portrait_512.png",
    "caelith": "portrait_512.png",
    "ravienna": "portrait_512.png",
    "nyx": "portrait_512.png",
    "crimson_witch": "portrait_512.png",
    "mirene": "portrait_512.png",
    "kael_common": "portrait_512.png",
    "kael_epic": "portrait_512.png",
    "kael_legendary": "portrait_512.png",
    "kael_mythic": "portrait_512.png",
    "lilith_common": "portrait_512.png",
    "lilith_epic": "portrait_512.png",
    "lilith_legendary": "portrait_512.png",
    "lilith_mythic": "portrait_512.png",
    "gerald_common": "portrait_512.png",
    "gerald_epic": "portrait_512.png",
    "gerald_legendary": "portrait_512.png",
    "gerald_mythic": "portrait_512.png",
    "ravienna_common": "portrait_512.png",
    "ravienna_rare": "portrait_512.png",
    "ravienna_epic": "portrait_512.png",
    "ravienna_mythic": "portrait_512.png",
    "cassien_common": "portrait_512.png",
    "cassien_epic": "portrait_512.png",
    "cassien_legendary": "portrait_512.png",
    "cassien_mythic": "portrait_512.png",
    "nyx_common": "portrait_512.png",
    "nyx_rare": "portrait_512.png",
    "nyx_epic": "portrait_512.png",
    "nyx_mythic": "portrait_512.png",
    "crimson_witch_common": "portrait_512.png",
    "crimson_witch_epic": "portrait_512.png",
    "crimson_witch_legendary": "portrait_512.png",
    "crimson_witch_mythic": "portrait_512.png",
    "mirene_common": "portrait_512.png",
    "mirene_epic": "portrait_512.png",
    "mirene_legendary": "portrait_512.png",
    "mirene_mythic": "portrait_512.png",
    "caelith_common": "portrait_512.png",
    "caelith_epic": "portrait_512.png",
    "caelith_legendary": "portrait_512.png",
    "caelith_mythic": "portrait_512.png"
}
static func texture(id: String) -> Texture2D:
	if not PATHS.has(id):id="kael_avatar"
	var path := "res://assets/characters/%s/%s" % [id,PATHS[id]]
	if PATHS[id] == "portrait_512.png":
		path = preload("res://scripts/art/portrait_texture_aliases.gd").collection_path(id)
	var source := load(path) as Texture2D if ResourceLoader.exists(path) else null
	return preload("res://scripts/ui/portrait_framing.gd").fitted(source,id,1.0,"icon")
