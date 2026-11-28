extends SceneTree
const SCENE="res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn"
const PROBE=Vector2(10000,-10000)
var zone:Node2D
var player:CharacterBody2D
var camera:Camera2D
var pm:Polygon2D
func _initialize():call_deferred("_run")
func anchor(n:Node2D)->Node2D:
 var chain:Array[Node2D]=[]
 var p:Node=n
 while p!=zone and p is Node2D:
  chain.push_front(p)
  p=p.get_parent()
 for x in chain:
  if not x.y_sort_enabled:return x
 return n
func layer(n:CanvasItem)->int:
 var zz=0
 var p:Node=n
 while p is CanvasItem:
  zz+=p.z_index
  if not p.z_as_relative:break
  p=p.get_parent()
 return zz
func marker(n:Node2D,color:Color)->Polygon2D:
 var m=Polygon2D.new()
 m.polygon=PackedVector2Array([Vector2(-36,-36),Vector2(36,-36),Vector2(36,36),Vector2(-36,36)])
 m.color=color
 m.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
 n.add_child(m)
 m.global_transform=Transform2D(0,PROBE)
 return m
func pixel(m:Polygon2D)->Color:
 for i in range(2):
  pm.global_transform=Transform2D(0,PROBE)
  m.global_transform=Transform2D(0,PROBE)
  await process_frame
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image()
 return img.get_pixel(int(img.get_width()/2),int(img.get_height()/2))
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 change_scene_to_file(SCENE)
 await scene_changed
 for i in range(5):await process_frame
 zone=current_scene
 player=zone.get("checkpoint_player")
 player.set("input_enabled",false)
 player.get_node("LocomotionComponent").set_physics_process(false)
 player.get_node("Camera2D").enabled=false
 zone.get_node("UI").hide()
 camera=Camera2D.new()
 zone.add_child(camera)
 camera.global_position=PROBE
 camera.make_current()
 camera.force_update_scroll()
 camera.reset_physics_interpolation()
 pm=marker(player.get_node("ActorVisual/FrameSprite"),Color.MAGENTA)
 var city=zone.get_node("Zone")
 var targets:Array[Node2D]=[]
 # Freeze decorative animations only for deterministic pixel ordering; movement is checked separately.
 for animation in city.find_children("*","AnimationPlayer",true,false):animation.pause()
 for g in [city,zone.get_node("Waystone")]:
  for s in g.find_children("*","Sprite2D",true,false):
   if s.is_visible_in_tree() and s.texture and s.name!="LanternLight" and layer(s)==0:targets.append(s)
  for s in g.find_children("ArtworkRegion","Polygon2D",true,false):
   if s.is_visible_in_tree() and s.texture and s.name!="LanternLight" and layer(s)==0:targets.append(s)
  for s in g.find_children("*","AnimatedSprite2D",true,false):
   if s.is_visible_in_tree() and s.sprite_frames and layer(s)==0:targets.append(s)
 var errors=[]
 var checked=0
 for s in targets:
  if not s.is_visible_in_tree():continue
  var a=anchor(s)
  var zz=layer(s)
  var m=marker(s,Color.GREEN)
  for d in [-45,45]:
   player.global_position=Vector2(7000,a.global_position.y+d)
   player.reset_physics_interpolation()
   var c=await pixel(m)
   var green=c.g>.7 and c.r<.3 and c.b<.3
   var magenta=c.r>.7 and c.b>.7 and c.g<.3
   var want_green=zz>0 or (zz==0 and d<0)
   if not (green if want_green else magenta):
    errors.append(str(zone.get_path_to(s))+" d="+str(d)+" z="+str(zz)+" got="+str(c))
   checked+=1
  m.free()
  if checked%100==0:print("DEPTH progress ",checked," errors=",errors.size())
 print("DEPTH RENDER CHECKS ",checked," assets=",targets.size()," errors=",errors.size())
 for e in errors:print(e)
 pm.free()
 zone.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit(0 if errors.is_empty() and checked>=200 else 1)

