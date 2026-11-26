extends RefCounted
## Presentation only: title ownership and equipped name remain server-authoritative.
static var _tiers:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/achievement_title_tiers.json"))
static func tier(title:String) -> String:
	return str(_tiers.get(title,""))
static func color(title:String) -> Color:
	match tier(title):
		"Rare":return Color("#8fc9ec")
		"Epic":return Color("#c39bf1")
		"Legendary":return Color("#e8be72")
		"Mythic":return Color("#ff9ebd")
		_:return Color("#d4ad69")
