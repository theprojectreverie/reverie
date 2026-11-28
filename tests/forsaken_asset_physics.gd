extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2);return
 root.get_node("GameState").quest_domain.flags["tutorial_complete"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var z=current_scene
 var space=z.get_world_2d().direct_space_state
 var q=PhysicsPointQueryParameters2D.new()
 q.collision_mask=1
 var count=0
 var failures=[]
 for n in z.find_children("*","CollisionPolygon2D",true,false):
  if not n.get_parent() is StaticBody2D:continue
  count+=1
  if n.polygon.size()<3 or (n.build_mode==0 and Geometry2D.triangulate_polygon(n.polygon).is_empty()):
   failures.append("Invalid polygon "+str(n.get_path()))
 for path in ["RuinsDecoration/EastArch","RuinsDecoration/FarArch","CemeteryDressing/NorthRuinedArch"]:
  var n=z.get_node(path)
  q.position=n.global_position
  if not space.intersect_point(q,12).is_empty():failures.append("Blocked arch center "+path)
  for foot in n.get_node("Body").get_children():
   if not foot is CollisionPolygon2D:continue
   var center=Vector2.ZERO
   for v in foot.polygon:center+=v
   center/=foot.polygon.size()
   q.position=foot.to_global(center)
   if not space.intersect_point(q,12).any(func(hit):return hit.collider==foot.get_parent()):failures.append("Non-solid arch foot "+path)
 for name in ["ExtraCandleWest","ExtraCandleFront","OfferingAtTomb","OfferingEast"]:
  var n=z.get_node("RaviennaCourtyard/MemorialSanctuary/"+name)
  q.position=n.global_position
  if not space.intersect_point(q,12).any(func(hit):return hit.collider==n.get_node("Body")):failures.append("Non-solid candle base "+name)
 for n in [z,z.get_node("Zone"),z.get_node("RaviennaCourtyard"),z.get_node("RaviennaCourtyard/MemorialSanctuary"),z.get_node("RuinsDecoration"),z.get_node("CemeteryDressing"),z.get_node("ArchitecturalDistricts"),z.get_node("CentralRuinsClusters"),z.get_node("CrimsonWoodlandClusters"),z.get_node("RuinedKingdomLandmarks")]:
  if not n.y_sort_enabled or n.z_index!=0:failures.append("Sorting group "+str(n.get_path()))
 if z.checkpoint_player.z_index!=0:failures.append("Player z index")
 for name in ["ForsakenGroundDressing","RuinAtmosphere"]:
  if not z.get_node(name).find_children("*","StaticBody2D",true,false).is_empty():failures.append("Decorative collision "+name)
 var marker=z.get_node("TransferPoints/ToNextZone")
 var tower=marker.get_node("RuinedTowerWalls")
 var art=marker.get_node("SoutheastRoadContinuation")
 if not marker.y_sort_enabled or not marker.get_parent().y_sort_enabled or art.z_index!=0:
  failures.append("Tower sorting chain")
 for foot in tower.get_children():
  var center=Vector2.ZERO
  for v in foot.polygon:center+=v
  q.position=foot.to_global(center/foot.polygon.size())
  if not space.intersect_point(q,32).any(func(hit):return hit.collider==tower):
   failures.append("Tower wall not solid "+str(foot.name))
 var player_query=PhysicsShapeQueryParameters2D.new()
 player_query.shape=z.checkpoint_player.get_node("CollisionShape2D").shape
 player_query.collision_mask=1
 for y in range(-120,1,10):
  player_query.transform=Transform2D(0,marker.to_global(Vector2(-96,y-10)))
  if space.intersect_shape(player_query,32).any(func(hit):return hit.collider==tower):
   failures.append("Tower doorway obstructed at "+str(y))
 for name in ["NorthRubble","EastRubble","SouthRubble","MidRubble"]:
  var rubble=z.get_node("RuinsDecoration/"+name)
  var body=rubble.get_node("Body")
  q.position=rubble.global_position
  if not space.intersect_point(q,32).any(func(hit):return hit.collider==body):
   failures.append("Non-solid rubble "+name)
 for path in ["RuinedKingdomLandmarks/WesternManor","RuinedKingdomLandmarks/EasternManor","RuinedKingdomLandmarks/NorthChapel","RuinedKingdomLandmarks/SouthernTerrace","RuinedKingdomLandmarks/UpperTerrace","ArchitecturalDistricts/SouthernRockyTerrace"]:
  var ruin=z.get_node(path)
  var artwork=ruin.get_node("Artwork")
  var foot=ruin.get_node("Body/Footprint")
  var front=-INF
  for v in foot.polygon:front=maxf(front,ruin.to_local(foot.to_global(v)).y)
  if not ruin.y_sort_enabled or artwork.z_index!=0 or absf(artwork.position.y-front)>1.0:
   failures.append("Ruin depth anchor "+path)
 if not failures.is_empty():
  for failure in failures:push_error(failure)
  quit(1);return
 print("FORSAKEN PHYSICS AUDIT PASS: ",count," static polygons, arch feet/openings, candle bases, sorting groups, decorative layers")
 quit(0)

