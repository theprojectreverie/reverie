extends Node
## Only validated PNG atlases and fixed animation metadata. Never loads remote scripts/resources.
const SLOTS := ["idle","basic_attack","skill_1","skill_2","ultimate","hit","defeat"]
var installed: Dictionary = {}
var _busy := false
var _next_at := 0
var _generation := 0
var _owner := ""
var _request: HTTPRequest
signal packs_changed

func _ready() -> void:
	AuthGateway.authentication_changed.connect(_identity_changed)

func _identity_changed(_authenticated: bool, _identity: Dictionary) -> void:
	_generation += 1
	_owner = str(AuthGateway.current_player().get("id", ""))
	_next_at = 0
	# Packs are public content, not account data. Retain already validated art for battles.

func frames_for(id: String) -> SpriteFrames:
	return installed.get(id, {}).get("frames") as SpriteFrames

func portrait_for(id: String) -> Texture2D:
	return installed.get(id, {}).get("portrait") as Texture2D

func _valid_hash(hash: String) -> bool:
	return hash.length() == 64 and hash.is_valid_hex_number(false) and hash == hash.to_lower()

func decode_png(bytes: PackedByteArray, hash: String) -> Image:
	if bytes.size() < 33 or bytes.size() > 1048576 or not _valid_hash(hash): return null
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA256)
	sha.update(bytes)
	if sha.finish().hex_encode() != hash: return null
	if bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]): return null
	var width := (int(bytes[16])<<24)|(int(bytes[17])<<16)|(int(bytes[18])<<8)|int(bytes[19])
	var height := (int(bytes[20])<<24)|(int(bytes[21])<<16)|(int(bytes[22])<<8)|int(bytes[23])
	if width < 1 or width > 1024 or height < 1 or height > 1024: return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK or img.get_width()!=width or img.get_height()!=height: return null
	return img

func _fetch_bytes(path: String, generation: int) -> PackedByteArray:
	if generation != _generation or not AuthGateway.access_token_ready_for_connection(): return PackedByteArray()
	var req := HTTPRequest.new()
	req.timeout = 12.0
	req.body_size_limit = 1048576
	req.max_redirects = 0
	add_child(req)
	var err := req.request(AuthGateway.api_base_url + "/v1/summon/" + path, PackedStringArray(["Authorization: Bearer " + AuthGateway.access_token_for_request()]))
	if err != OK:
		req.queue_free()
		return PackedByteArray()
	var result: Array = await req.request_completed
	req.queue_free()
	if generation != _generation or result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200: return PackedByteArray()
	return result[3]

func _texture(hash: String, generation: int) -> Texture2D:
	if not _valid_hash(hash): return null
	var path := "user://live_character_" + hash + ".png"
	var img: Image = null
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and f.get_length() <= 1048576: img = decode_png(f.get_buffer(f.get_length()),hash)
	if img == null:
		var bytes := await _fetch_bytes("artwork/" + hash,generation)
		img = decode_png(bytes,hash)
		if img == null: return null
		if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
			var f := FileAccess.open(path,FileAccess.WRITE)
			if f != null: f.store_buffer(bytes)
	return ImageTexture.create_from_image(img)

func _build(pack: Dictionary, generation: int) -> Dictionary:
	var id := str(pack.get("characterId", ""))
	var rev := str(pack.get("revision", ""))
	if not _valid_hash(rev) or pack.get("mode") not in ["animation_update","new_character"]: return {}
	if pack.get("mode")=="animation_update" and ContentDB.get_character(id)==null: return {}
	if pack.get("mode")=="new_character":
		if not id.begins_with("livechar_") or str(pack.get("mythic",""))!=id+"_mythic" or not pack.get("definitions") is Dictionary or pack.definitions.size()!=2 or not pack.definitions.has(id) or not pack.definitions.has(id+"_mythic") or not pack.has("portrait"): return {}
		if ContentDB.validated_live_definitions(pack.definitions).size()!=2: return {}
	var animations: Variant = pack.get("animations")
	if not animations is Array or animations.size()!=SLOTS.size(): return {}
	var seen: Dictionary = {}
	var pixels := 0
	for a in animations:
		if not a is Dictionary: return {}
		var slot := str(a.get("slot",""))
		var columns := int(a.get("columns",0))
		var rows := int(a.get("rows",0))
		var frames := int(a.get("frames",0))
		var fps := int(a.get("fps",0))
		if slot not in SLOTS or seen.has(slot) or columns<1 or columns>8 or rows<1 or rows>8 or frames<1 or frames>columns*rows or fps<1 or fps>24 or a.get("facing") not in ["left","right"] or not _valid_hash(str(a.get("artwork",""))): return {}
		seen[slot]=true
		pixels+=columns*rows*128*128
	if pixels>3000000: return {}
	var sprites := SpriteFrames.new()
	sprites.remove_animation(&"default")
	var height := 0.0
	var bottom := 128.0
	var facings: Dictionary={}
	var textures: Dictionary = {}
	for a in animations:
		var hash := str(a.artwork)
		var tex: Texture2D = textures.get(hash)
		if tex == null:
			tex = await _texture(hash,generation)
			if tex == null or generation != _generation: return {}
			textures[hash]=tex
		if tex.get_width()!=int(a.columns)*128 or tex.get_height()!=int(a.rows)*128: return {}
		var slot := StringName(str(a.slot))
		facings[str(slot)]=str(a.facing)
		sprites.add_animation(slot)
		sprites.set_animation_speed(slot,float(a.fps))
		sprites.set_animation_loop(slot,slot==&"idle")
		for i in range(int(a.frames)):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2((i % int(a.columns))*128, floori(float(i)/int(a.columns))*128,128,128)
			atlas.filter_clip = true
			sprites.add_frame(slot,atlas)
			if slot==&"idle" and i==0:
				var img := tex.get_image().get_region(Rect2i(atlas.region))
				height=float(img.get_used_rect().size.y)
				bottom=float(img.get_used_rect().end.y)
	if height<1: return {}
	var portrait: Texture2D = null
	if pack.has("portrait"):
		portrait=await _texture(str(pack.portrait),generation)
		if portrait==null or generation!=_generation: return {}
	return {"revision":rev,"frames":sprites,"portrait":portrait,"height":height,"bottom":bottom,"facings":facings,"heightCm":int(pack.get("heightCm",0))}

