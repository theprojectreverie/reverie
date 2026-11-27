extends RefCounted
## Display-only crops of existing authored images. Original assets are unchanged.
## Face centers (normalized x/y) and square crop widths measured against the source artwork.
const FACE = {
 "kael": Vector3(0.51,0.35,0.96),
 "gerald": Vector3(0.53,0.24,0.78),
 "lilith": Vector3(0.45,0.35,0.90),
 "cassien": Vector3(0.60,0.28,0.94),
 "caelith": Vector3(0.55,0.30,0.98),
 "ravienna": Vector3(0.56,0.31,0.96),
 "nyx": Vector3(0.52,0.31,0.96),
 "crimson_witch": Vector3(0.51,0.28,0.96),
 "mirene": Vector3(0.54,0.30,0.96),
 "elathra": Vector3(0.52,0.42,0.74),
 "revienna_human_ritual": Vector3(0.56,0.38,0.96),
}
static var _cache: Dictionary = {}

static func base_id(id: String) -> String:
 for suffix in ["_common", "_rare", "_epic", "_legendary", "_mythic", "_avatar"]:
  id = id.trim_suffix(suffix)
 return id

static func authored_texture(id: String, mode: String = "icon") -> Texture2D:
 var approved := preload("res://scripts/art/approved_character_portraits.gd").texture(id)
 if approved != null: return approved
 var base := base_id(id)
 var folder := "kael_avatar" if base == "kael" else base
 var candidates: Array[String] = []
 if mode == "card" and base == "elathra":
  candidates.append("res://assets/portraits/summon/elathra.png")
 for key in [id, folder]:
  for file in ["portrait.png", "portrait_512.png", "portrait_battle.png"]:
   if file == "portrait_512.png":
    candidates.append(preload("res://scripts/art/portrait_texture_aliases.gd").collection_path(key))
   else:
    candidates.append("res://assets/characters/%s/%s" % [key,file])
 candidates.append("res://assets/portraits/summon/%s.png" % base)
 for path in candidates:
  if ResourceLoader.exists(path):
   var texture := load(path) as Texture2D
   if texture != null:
    return texture
 return null

static func fitted(texture: Texture2D, id: String, aspect: float, mode: String) -> Texture2D:
 if texture == null or mode == "art" or texture is AtlasTexture:
  return texture
 var dimensions := texture.get_size()
 if dimensions.x <= 0 or dimensions.y <= 0 or aspect <= 0:
  return texture
 var key := "%d:%s:%d:%s" % [texture.get_instance_id(),id,roundi(aspect*1000),mode]
 if _cache.has(key):
  return _cache[key]
 var focus: Vector3 = FACE.get(base_id(id),Vector3(0.5,0.35,1.0))
 var crop := Vector2.ZERO
 if mode == "icon":
  var side := minf(dimensions.x,dimensions.y)*focus.z
  crop = Vector2(side,side/aspect) if aspect < 1.0 else Vector2(side*aspect,side)
  crop *= minf(1.0,minf(dimensions.x/crop.x,dimensions.y/crop.y))
 else:
  crop = Vector2(minf(dimensions.x,dimensions.y*aspect),minf(dimensions.y,dimensions.x/aspect))
 var origin := Vector2(focus.x*dimensions.x-crop.x*0.5,focus.y*dimensions.y-crop.y*0.45)
 if mode == "card":
  origin.y = 0.0
 origin = origin.clamp(Vector2.ZERO,dimensions-crop)
 var atlas := AtlasTexture.new()
 atlas.atlas = texture
 atlas.region = Rect2(origin.round(),crop.floor())
 atlas.filter_clip = true
 if _cache.size() >= 512:
  _cache.clear()
 _cache[key] = atlas
 return atlas
