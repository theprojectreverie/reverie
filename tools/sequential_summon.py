from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
def edit(rel,fn):
 f=p/rel;t=f.read_text(encoding='utf-8-sig');shutil.copy2(f,str(f)+'.before_sequential_reveal');f.write_text(fn(t),encoding='utf-8')
def flow(t):
 a=t.index('\tvar reveal_close');b=t.index('\n\nfunc show_results',a)
 t=t[:a]+'''	var reveal := screen._results_layer as SummonRevealOverlay
	AudioDirector.play_summon_ritual_ambience()
	await reveal.play_batch(results)
	if not is_instance_valid(screen) or not screen.is_inside_tree():
		return
	AudioDirector.stop_summon_ritual_ambience()
	if is_instance_valid(screen._results_layer):
		screen._results_layer.hide()
		screen._results_layer.queue_free()
	screen._results_layer = null
'''+t[b:]
 t=t.replace('screen.add_child(screen._results_layer)\n\n\tvar panel','screen.add_child(screen._results_layer)\n\tscreen._results_layer.z_index = 80\n\n\tvar panel')
 t=t.replace('var grid := screen._results_layer.get_node("Center/Panel/Content/ResultGrid")','var grid := screen._results_layer.get_node("Center/Panel/Content/ResultsScroll/ResultGrid")')
 t=t.replace('var card_width := clampf','var scroll := grid.get_parent() as ScrollContainer\n\tscroll.custom_minimum_size.y = minf(screen.get_viewport_rect().size.y * 0.70, 590.0 if results.size() > grid.columns else 310.0)\n\tvar card_width := clampf')
 return t
edit('scripts/ui/components/gacha_summon_flow_component.gd',flow)
def reveal(t):
 t=t.replace('signal stream_completed','signal stream_completed\nsignal advance_requested\nvar skipped := false\nvar waiting_for_card := false\nvar reveal_count := 0\nconst CARD = preload("res://scenes/ui/components/summon_result_card.tscn")')
 a=t.index('func play_reveal');b=t.index('func _play_stream',a)
 t=t[:a]+'''func _ready() -> void:
	$CloseSummonButton.text = "SKIP ALL"
	$CloseSummonButton.pressed.connect(skip_all)
	$CardStage/NextButton.pressed.connect(_advance)

func skip_all() -> void:
	if skipped:
		return
	skipped = true
	stream_completed.emit()
	advance_requested.emit()

func _advance() -> void:
	if waiting_for_card:
		advance_requested.emit()

func play_reveal(rarity: String) -> void:
	await play_batch([{"rarity": rarity}])

func play_batch(results: Array) -> void:
	$Shade.color = Color(0.015, 0.008, 0.035, 1.0)
	$SigilCenter.hide()
	$Title.hide()
	$Subtitle.hide()
	$CardStage.hide()
	cinematic_player.show()
	await _play_stream(OPENING_STREAM)
	for index in results.size():
		if skipped:
			break
		var roll: Dictionary = results[index]
		var rarity := str(roll.get("rarity", "common")).to_lower()
		if rarity in ["legendary", "mythic"]:
			cinematic_player.show()
			await _play_stream(HIGHEST_STREAM)
		if skipped:
			break
		cinematic_player.hide()
		AudioDirector.play_summon_reveal()
		await _show_card(roll, index, results.size())
	cinematic_player.stop()
	reveal_finished.emit()

func _show_card(roll: Dictionary, index: int, total: int) -> void:
	var stage := $CardStage
	var slot := $CardStage/CardCenter
	var rarity := str(roll.get("rarity", "common")).to_lower()
	var premium := rarity in ["legendary", "mythic"]
	stage.show()
	$CardStage/Progress.text = "%d / %d" % [index + 1, total]
	$CardStage/Intro.text = "A legendary bond awakens" if rarity == "legendary" else ("A mythic soul descends" if rarity == "mythic" else "A new bond answers")
	$CardStage/Intro.modulate = UITheme.rarity_color(rarity)
	$CardStage/NextButton.text = "View all results" if index + 1 == total else "Next card"
	var card := CARD.instantiate() as SummonResultCard
	card.custom_minimum_size = Vector2(300, 420)
	var portrait := card.get_node("Content/Portrait") as PortraitView
	portrait.custom_minimum_size = Vector2(240, 300)
	slot.add_child(card)
	card.setup(roll)
	reveal_count += 1
	card.modulate.a = 0.0
	$CardStage/AnimationPlayer.play("mythic" if rarity == "mythic" else ("legendary" if premium else "standard"))
	var fade := create_tween()
	fade.tween_property(card, "modulate:a", 1.0, 0.35)
	waiting_for_card = true
	await advance_requested
	waiting_for_card = false
	stage.hide()
	card.hide()
	card.queue_free()


'''+t[b:]
 t=t.replace('if stream == null or not is_instance_valid(cinematic_player):','if skipped or stream == null or not is_instance_valid(cinematic_player):')
 return t
