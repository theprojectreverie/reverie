from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scripts/ui/components/summon_reveal_overlay.gd'
t=f.read_text(encoding='utf-8-sig');shutil.copy2(f,str(f)+'.before_full_art_reveal')
t=t.replace('const CARD = preload("res://scenes/ui/components/summon_result_card.tscn")','')
t=t.replace('_show_card(roll, index, results.size())','_show_character(roll, index, results.size())')
a=t.index('func _show_card');b=t.index('func _play_stream',a)
t=t[:a]+'''func _show_character(roll: Dictionary, index: int, total: int) -> void:
	var stage := $CardStage
	var rarity := str(roll.get("rarity", "common")).to_lower()
	var character_id := str(roll.get("character_id", ""))
	var definition: CharacterDef = ContentDB.get_character(character_id)
	var art := $CardStage/CharacterArtwork as TextureRect
	art.texture = _character_art(character_id)
	stage.show()
	$CardStage/Progress.text = "%d / %d" % [index + 1, total]
	$CardStage/Intro.text = rarity.to_upper()
	$CardStage/Intro.modulate = UITheme.rarity_color(rarity)
	$CardStage/CharacterName.text = definition.display_name if definition != null else character_id.capitalize()
	$CardStage/CharacterTitle.text = definition.title if definition != null else ""
	$CardStage/CharacterTitle.modulate = UITheme.rarity_color(rarity)
	$CardStage/NextButton.text = "View all results" if index + 1 == total else "Next character"
	reveal_count += 1
	art.modulate.a = 0.0
	$CardStage/AnimationPlayer.play("mythic" if rarity == "mythic" else ("legendary" if rarity == "legendary" else "standard"))
	var fade := create_tween()
	fade.tween_property(art, "modulate:a", 1.0, 0.65 if rarity in ["legendary", "mythic"] else 0.35)
	waiting_for_card = true
	await advance_requested
	waiting_for_card = false
	fade.kill()
	stage.hide()
	art.texture = null

func _character_art(character_id: String) -> Texture2D:
	var base := character_id
	for suffix in ["_common", "_rare", "_epic", "_legendary", "_mythic"]:
		base = base.trim_suffix(suffix)
	var body_base := "kael_avatar" if base == "kael" else base
	# Prefer dedicated aspect artwork. Preserve original authored images.
	for id in [character_id, body_base]:
		var path := "res://assets/characters/%s/full_body_illustration.png" % id
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	# Temporary authored portrait until the missing full-body artwork is supplied.
	var portrait := PortraitAssetSource.texture_for(character_id, "collection")
	if portrait == null:
		portrait = PortraitAssetSource.texture_for(base, "collection")
	return portrait


'''+t[b:]
f.write_text(t,encoding='utf-8')
s=p/'scenes/ui/components/summon_reveal_overlay.tscn';t=s.read_text(encoding='utf-8-sig');shutil.copy2(s,str(s)+'.before_full_art_reveal')
a=t.index('[node name="CardCenter"');b=t.index('[node name="NextButton"',a)
t=t[:a]+'''[node name="CharacterArtwork" type="TextureRect" parent="CardStage"]
anchor_left = 0.12
anchor_right = 0.88
anchor_top = 0.19
anchor_bottom = 0.77
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="CharacterName" type="Label" parent="CardStage"]
anchor_left = 0.08
anchor_right = 0.92
anchor_top = 0.76
anchor_bottom = 0.82
theme_override_colors/font_color = Color(1, 0.91, 0.75, 1)
theme_override_font_sizes/font_size = 30
horizontal_alignment = 1
text_overrun_behavior = 3

[node name="CharacterTitle" type="Label" parent="CardStage"]
anchor_left = 0.08
anchor_right = 0.92
anchor_top = 0.82
anchor_bottom = 0.88
theme_override_font_sizes/font_size = 16
horizontal_alignment = 1
text_overrun_behavior = 3

'''+t[b:]
t=t.replace('text = "Next card"','text = "Next character"')
s.write_text(t,encoding='utf-8')
print('Full artwork stage installed; final card collection unchanged.')
