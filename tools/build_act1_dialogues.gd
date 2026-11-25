extends SceneTree

const DIALOGUES := {
	"road_warden_elowen": {"speaker":"Road Warden Elowen","text":"The king's road is still safe as far as the windmill. Beyond the willow fields, keep your lantern close. The old forest has begun answering voices that no one speaks.","portrait":{"hair":"#d9b7a2","primary":"#536b7a","secondary":"#b69a69","accent":"#f2d7a5","skin":"#e8c5ad"}},
	"miller_ada": {"speaker":"Miller Ada","text":"The mill turns when the valley wind is kind. Lately the stream has carried pale petals from the old wood. I have never seen flowers drift against the current before.","portrait":{"hair":"#9a604b","primary":"#9a7049","secondary":"#e0c078","accent":"#f2d9a1","skin":"#e9c3a5"}},
	"grove_keeper_thalen": {"speaker":"Grove Keeper Thalen","text":"This tree remembers the first dawn. The blight is not born here; it is being called from the ruins. If you hear your name among the branches, do not answer.","portrait":{"hair":"#c6d2bd","primary":"#405b4a","secondary":"#8b6c9c","accent":"#c6a7e8","skin":"#dfc4ae"}},
	"scout_merrow": {"speaker":"Scout Merrow","text":"The aqueduct is broken, but the water still runs beneath the stones. Something has nested in the arch. I marked a safe path through the rubble—follow the blue crystals, not the red ones.","portrait":{"hair":"#554b48","primary":"#59616d","secondary":"#8e505a","accent":"#9cc8d7","skin":"#d8b39d"}},
	"tower_sentinel": {"speaker":"Tower Sentinel","text":"The spire is a lock, not a monument. Its violet light is the key turning in the wrong direction. Beyond it lies the sealed keep. I can open the way only when the tower's sigil is quiet.","portrait":{"hair":"#ded4e8","primary":"#4b4268","secondary":"#8c6ab0","accent":"#d7a5ff","skin":"#e6c6bb"}}
}

func _initialize() -> void:
	var path := "res://resources/data/dialogue.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot read dialogue.json")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("dialogue.json invalid")
		quit(1)
	var data: Dictionary = parsed
	for id in DIALOGUES:
		var entry: Dictionary = DIALOGUES[id]
		data[id] = {
			"start":"greet",
			"nodes":{
				"greet":{
					"speaker":entry["speaker"],
					"portrait":entry["portrait"],
					"text":entry["text"],
					"choices":[
						{"text":"Tell me about this place.","next":"lore"},
						{"text":"I'll keep moving.","next":""}
					]
				},
				"lore":{
					"speaker":entry["speaker"],
					"portrait":entry["portrait"],
					"text":"The Royal Road binds these places together. Each landmark is part of an older warding path, and the stones remember what the living have forgotten.",
					"choices":[{"text":"Thank you.","next":""}]
				}
			}
		}
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(data, "\t"))
	out.close()
	print("ACT1_DIALOGUES_WRITTEN ", DIALOGUES.size(), " total=", data.size())
	quit()
