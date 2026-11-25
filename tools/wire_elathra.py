import pathlib,json,shutil
p=pathlib.Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
q=p/'resources/data/quests.json'; d=p/'resources/data/dialogue.json'
for f in (q,d):
 b=f.with_suffix(f.suffix+'.before_elathra')
 if not b.exists(): shutil.copy2(f,b)
quests=json.loads(q.read_text(encoding='utf-8-sig'))
quests['elathra_first_audience']={'name':'The Lily of Shadows','region':'castle_royal_gardens','summary':'Meet Elathra beneath the wisteria and hear her warning.','steps':[{'type':'talk','target':'elathra','grid':[20,8],'text':'Hear Elathra’s request'},{'type':'talk','target':'elathra','grid':[20,8],'text':'Accept Elathra’s counsel'}],'rewards':{'gold':0,'crystals':0,'xp':25,'items':{}}}
q.write_text(json.dumps(quests,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
dialogues=json.loads(d.read_text(encoding='utf-8-sig'))
def node(text,choices): return {'speaker':'Élathra','text':text,'portrait_asset':'res://assets/characters/elathra/portrait.jpg','choices':choices}
dialogues['elathra']={'start':'greet','start_rules':[{'if':'quest_complete:elathra_first_audience','node':'complete'},{'if':'quest_ready:elathra_first_audience','node':'accepted'}],'nodes':{'greet':node('The gardens remember what the kingdom would rather forget, Kael. Will you hear what I have to tell you?',[{'text':'I am listening.','action':'start_quest:elathra_first_audience','next':'accepted'},{'text':'Another time.','next':''}]),'accepted':node('Do not mistake the silence beyond the royal gate for peace. The war has left wounds that no sword can heal.',[{'text':'I will remember.','action':'complete_quest:elathra_first_audience','next':'complete'}]),'complete':node('Return to me when the road has revealed its secrets.',[{'text':'Until then.','next':''}])}}
d.write_text(json.dumps(dialogues,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
z=p/'scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn'
t=z.read_text(encoding='utf-8-sig')
if 'id="elathra_dialogue"' not in t:
 shutil.copy2(z,str(z)+'.before_elathra')
 i=t.index('[ext_resource'); t=t[:i]+'[ext_resource type="PackedScene" path="res://scenes/ui/dialogue_box.tscn" id="elathra_dialogue"]\n'+t[i:]
 t+='\n[node name="NPCDialogueLayer" type="CanvasLayer" parent="."]\nlayer = 20\n\n[node name="Dialogue" parent="NPCDialogueLayer" instance=ExtResource("elathra_dialogue")]\n'
 z.write_text(t,encoding='utf-8')
c=p/'scripts/world/six_zone_reverie/standalone_zone_controller.gd'
t=c.read_text(encoding='utf-8-sig')
if '_open_local_npc_dialogue' not in t:
 shutil.copy2(c,str(c)+'.before_elathra')
 t=t.replace('    var player: CharacterBody2D', '    if has_node("NPCDialogueLayer/Dialogue"):\n        EventBus.dialogue_requested.connect(_open_local_npc_dialogue)\n    var player: CharacterBody2D',1)
 t+='\nfunc _open_local_npc_dialogue(id: String) -> void:\n    if id == "elathra":\n        $NPCDialogueLayer/Dialogue.open(id)\n'
 c.write_text(t,encoding='utf-8')
print('Quest and dialogue installed')
