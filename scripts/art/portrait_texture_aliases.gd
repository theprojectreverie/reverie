extends RefCounted
## Exact duplicate collection portraits share one imported texture.
## Character identity, ownership, rarity and crop focus remain independent.
## Remove an alias and its export exclusion when authoring distinct art for that ID.
const COLLECTION_FOLDERS := {
	"elathra_mythic": "elathra",
	"caelith_common": "caelith_mythic",
	"caelith_epic": "caelith_mythic",
	"caelith_legendary": "caelith_mythic",
	"cassien_common": "cassien",
	"cassien_epic": "cassien",
	"cassien_legendary": "cassien",
	"cassien_mythic": "cassien",
	"crimson_witch_common": "crimson_witch_mythic",
	"crimson_witch_epic": "crimson_witch_mythic",
	"crimson_witch_legendary": "crimson_witch_mythic",
	"gerald": "gerald_mythic",
	"gerald_common": "gerald_mythic",
	"gerald_epic": "gerald_mythic",
	"gerald_legendary": "gerald_mythic",
	"kael_common": "kael_mythic",
	"kael_epic": "kael_mythic",
	"kael_legendary": "kael_mythic",
	"lilith_common": "lilith_mythic",
	"lilith_epic": "lilith_mythic",
	"lilith_legendary": "lilith_mythic",
	"mirene_common": "mirene",
	"mirene_epic": "mirene",
	"mirene_legendary": "mirene",
	"mirene_mythic": "mirene",
	"nyx_common": "nyx_mythic",
	"nyx_epic": "nyx_mythic",
	"nyx_rare": "nyx_mythic",
	"ravienna_common": "ravienna_mythic",
	"ravienna_epic": "ravienna_mythic",
	"ravienna_rare": "ravienna_mythic",
}

static func collection_path(character_id: String) -> String:
	return "res://assets/characters/%s/portrait_512.png" % str(COLLECTION_FOLDERS.get(character_id, character_id))
