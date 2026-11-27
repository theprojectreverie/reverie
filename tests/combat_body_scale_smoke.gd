extends Node
var failures: Array[String] = []
var count := 0
func check(ok:bool,label:String)->void:
	if not ok: failures.append(label);push_error(label)
func _ready()->void: call_deferred("_run")
func _run()->void:
	var field:=preload("res://scenes/ui/battlefield.tscn").instantiate() as Battlefield
	add_child(field)
	field.size=Vector2(1000,450)
	var hero:=CombatFactory.build_from_character(CharacterInstance.from_dict({"char_id":"kael","uid":"size_hero","level":1}))
	var enemy:=CombatFactory.enemy_units("gerald_boss_encounter")[0] as Combatant
	var tested:Dictionary={}
	for id in ContentDB.characters:
		var u:=CombatFactory.build_from_character(CharacterInstance.from_dict({"char_id":id,"uid":"size_"+str(id),"level":1}))
		if u==null: check(false,"missing playable "+str(id));continue
		field.arena_id="gerald_boss_encounter"
		field.setup([u],[enemy]);await get_tree().process_frame
		var a:=field.actor_for_uid(u.uid)
		check(a!=null,"actor "+str(id))
		if a==null:continue
		check_actor(a)
		tested[id]=true
		count+=1
	for group in ContentDB.enemy_groups:
		var enemies:=CombatFactory.enemy_units(str(group))
		for u in enemies:
			if tested.has(u.def_id):continue
			field.arena_id=str(group)
			field.setup([hero],[u]);await get_tree().process_frame
			var a:=field.actor_for_uid(u.uid)
			check(a!=null,"enemy "+u.def_id)
			if a!=null:check_actor(a);count+=1
			tested[u.def_id]=true
	# Enemy definitions without encounter assignment still receive the same scene-level scale policy.
	for id in ContentDB.enemies:
		if tested.has(id):continue
		var u:=Combatant.new();u.def_id=str(id);u.uid="size_"+str(id);u.display_name=str(id);u.hp=100;u.max_hp=100
		field.setup([hero],[u]);await get_tree().process_frame
		check_actor(field.actor_for_uid(u.uid));count+=1
		tested[id]=true
	check(count==ContentDB.characters.size()+ContentDB.enemies.size(),"all definitions covered")
	print("COMBAT_SIZE_AUDIT count=",count," failures=",failures.size())
	field.queue_free();await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
func check_actor(a:BattlefieldActor)->void:
	var id:=a.unit.def_id
	for name in ["KaelAnimationPlayer","BattlePoseAnimationPlayer","AnimationPlayer"]:
		var p:=a.get_node(name) as AnimationPlayer
		for clip in p.get_animation_list():
			if clip=="RESET":continue
			var animation:=p.get_animation(clip)
			for i in animation.get_track_count():
				if str(animation.track_get_path(i))!="ActorVisual:scale":continue
				for k in animation.track_get_key_count(i):
					check(animation.track_get_key_value(i,k).is_equal_approx(Vector2.ONE),id+" nonuniform "+clip)
	var visual:=a.visual
	var lp:=visual.animation_component.get_player()
	for clip in lp.get_animation_list():
		var anim:=lp.get_animation(clip)
		for i in anim.get_track_count():
			check(str(anim.track_get_path(i))!="FrameSprite:scale",id+" absolute idle scale")
	if a.kael_boss_art_enabled:
		var idle:=a.kael_boss_art.scale.x
		for clip in [&"approach",&"attack",&"retreat",&"idle"]:
			a.play_kael_boss_clip(clip)
			var art:=a.kael_boss_art
			var expected:=idle*(1.12 if clip==&"attack" else 0.96 if clip!=&"idle" else 1.0)
			for i in art.sprite_frames.get_frame_count(clip):
				art.set_frame_and_progress(i,0.0);a._sync_kael_boss_art()
				check(is_equal_approx(art.scale.x,expected) and is_equal_approx(art.scale.y,expected),id+" clip scale "+str(clip))
		check(a.kael_boss_art.visible and not visual.visible,id+" same combat model")
	elif is_instance_valid(a.gerald_art):
		for ult in [false,true]:
			a.play_gerald_action(ult)
			check(is_equal_approx(a.gerald_art.scale.x,a.gerald_art.scale.y),id+" boss uniform")
			check(is_equal_approx(a.gerald_art.scale.x,a._base_scale*(1.0 if ult else 1.06)),id+" boss calibrated")
	elif is_instance_valid(a.rose_art):
		for clip in [&"idle",&"attack",&"hit"]:
			a.rose_art.play(clip);a._sync_monster_body_scale()
			var expected:=1.4*(1.20 if id=="crownling" and clip==&"attack" else 1.08 if id=="crownling" and clip==&"hit" else 1.0)
			check(is_equal_approx(a.rose_art.scale.x,expected) and is_equal_approx(a.rose_art.scale.y,expected),id+" monster clip calibration")
	elif visual._sprite_active and visual.visible:
		for state in [ActorVisual.S_IDLE,ActorVisual.S_ATTACK,ActorVisual.S_CAST,ActorVisual.S_DAMAGE]:
			visual.animator.play_forced(state);visual.refresh_animation_presentation()
			check(absf(visual._sprite.scale.x-visual._sprite.scale.y)<0.025,id+" body uniform "+str(state))
	print("SIZE_CHECKED ",id," authored=",not visual.using_temporary_art or not visual.visible)
