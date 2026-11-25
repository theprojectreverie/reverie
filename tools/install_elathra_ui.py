from pathlib import Path
from PIL import Image, ImageDraw
import json, shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
a=p/'assets/characters/elathra'
dl=Path.home()/'Downloads'
portrait=next(dl.glob('*Enchanted Witch Portrait.png'))
shutil.copy2(portrait,a/'portrait.png')
src=Image.open(dl/'Elathra Witch Portrait and Dialogue Panel.png').convert('RGBA')
# Extract only the illustrated panel, excluding the separate character on its left.
panel=src.crop((450,620,1510,942))
mask=Image.new('L',panel.size,0)
ImageDraw.Draw(mask).polygon([(0,95),(20,52),(70,30),(100,5),(360,5),(390,25),(470,25),(528,0),(570,25),(880,25),(950,0),(1030,45),(1060,90),(1060,265),(1025,300),(560,300),(520,322),(480,300),(85,300),(20,270),(0,235)],fill=255)
from PIL import ImageChops
panel.putalpha(ImageChops.multiply(panel.getchannel('A'),mask))
panel.save(a/'dialogue_panel.png')
# Keep original source for future art revisions.
shutil.copy2(dl/'Elathra Witch Portrait and Dialogue Panel.png',a/'dialogue_art_reference.png')
d=p/'resources/data/dialogue.json'
shutil.copy2(d,str(d)+'.before_elathra_portrait')
t=d.read_text(encoding='utf-8-sig').replace('res://assets/characters/elathra/portrait.jpg','res://assets/characters/elathra/portrait.png')
d.write_text(t,encoding='utf-8')
base=p/'scenes/ui/dialogue_box.tscn'
t=base.read_text(encoding='utf-8-sig')
t=t.replace('load_steps=4','load_steps=6')
i=t.index('[sub_resource')
t=t[:i]+'[ext_resource type="Texture2D" path="res://assets/characters/elathra/dialogue_panel.png" id="3_panel"]\n\n'+t[i:]
i=t.index('[node name="Dialogue"')
t=t[:i]+'[sub_resource type="StyleBoxEmpty" id="ElathraEmpty"]\ncontent_margin_left = 26.0\ncontent_margin_top = 22.0\ncontent_margin_right = 40.0\ncontent_margin_bottom = 24.0\n\n'+t[i:]
t=t.replace('theme_override_styles/panel = SubResource("StyleBoxFlat_panel")','theme_override_styles/panel = SubResource("ElathraEmpty")')
t=t.replace('offset_top = -314.0','offset_top = -365.0')
t=t.replace('custom_minimum_size = Vector2(196, 248)','custom_minimum_size = Vector2(320, 300)')
# Independent background sibling, positioned under the text column rather than baked into portrait.
i=t.index('[node name="DialoguePanel"')
bg='''[node name="ElathraDialogueBox" type="TextureRect" parent="."]
layout_mode = 1
anchor_left = 0.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 365.0
offset_top = -365.0
offset_right = -35.0
offset_bottom = -20.0
mouse_filter = 2
texture = ExtResource("3_panel")
expand_mode = 1
stretch_mode = 0

'''
t=t[:i]+bg+t[i:]
t=t.replace('theme_override_constants/separation = 18','theme_override_constants/separation = 32')
t=t.replace('normal_font_size = 16','normal_font_size = 18')
t=t.replace('custom_minimum_size = Vector2(0, 104)','custom_minimum_size = Vector2(0, 95)')
t=t.replace('offset_left = 48.0','offset_left = 30.0')
t=t.replace('offset_right = -48.0','offset_right = -65.0')
(p/'scenes/ui/elathra_dialogue_box.tscn').write_text(t,encoding='utf-8')
z=p/'scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn'
shutil.copy2(z,str(z)+'.before_elathra_custom_ui')
t=z.read_text(encoding='utf-8-sig').replace('res://scenes/ui/dialogue_box.tscn" id="elathra_dialogue"','res://scenes/ui/elathra_dialogue_box.tscn" id="elathra_dialogue"')
z.write_text(t,encoding='utf-8')
# Exact 128x128 idle frames without stretching the original art.
idle=Image.open(a/'elathra_idle_127x128.png').convert('RGBA')
if idle.size==(635,128):
 out=Image.new('RGBA',(640,128))
 for i in range(5): out.paste(idle.crop((127*i,0,127*(i+1),128)),(128*i,0))
 out.save(a/'elathra_idle_128x128.png')
 s=p/'scenes/world/six_zone_reverie/elathra.tscn'
 t=s.read_text(encoding='utf-8').replace('elathra_idle_127x128.png','elathra_idle_128x128.png')
 for i in range(5): t=t.replace(f'Rect2({127*i}, 0, 127, 128)',f'Rect2({128*i}, 0, 128, 128)')
 s.write_text(t,encoding='utf-8')
print('Portrait:',Image.open(a/'portrait.png').size,'Panel:',panel.size,'Custom UI saved and connected')
