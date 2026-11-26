extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/characters.json"))
 var vis=load("res://scenes/characters/actor_visual.tscn").instantiate()
 root.add_child(vis)
 await process_frame
 var missing=[]
 var valid=[]
 var errors=[]
 var clips=0
 for id in data:
  var source=SpriteFramesActorSource.from_playable(id)
  var expected=not str(data[id].get("assets",{}).get("world_sheet","")).is_empty()
  if not source.has_frames():
   missing.append(id)
   if expected:errors.append([id,source.validate_sheets().slice(0,3)])
   continue
  valid.append(id)
  var report=vis.configure_character(id)
  if not report.registered:errors.append([id,"registration"]);continue
  for state in range(9):
   for direction in range(8):
    vis.animator.play_forced(state,direction)
    vis._update_sprite_frame()
    if not vis._sprite.visible or vis._sprite.texture!=source.frame(state,direction,vis.animator.frame):
     errors.append([id,state,direction,"frame"])
    if vis.animator.frame_count()!=source.frame_count(state,direction) or not is_equal_approx(vis.animator.fps(),source.fps(state)):
     errors.append([id,state,direction,"timing"])
    clips+=1
  vis.animator.play_forced(0,0)
  await process_frame
  await process_frame
  if vis.get_node("SharedCharacterEffects").visible:errors.append([id,"generic overlay"])
  if vis.get_node("LilithSpectralEffects/SpectralHalo").is_visible_in_tree():errors.append([id,"spectral halo"])
 print("VALID ",valid.size()," / ",data.size()," CLIPS ",clips," MISSING ",missing)
 print("ERRORS ",errors)
 vis.queue_free()
 await process_frame
 var declared:Array=[]
 for id in data:
  if not str(data[id].get("assets",{}).get("world_sheet","")).is_empty():declared.append(id)
 var all_declared_valid:bool=not declared.is_empty() and declared.all(func(id):return valid.has(id))
 print("DECLARED_SHEETS ",declared.size()," ALL_VALID ",all_declared_valid)
 quit(0 if errors.is_empty() and all_declared_valid and valid.size()>=declared.size() else 1)
