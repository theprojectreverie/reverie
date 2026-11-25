import pathlib, shutil, json
p=pathlib.Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
a=p/'assets/characters/elathra'; a.mkdir(parents=True,exist_ok=True)
for f in (pathlib.Path.home()/'Downloads').glob('elathra_*.png'): shutil.copy2(f,a/f.name)
s=p/'scenes/world/six_zone_reverie/elathra.tscn'
dirs=['idle','east','west','south','north']
names=['elathra_idle_127x128.png']+['elathra_walk_'+d+'_128x128.png' for d in dirs[1:]]
lines=['[gd_scene format=3]','', '[ext_resource type="Script" path="res://scripts/world/six_zone_reverie/elathra.gd" id="npc"]','[ext_resource type="PackedScene" path="res://scenes/world/components/npc_quest_marker.tscn" id="marker"]']
for d,n in zip(dirs,names): lines.append(f'[ext_resource type="Texture2D" path="res://assets/characters/elathra/{n}" id="{d}"]')
animations=[]
for d in dirs:
 w=127 if d=='idle' else 128
 count=5 if d=='idle' else 8
 frames=[]
 for i in range(count):
  k=f'{d}_{i}'; lines += ['',f'[sub_resource type="AtlasTexture" id="{k}"]',f'atlas = ExtResource("{d}")',f'region = Rect2({i*w}, 0, {w}, 128)']; frames.append('{"duration": 1.0, "texture": SubResource("'+k+'")}')
 animations.append('{"frames": ['+', '.join(frames)+'], "loop": true, "name": &"'+('idle' if d=='idle' else 'walk_'+d)+'", "speed": '+('4.0' if d=='idle' else '8.0')+'}')
lines += ['', '[sub_resource type="SpriteFrames" id="frames"]','animations = ['+', '.join(animations)+']','','[node name="Elathra" type="Node2D"]','script = ExtResource("npc")','', '[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]','texture_filter = 1','position = Vector2(0, -64)','sprite_frames = SubResource("frames")','animation = &"idle"','autoplay = "idle"','','[node name="QuestMarker" parent="." instance=ExtResource("marker")]','position = Vector2(0, -145)']
s.write_text('\n'.join(lines)+'\n',encoding='utf-8')
z=p/'scenes/world/six_zone_reverie/zone_01_royal_gardens.tscn'
t=z.read_text(encoding='utf-8-sig')
if 'id="elathra_npc"' not in t:
 shutil.copy2(z,str(z)+'.before_elathra')
 i=t.index('[ext_resource'); t=t[:i]+'[ext_resource type="PackedScene" path="res://scenes/world/six_zone_reverie/elathra.tscn" id="elathra_npc"]\n'+t[i:]
 i=t.find('[editable'); i=len(t) if i<0 else i
 t=t[:i]+'\n[node name="Elathra" parent="RoyalGardenV3Decorations" instance=ExtResource("elathra_npc")]\nposition = Vector2(2179, 1400)\n\n'+t[i:]; z.write_text(t,encoding='utf-8')
print('Imported',len(list(a.glob('*.png'))),'sheets; authored NPC and placed near gazebo')
