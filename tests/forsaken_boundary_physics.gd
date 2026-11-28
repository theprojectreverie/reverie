extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 var p:CharacterBody2D=z.checkpoint_player
 var space=z.get_world_2d().direct_space_state
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=p.get_node("CollisionShape2D").shape
 q.collision_mask=1
 var perimeter=z.get_node("TerrainPerimeter/TerrainOutline")
 var hits=0
 for i in range(perimeter.polygon.size()):
  var a=perimeter.to_global(perimeter.polygon[i])
  var b=perimeter.to_global(perimeter.polygon[(i+1)%perimeter.polygon.size()])
  for t in [.15,.5,.85]:
   q.transform=Transform2D(0,a.lerp(b,t))
   if space.intersect_shape(q,32).any(func(h):return h.collider==perimeter.get_parent()):hits+=1
 print("PERIMETER PLAYER SHAPE ",hits,"/",perimeter.polygon.size()*3)
 var failures=[]
 if hits!=perimeter.polygon.size()*3:failures.append("Perimeter gap")
 var arches=0
 for n in z.find_children("*","Node2D",true,false):
  if not n.has_node("Body") or not n.has_node("Artwork"):continue
  var art=n.get_node("Artwork")
  if not art is Sprite2D or art.texture==null or not art.texture.resource_path.contains("arch"):continue
  arches+=1
  # Verify a player-sized footprint can cross between the pillars in the arch's own plane.
  var body=n.get_node("Body")
  var best=0
  for x in range(-30,31,5):
   var clear=true
   for y in range(-28,29,7):
    q.transform=Transform2D(0,n.to_global(Vector2(x,y)))
    if space.intersect_shape(q,32).any(func(h):return h.collider==body):clear=false
   if clear:best+=1
  print("ARCH ",n.name," clear crossing lanes ",best)
  if best==0:failures.append("Arch no crossing lane "+str(n.get_path()))
 print("ARCHES ",arches)
 if not failures.is_empty():
  for f in failures:push_error(f)
  quit(1);return
 print("BOUNDARY AND ARCH PLAYER-SHAPE PASS")
 quit(0)