edit('scripts/ui/components/summon_reveal_overlay.gd',reveal)
def scene(t):
 # Native animation tracks on the authored introduction label, no generated art.
 i=t.index('[node name="SummonRevealOverlay"')
 resources=''
 for name,duration,start in [('standard',0.45,0.0),('legendary',1.1,0.0),('mythic',1.6,0.0)]:
  resources+=f'''[sub_resource type="Animation" id="{name}"]
resource_name = "{name}"
length = {duration}
tracks/0/type = "value"
tracks/0/path = NodePath("Intro:modulate:a")
tracks/0/keys = {{"times": PackedFloat32Array(0, {duration}), "transitions": PackedFloat32Array(1, 1), "update": 0, "values": [0.0, 1.0]}}

'''
 resources+='''[sub_resource type="AnimationLibrary" id="RevealAnimations"]
_data = {&"standard": SubResource("standard"), &"legendary": SubResource("legendary"), &"mythic": SubResource("mythic")}

'''
 t=t[:i]+resources+t[i:]
 t=t.replace('load_steps=7','load_steps=11')
 t+='''
[node name="CardStage" type="Control" parent="."]
visible = false
z_index = 1
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2

[node name="Progress" type="Label" parent="CardStage"]
anchor_left = 0.4
anchor_right = 0.6
anchor_top = 0.04
anchor_bottom = 0.10
horizontal_alignment = 1
theme_override_font_sizes/font_size = 18

[node name="Intro" type="Label" parent="CardStage"]
anchor_left = 0.1
anchor_right = 0.9
anchor_top = 0.12
anchor_bottom = 0.20
horizontal_alignment = 1
theme_override_font_sizes/font_size = 28

[node name="CardCenter" type="CenterContainer" parent="CardStage"]
anchor_left = 0.05
anchor_right = 0.95
anchor_top = 0.20
anchor_bottom = 0.87
mouse_filter = 2

[node name="NextButton" type="Button" parent="CardStage"]
anchor_left = 0.38
anchor_right = 0.62
anchor_top = 0.89
anchor_bottom = 0.96
text = "Next card"

[node name="AnimationPlayer" type="AnimationPlayer" parent="CardStage"]
libraries = {&"": SubResource("RevealAnimations")}
'''
 return t
edit('scenes/ui/components/summon_reveal_overlay.tscn',scene)
def screen(t):
 t=t.replace('if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_menu"):\n\t\tclose_screen()','if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_menu"):\n\t\tif _results_layer is SummonRevealOverlay:\n\t\t\t_results_layer.skip_all()\n\t\telif _results_layer != null and is_instance_valid(_results_layer):\n\t\t\t_results_layer.queue_free()\n\t\t\t_results_layer = null\n\t\telif not _summon_busy:\n\t\t\tclose_screen()')
 return t
edit('scripts/ui/screens/gacha_screen.gd',screen)
def results(t):
 t=t.replace('[node name="ResultGrid" type="GridContainer" parent="Center/Panel/Content"]','[node name="ResultsScroll" type="ScrollContainer" parent="Center/Panel/Content"]\nlayout_mode = 2\nhorizontal_scroll_mode = 0\n\n[node name="ResultGrid" type="GridContainer" parent="Center/Panel/Content/ResultsScroll"]\nsize_flags_horizontal = 3')
 return t
edit('scenes/ui/components/summon_results_overlay.tscn',results)
print('Sequential reveal, skip-to-results, premium intro and scrollable collection installed.')
