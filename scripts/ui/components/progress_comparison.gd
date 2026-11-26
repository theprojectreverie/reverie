extends RefCounted
## Read-only local comparison. Never uploads local save data or grants online assets.
const CURRENCIES := ["gold","crystals","paid_moonstones","gems","ancient_coins","guild_tokens","event_tokens"]
static func compare(local: Dictionary, online: Dictionary) -> Dictionary:
	var local_chars: Dictionary = {}
	var remote_chars: Dictionary = {}
	for row in local.get("roster",[]):
		if row is Dictionary and not str(row.get("char_id","")).is_empty():
			local_chars[str(row.char_id)] = row
	for row in online.get("roster",[]):
		if row is Dictionary and not str(row.get("char_id","")).is_empty():
			remote_chars[str(row.char_id)] = row
	var ids: Array = local_chars.keys()
	for id in remote_chars:
		if not ids.has(id): ids.append(id)
	ids.sort()
	var characters: Array = []
	for id in ids:
		var l: Dictionary = local_chars.get(id,{})
		var r: Dictionary = remote_chars.get(id,{})
		characters.append({"id":id,"local":not l.is_empty(),"online":not r.is_empty(),"local_level":int(l.get("level",0)),"online_level":int(r.get("level",0)),"local_ascension":int(l.get("ascension",0)),"online_ascension":int(r.get("ascension",0)),"local_awakening":int(l.get("awakening",0)),"online_awakening":int(r.get("awakening",0))})
	var currencies: Array = []
	for id in CURRENCIES:
		currencies.append({"id":id,"local":int(local.get("profile",{}).get(id,0)),"online":int(str(online.get("currencies",{}).get(id,"0")))})
	var li: Dictionary = local.get("inventory",{})
	var ri: Dictionary = online.get("inventory",{})
	var item_ids: Array = li.keys()
	for id in ri:
		if not item_ids.has(id): item_ids.append(id)
	item_ids.sort()
	var items: Array = []
	for id in item_ids:
		var a := int(li.get(id,0))
		var b := int(str(ri.get(id,"0")))
		if a>0 or b>0: items.append({"id":id,"local":a,"online":b})
	return {"characters":characters,"currencies":currencies,"items":items}

static func format_report(report: Dictionary) -> String:
	var lines: PackedStringArray = ["CHARACTERS — local / online"]
	for row in report.characters:
		var definition: CharacterDef = ContentDB.get_character(str(row.id))
		var name := definition.display_name if definition != null else str(row.id).replace("_"," ").capitalize()
		var left := "Lv %d, A%d, W%d" % [row.local_level,row.local_ascension,row.local_awakening] if row.local else "Not owned"
		var right := "Lv %d, A%d, W%d" % [row.online_level,row.online_ascension,row.online_awakening] if row.online else "Not owned"
		lines.append("%s: %s / %s" % [name,left,right])
	lines.append("\nCURRENCIES — local / online")
	for row in report.currencies:
		lines.append("%s: %s / %s" % [str(row.id).replace("_"," ").capitalize(),UIFactory.number(row.local),UIFactory.number(row.online)])
	lines.append("\nUNEQUIPPED ITEMS — local / online")
	for row in report.items:
		lines.append("%s: %s / %s" % [str(ContentDB.get_item(str(row.id)).get("name",str(row.id).replace("_"," ").capitalize())),UIFactory.number(row.local),UIFactory.number(row.online)])
	lines.append("\nComparison only. Local assets are not verified server ownership. Paid currency, equipment, skills, pity and story progress are not transferred.")
	return "\n".join(lines)
