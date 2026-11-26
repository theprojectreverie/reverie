extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 var idle=load("res://assets/enemies/gerald_fallen/idle_directions.tres") as SpriteFrames
 var walk=load("res://assets/enemies/gerald_fallen/walk_directions.tres") as SpriteFrames
 var combat=load("res://assets/enemies/gerald_fallen/combat_frames.tres") as SpriteFrames
 var out=SpriteFrames.new()
 out.remove_animation("default")
 var directions=["s","se","e","ne","n","nw","w","sw"]
 var idles=["front","right","right","right","back","left","left","left"]
 for d in range(8):
  for state in ["idle","walk","run","interact","attack","damage","victory","defeat","cast"]:
   var source=idle
   var clip="idle_"+idles[d]
   var fps=4.0
   var loop=state in ["idle","walk","run"]
   if state in ["walk","run"]:
    source=walk
    clip="walk_"+directions[d]
    fps=12.0 if state=="walk" else 16.0
   elif state in ["attack","cast","damage","defeat"]:
    source=combat
    clip={"attack":"attack","cast":"attack","damage":"hit","defeat":"defeat"}[state]
    fps=10.0
   var name=state+"_"+str(d)
   out.add_animation(name)
   out.set_animation_speed(name,fps)
   out.set_animation_loop(name,loop)
   for i in range(source.get_frame_count(clip)):
    out.add_frame(name,source.get_frame_texture(clip,i))
 assert(ResourceSaver.save(out,"res://assets/characters/gerald/world_sheet_fallen.tres")==OK)
 print("GERALD AUTHORED RESOURCE ",out.get_animation_names().size()," animations")
 quit()
