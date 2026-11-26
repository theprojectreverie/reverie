extends SceneTree

const ALIASES := preload("res://scripts/art/portrait_texture_aliases.gd")
const SOCIAL := preload("res://scripts/ui/social_portrait.gd")
const FRAMING := preload("res://scripts/ui/portrait_framing.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var count := 0
	var social_count := 0
	for id in ALIASES.COLLECTION_FOLDERS:
		var old_path := "res://assets/characters/%s/portrait_512.png" % id
		var canonical_path: String = ALIASES.collection_path(id)
		var canonical := load(canonical_path) as Texture2D
		assert(canonical != null)
		if ResourceLoader.exists(old_path):
			var original := load(old_path) as Texture2D
			assert(original != null and original.get_size() == canonical.get_size())
			assert(original.get_image().get_data() == canonical.get_image().get_data())
		assert(PortraitAssetSource.texture_for(id, "collection") == canonical)
		if SOCIAL.PATHS.get(id, "") == "portrait_512.png":
			var crop := SOCIAL.texture(id) as AtlasTexture
			assert(crop != null and crop.atlas == canonical)
			assert(crop.region == (FRAMING.fitted(canonical, id, 1.0, "icon") as AtlasTexture).region)
			social_count += 1
		count += 1
	print("PORTRAIT_ALIAS_SMOKE_PASS aliases=", count, " social=", social_count)
	quit(0)
