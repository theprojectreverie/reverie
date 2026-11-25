from pathlib import Path
import shutil,json,os
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
def edit(rel, old,new):
 f=p/rel;t=f.read_text(encoding='utf-8-sig')
 if old not in t: raise RuntimeError(rel)
 b=Path(str(f)+'.before_tutorial_checkpoint'); 
 if not b.exists(): shutil.copy2(f,b)
 f.write_text(t.replace(old,new,1),encoding='utf-8')
edit('scripts/world/tutorial_prologue/training_ground_layout.gd','\tvar error := get_tree().change_scene_to_file(ROYAL_GARDENS)\n','\tGameState.quest_domain.flags["tutorial_complete"] = true\n\tGameState.session_domain.set_player_region("castle_royal_gardens")\n\tGameState.session_domain.loaded_from_save = true\n\tGameState.save_now()\n\tvar error := get_tree().change_scene_to_file(ROYAL_GARDENS)\n')
edit('scripts/world/tutorial_prologue/training_ground_layout.gd','\tGameState.quest_domain.flags["tutorial_complete"] = true\n\tGameState.queue_save()','\t# Completion checkpoint was saved before changing scenes.')
edit('scripts/world/tutorial_prologue/tutorial_prologue_world.gd','GameState.quest_domain.flags["tutorial_complete"] = true\n\t\t\tGameState.queue_save()','GameState.quest_domain.flags["tutorial_complete"] = true\n\t\t\tGameState.save_now()')
edit('scripts/game/components/main_gameplay_flow_component.gd','\tif GameState.session_domain.loaded_from_save:\n\t\tif bool(GameState.quest_domain.flags.get("tutorial_complete", false)):\n\t\t\t_load_gameplay()\n\t\telse:\n\t\t\t_load_tutorial()','\tif bool(GameState.quest_domain.flags.get("tutorial_complete", false)):\n\t\t_load_gameplay()\n\t\treturn\n\tif GameState.session_domain.loaded_from_save:\n\t\t_load_tutorial()')
# Repair the user's existing checkpoint, preserving all other progress.
f=Path(os.environ['APPDATA'])/'Project Fantasy/project_fantasy_save.json'
data=json.loads(f.read_text(encoding='utf-8-sig'))
b=Path(str(f)+'.before_tutorial_checkpoint')
if not b.exists(): shutil.copy2(f,b)
data.setdefault('flags',{})['tutorial_complete']=True
data['region']='castle_royal_gardens';data['active_world_id']='castle_royal_gardens'
tmp=f.with_suffix('.checkpoint.tmp');tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8');os.replace(tmp,f)
print('Checkpoint code patched; existing save recovered; backup preserved.')
