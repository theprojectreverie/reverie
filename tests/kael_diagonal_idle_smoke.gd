extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var sheet := load("res://assets/characters/kael_avatar/world_sheet.tres") as SpriteFrames
	assert(sheet != null and sheet.get_animation_names().size()==72)
	var directions := ["south","south_east","east","north_east","north","north_west","west","south_west"]
	var atlases := {}
	for d in range(8):
		var clip := StringName("idle_%d" % d)
		assert(sheet.has_animation(clip) and sheet.get_frame_count(clip)==5)
		assert(sheet.get_animation_loop(clip) and is_equal_approx(sheet.get_animation_speed(clip),6.0))
		var unique := {}
		var baseline := -1
		for i in range(5):
			var tex := sheet.get_frame_texture(clip,i) as AtlasTexture
			assert(tex != null and tex.get_width()==128 and tex.get_height()==128)
			assert(tex.atlas.resource_path.ends_with("kael_idle_%s_128x128.png" % directions[d]))
			atlases[tex.atlas.resource_path]=true
			var img := tex.atlas.get_image().get_region(Rect2i(tex.region))
			var bounds := img.get_used_rect()
			assert(bounds.size.x>30 and bounds.size.y>70 and bounds.position.x>0 and bounds.end.x<128)
			assert(img.get_pixel(0,0).a==0.0)
			if d%2==1:
				if baseline<0:baseline=bounds.end.y
				assert(bounds.end.y==baseline)
			unique[img.get_data().hex_encode().sha256_text()]=true
		if d%2==1:assert(unique.size()==5)
	assert(atlases.size()==8)
	var visual := (load("res://scenes/characters/actor_visual.tscn") as PackedScene).instantiate() as ActorVisual
	root.add_child(visual)
	await process_frame
	var report := visual.configure_character("kael")
	assert(report.get("registered",false) and not report.get("fallback_active",true))
	for d in range(8):
		visual.play(ActorVisual.S_WALK,d)
		await process_frame
		visual.play(ActorVisual.S_IDLE,d)
		await process_frame
		assert(visual.animator.direction==d and visual.animator.state==ActorVisual.S_IDLE)
	visual.queue_free()
	await process_frame
	print("KAEL_DIAGONAL_IDLE_PASS: eight distinct directional sheets, 40 frames, 72 clips, valid player art and walk-to-idle direction")
	quit(0)
