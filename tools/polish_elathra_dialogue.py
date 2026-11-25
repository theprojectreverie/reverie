from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scenes/ui/elathra_dialogue_box.tscn'
t=f.read_text(encoding='utf-8-sig')
shutil.copy2(f,str(f)+'.before_layout_polish')
# Use a fixed proportional composition at 1280x720 with independent portrait and panel.
def patch_node(name, changes):
 global t
 import re
 pattern=r'(?m)^\[node name="'+name+r'"[^\n]*\]\n.*?(?=\n\[node |\Z)'
 m=re.search(pattern,t,re.S)
 if not m: raise RuntimeError(name)
 chunk=m.group(0)
 for key,val in changes.items():
  pat=r'(?m)^'+re.escape(key)+r' = .*?$'
  if re.search(pat,chunk): chunk=re.sub(pat,key+' = '+val,chunk)
  else: chunk=chunk.rstrip()+'\n'+key+' = '+val+'\n'
 t=t[:m.start()]+chunk.rstrip()+'\n'+t[m.end():]
patch_node('ElathraDialogueBox',{'offset_left':'410.0','offset_top':'-345.0','offset_right':'-30.0','offset_bottom':'-25.0'})
patch_node('DialoguePanel',{'offset_left':'12.0','offset_top':'-338.0','offset_right':'-74.0','offset_bottom':'-47.0'})
patch_node('ContentRow',{'theme_override_constants/separation':'30'})
patch_node('Portrait',{'custom_minimum_size':'Vector2(390, 265)'})
patch_node('PortraitArt',{'offset_top':'-150.0','offset_bottom':'8.0','stretch_mode':'5'})
patch_node('TextColumn',{'theme_override_constants/separation':'12'})
patch_node('Header',{'custom_minimum_size':'Vector2(0, 35)'})
patch_node('SpeakerLabel',{'custom_minimum_size':'Vector2(220, 32)','horizontal_alignment':'1','theme_override_font_sizes/font_size':'24'})
patch_node('NameLabel',{'visible':'false'})
patch_node('TextLabel',{'custom_minimum_size':'Vector2(0, 78)','theme_override_font_sizes/normal_font_size':'20','theme_override_colors/default_color':'Color(0.97, 0.93, 0.86, 1)','theme_override_constants/line_separation':'4','scroll_active':'true'})
patch_node('ChoicesBox',{'theme_override_constants/separation':'8'})
patch_node('HintLabel',{'theme_override_colors/font_color':'Color(0.79, 0.73, 0.64, 1)'})
t=t.replace('content_margin_left = 26.0','content_margin_left = 12.0').replace('content_margin_top = 22.0','content_margin_top = 20.0').replace('content_margin_right = 40.0','content_margin_right = 24.0').replace('content_margin_bottom = 24.0','content_margin_bottom = 12.0')
# The portrait gets its own larger independent node, avoiding clipping by its container.
i=t.index('[node name="DialoguePanel"')
t=t[:i]+'''[node name="ElathraPortrait" type="TextureRect" parent="."]
layout_mode = 1
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = -530.0
offset_right = 442.0
offset_bottom = -38.0
mouse_filter = 2
texture = ExtResource("4_art")
expand_mode = 1
stretch_mode = 5
texture_filter = 2

'''+t[i:]
t=t.replace('[ext_resource type="Texture2D" path="res://assets/characters/elathra/dialogue_panel.png" id="3_panel"]','[ext_resource type="Texture2D" path="res://assets/characters/elathra/dialogue_panel.png" id="3_panel"]\n[ext_resource type="Texture2D" path="res://assets/characters/elathra/portrait.png" id="4_art"]')
t=t.replace('load_steps=6','load_steps=7')
# Keep original PortraitView as invisible layout spacer with script interface intact.
t=t.replace('custom_minimum_size = Vector2(390, 265)','visible = false\ncustom_minimum_size = Vector2(390, 265)')
# Replace invisible portrait's width using an explicit spacer.
i=t.index('[node name="TextColumn"')
t=t[:i]+'''[node name="PortraitSpacer" type="Control" parent="DialoguePanel/ContentRow"]
custom_minimum_size = Vector2(390, 0)
layout_mode = 2
mouse_filter = 2

'''+t[i:]
f.write_text(t,encoding='utf-8')
# Style choices using native Theme resources, limited to this custom overlay.
g=p/'scripts/ui/elathra_dialogue_box.gd'
g.write_text('''extends DialogueBox

const CHOICE_THEME = preload("res://resources/ui/elathra_choice_theme.tres")

func _ready() -> void:
	super._ready()
	_name_label.hide()
	_portrait.hide()
	_continue_button.theme = CHOICE_THEME

func _build_choices() -> void:
	super._build_choices()
	for child in _choices_box.get_children():
		if child is Button:
			child.theme = CHOICE_THEME
			child.custom_minimum_size = Vector2(0, 40)
''',encoding='utf-8')
r=p/'resources/ui';r.mkdir(exist_ok=True)
theme=['[gd_resource type="Theme" format=3]']
for name,bg,border in [('Normal','0.075, 0.085, 0.16, 0.96','0.64, 0.48, 0.27, 0.85'),('Hover','0.16, 0.15, 0.25, 1','0.94, 0.78, 0.45, 1'),('Pressed','0.20, 0.17, 0.28, 1','0.94, 0.78, 0.45, 1')]:
 theme+=['',f'[sub_resource type="StyleBoxFlat" id="{name}"]',f'bg_color = Color({bg})',f'border_color = Color({border})']
 for edge in ['left','top','right','bottom']: theme.append(f'border_width_{edge} = 1')
 for corner in ['top_left','top_right','bottom_left','bottom_right']: theme.append(f'corner_radius_{corner} = 5')
 theme+=['content_margin_left = 16.0','content_margin_right = 16.0','content_margin_top = 6.0','content_margin_bottom = 6.0']
theme+=['','[resource]','Button/colors/font_color = Color(0.97, 0.93, 0.86, 1)','Button/colors/font_hover_color = Color(1, 0.91, 0.72, 1)','Button/font_sizes/font_size = 17','Button/styles/normal = SubResource("Normal")','Button/styles/hover = SubResource("Hover")','Button/styles/pressed = SubResource("Pressed")','Button/styles/focus = SubResource("Hover")']
(r/'elathra_choice_theme.tres').write_text('\n'.join(theme)+'\n',encoding='utf-8')
t=f.read_text(encoding='utf-8').replace('res://scripts/ui/dialogue_box.gd','res://scripts/ui/elathra_dialogue_box.gd')
f.write_text(t,encoding='utf-8')
print('Custom dialogue layout, portrait and themed choices installed.')
