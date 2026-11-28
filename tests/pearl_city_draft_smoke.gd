extends SceneTree
const SCENE="res://scenes/world/six_zone_reverie/pearl_city_draft/pearl_city_playable_preview.tscn"
func _initialize():
	var root=load(SCENE).instantiate() as Node2D
	var ground=root.get_node("DraftGround") as TileMapLayer
	var footprints=[]
	for poly in root.find_children("*","CollisionPolygon2D",true,false):
		var points=PackedVector2Array()
		var node:Node2D=poly
		var offset=Vector2.ZERO
		while node!=root:
			offset+=node.position
			node=node.get_parent()
		for v in poly.polygon: points.append(v+offset)
		footprints.append(points)
	var samples=0
	var missing=0
	var blocked=0
	var nearest=INF
	for path in root.get_node("WalkableRoutes").get_children():
		var cv=path.curve
		for i in range(cv.point_count-1):
			var a=cv.get_point_position(i)
			var b=cv.get_point_position(i+1)
			var n=ceili(a.distance_to(b)/16.0)
			for j in range(n+1):
				var p=a.lerp(b,float(j)/maxi(n,1))
				samples+=1
				if ground.get_cell_source_id(ground.local_to_map(p-ground.position))==-1: missing+=1
				for poly in footprints:
					if Geometry2D.is_point_in_polygon(p,poly):
						blocked+=1
						print("BLOCKED ",path.name," ",p)
					for k in range(poly.size()):
						nearest=minf(nearest,p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[k],poly[(k+1)%poly.size()])))
	var sprites=root.find_children("*","Sprite2D",true,false).size()
	print("PEARL_DRAFT: tiles=",ground.get_used_cells().size()," sprites=",sprites," footprints=",footprints.size()," route_samples=",samples," missing_ground=",missing," blocked=",blocked," nearest_edge=",snappedf(nearest,0.1))
	var ok=missing==0 and blocked==0 and sprites>=17 and footprints.size()>=18
	root.free()
	quit(0 if ok else 1)