func refresh(force: bool = false) -> bool:
	if not AuthGateway.is_authenticated() or not AuthGateway.access_token_ready_for_connection(): return false
	if _busy:
		if not force: return false
		var waiting:=_generation
		while _busy and waiting==_generation: await get_tree().process_frame
		if waiting!=_generation: return false
	if not force and Time.get_ticks_msec()<_next_at: return true
	_busy=true
	_next_at=Time.get_ticks_msec()+30000
	var generation:=_generation
	var owner:=str(AuthGateway.current_player().get("id",""))
	var raw:=await _fetch_bytes("character-content",generation)
	var data: Variant=JSON.parse_string(raw.get_string_from_utf8()) if not raw.is_empty() else null
	if generation!=_generation or not data is Dictionary or data.get("schema")!=1 or str(data.get("playerId",""))!=owner or not data.get("packs") is Array or data.packs.size()>4:
		_busy=false
		return false
	var next: Dictionary={}
	var raw_defs: Dictionary={}
	var items: Dictionary={}
	var cards: Dictionary={}
	var fusion: Dictionary={}
	var ascension: Dictionary={}
	for pack in data.packs:
		if not pack is Dictionary:
			_busy=false
			return false
		var id:=str(pack.get("characterId",""))
		if next.has(id):
			_busy=false
			return false
		if pack.get("mode")=="new_character":
			if not pack.get("definitions") is Dictionary or not pack.get("items") is Dictionary or not pack.get("upgrade_cards") is Dictionary or not pack.get("mythic_fusion") is Dictionary or not pack.get("mythic_ascension") is Dictionary:
				_busy=false
				return false
			for key in pack.definitions:
				if raw_defs.has(key):
					_busy=false
					return false
			raw_defs.merge(pack.definitions)
			items.merge(pack.items)
			cards.merge(pack.upgrade_cards)
			fusion.merge(pack.mythic_fusion)
			ascension.merge(pack.mythic_ascension)
		var current: Dictionary=installed.get(id,{})
		if current.get("revision")==pack.get("revision") and not current.is_empty():
			next[id]=current
			if pack.get("mode")=="new_character": next[str(pack.mythic)]=current
			continue
		var built:=await _build(pack,generation)
		if built.is_empty() or generation!=_generation:
			_busy=false
			return false
		next[id]=built
		if pack.get("mode")=="new_character": next[str(pack.mythic)]=built
	if generation!=_generation:
		_busy=false
		return false
	var defs:=ContentDB.validated_live_definitions(raw_defs)
	if defs.size()!=raw_defs.size():
		_busy=false
		return false
	var changed:=next!=installed
	if changed:
		ContentDB.install_live_definitions(defs)
		ContentDB.live_character_items=items
		ContentDB.live_upgrade_cards=cards
		ContentDB.live_mythic_fusion=fusion
		ContentDB.live_mythic_ascension=ascension
	installed=next
	_busy=false
	# Only retain files referenced by the currently accepted catalog.
	var keep: Dictionary={}
	for pack in data.packs:
		for a in pack.animations: keep["live_character_"+str(a.artwork)+".png"]=true
		if pack.has("portrait"): keep["live_character_"+str(pack.portrait)+".png"]=true
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		for file in DirAccess.get_files_at("user://"):
			if file.begins_with("live_character_") and file.ends_with(".png") and not keep.has(file): DirAccess.remove_absolute("user://"+file)
	if changed: packs_changed.emit()
	return true
