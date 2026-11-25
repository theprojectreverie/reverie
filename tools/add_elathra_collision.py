from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scenes/world/six_zone_reverie/elathra.tscn'
t=f.read_text(encoding='utf-8-sig')
if 'ElathraFootprint' not in t:
 shutil.copy2(f,str(f)+'.before_npc_collision')
 i=t.index('[node name="Elathra"')
 t=t[:i]+'[sub_resource type="CapsuleShape2D" id="ElathraFootprint"]\nradius = 15.0\nheight = 34.0\n\n'+t[i:]
 t+='\n[node name="FootprintBody" type="StaticBody2D" parent="."]\ncollision_layer = 1\ncollision_mask = 0\n\n[node name="CollisionShape2D" type="CollisionShape2D" parent="FootprintBody"]\nposition = Vector2(0, -12)\nshape = SubResource("ElathraFootprint")\n'
 f.write_text(t,encoding='utf-8')
g=p/'scripts/world/six_zone_reverie/elathra.gd'
t=g.read_text(encoding='utf-8-sig')
if 'func _physics_process' not in t:
 shutil.copy2(g,str(g)+'.before_npc_collision')
 t=t.replace('func _process(delta: float)', 'func _physics_process(delta: float)')
 t=t.replace('if talking:\n\t\treturn','if talking:\n\t\treturn\n\tvar player := get_tree().get_first_node_in_group("player") as Node2D\n\tif player != null and global_position.distance_to(player.global_position) < 36.0:\n\t\tsprite.play("idle")\n\t\treturn',1)
 g.write_text(t,encoding='utf-8')
print('NPC footprint installed on layer 1, matching player mask 1.')
