from pathlib import Path
import json,os,shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=Path(os.environ['APPDATA'])/'Project Fantasy/project_fantasy_save_3b0d68b4-0a85-4b21-a789-79a88be8ec1a.json'
d=json.loads(f.read_text(encoding='utf-8-sig'))
assert d['profile']['name'].casefold()=='raven'
shutil.copy2(f,str(f)+'.before_developer_currency_grant')
# Apply once per local account, including on next login if an older running process overwrites the file.
g=p/'scripts/core/components/game_state_lifecycle_component.gd'
t=g.read_text(encoding='utf-8-sig')
shutil.copy2(g,str(g)+'.before_raven_grant')
key='dev_grant_raven_20261125'
if 'func _apply_local_developer_grant' not in t:
 t=t.replace('state.loaded_from_save = true\n\t\tEventBus.roster_changed.emit()', 'state.loaded_from_save = true\n\t\t_apply_local_developer_grant()\n\t\tEventBus.roster_changed.emit()')
 t=t.replace('new_game(str(player.get("name", "Wanderer")))','new_game(str(player.get("name", "Wanderer")))\n\t\t_apply_local_developer_grant()')
 t+='''

func _apply_local_developer_grant() -> void:
	if not OS.is_debug_build() or active_player_id != "3b0d68b4-0a85-4b21-a789-79a88be8ec1a":
		return
	if bool(state.flags.get("dev_grant_raven_20261125", false)):
		return
	state.profile["crystals"] = int(state.profile.get("crystals", 0)) + 1000000
	state.profile["paid_moonstones"] = int(state.profile.get("paid_moonstones", 0)) + 1000000
	state.flags["dev_grant_raven_20261125"] = true
	save_now()
	EventBus.currency_changed.emit()
'''
 g.write_text(t,encoding='utf-8')
if not d.setdefault('flags',{}).get(key):
 for k in ('crystals','paid_moonstones'): d['profile'][k]=int(d['profile'].get(k,0))+1000000
 d['flags'][key]=True
 tmp=f.with_suffix('.grant.tmp');tmp.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8');os.replace(tmp,f)
print('Raven local balance:',d['profile']['crystals'],d['profile']['paid_moonstones'])
