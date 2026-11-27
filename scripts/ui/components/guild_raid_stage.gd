extends Control
## Presentation only. Never simulates damage or decides combat outcomes.
signal playback_changed(busy:bool)
var playing:=false
const PORTRAIT=preload("res://scripts/ui/social_portrait.gd")
const KAEL=preload("res://assets/characters/kael/boss_combat/combat_frames.tres")
const CASSIEN=preload("res://assets/characters/cassien/combat/combat_frames.tres")
const REVIENNA=preload("res://assets/characters/revienna/combat/combat_frames.tres")
const GERALD=preload("res://assets/enemies/gerald_fallen/combat_frames.tres")
var _actors:Dictionary={}
var _dead:Dictionary={}
var _party_ids:Array[String]=[]
var _boss_uid:=""
var _attempt_id:=""
var _sequence:=-1
var _epoch:=0

func _ready():
	resized.connect(_layout_art)
	$Boss.animation_finished.connect(_return_idle.bind($Boss))

func reset_stage():
	_epoch+=1
	_set_playing(false)
	_attempt_id=""
	_sequence=-1
	_boss_uid=""
	_actors.clear()
	_dead.clear()
	_party_ids.clear()
	for child in $Party.get_children():
		$Party.remove_child(child)
		child.queue_free()
	$Boss.stop()
	$Feedback.text=""

func _art_for(unit:Dictionary)->Node2D:
	var id:=str(unit.get("charId",""))
	# Only exact, existing art resources. No ActorVisual procedural fallbacks.
	var frames:SpriteFrames=null
	match id:
		"kael":frames=KAEL
		"cassien":frames=CASSIEN
		"revienna","ravienna":frames=REVIENNA
		"gerald":frames=GERALD
	if frames!=null:
		var sprite:=AnimatedSprite2D.new()
		sprite.sprite_frames=frames
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.animation_finished.connect(_return_idle.bind(sprite))
		sprite.play("idle")
		return sprite
	var art:=Sprite2D.new()
	var path:="res://assets/characters/%s/combat_sprite.png" % id
	if ResourceLoader.exists(path):art.texture=load(path) as Texture2D
	else:
		# Use the matching approved portrait only; never borrow another character.
		if PORTRAIT.PATHS.has(id):art.texture=PORTRAIT.legacy_texture(id)
		elif id=="kael":art.texture=PORTRAIT.legacy_texture("kael_avatar")
	art.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	return art

func show_snapshot(attempt_id:String,view:Dictionary,animate:bool=true):
	var seq:=int(view.get("sequence",0))
	var fresh:=attempt_id!=_attempt_id
	if fresh:
		reset_stage()
		_attempt_id=attempt_id
		for unit in view.get("units",[]):
			var uid:=str(unit.uid)
			if int(unit.team)==1:
				_boss_uid=uid
				_actors[uid]=$Boss
				$Boss.show()
				$Boss.modulate=Color.WHITE
				$Boss.play("idle")
			else:
				var art:=_art_for(unit)
				$Party.add_child(art)
				_actors[uid]=art
				_party_ids.append(uid)
		_layout_art()
	if not fresh and seq<=_sequence:return
	var play_events:=animate and not fresh and seq>_sequence
	_sequence=seq
	_epoch+=1
	var epoch:=_epoch
	if play_events:
		_set_playing(true)
		_play_events(view.get("events",[]),epoch,view)
	else:
		_sync_life(view)
		$Feedback.text=""
		_set_playing(false)

func _fit_art(art:Node2D,max_side:float):
	var texture:Texture2D=null
	if art is AnimatedSprite2D:
		var sprite:=art as AnimatedSprite2D
		texture=sprite.sprite_frames.get_frame_texture("idle",0)
	elif art is Sprite2D:texture=(art as Sprite2D).texture
	if texture!=null:
		art.scale=Vector2.ONE*(max_side/maxf(1,maxf(texture.get_width(),texture.get_height())))

func _layout_art():
	var count:=maxi(1,_party_ids.size())
	for i in _party_ids.size():
		var art:Node2D=_actors[_party_ids[i]]
		var col:=i%2
		var row:=i/2
		var x:=size.x*(0.16+float(col)*0.19) if count>1 else size.x*0.26
		art.position=Vector2(x,size.y*(0.61+float(row)*0.19))
		_fit_art(art,minf(size.x*0.18,size.y*0.52))
	$Boss.position=Vector2(size.x*0.76,size.y*0.57)
	_fit_art($Boss,minf(size.x*0.38,size.y*0.88))

func _return_idle(sprite:AnimatedSprite2D):
	if not is_instance_valid(sprite):return
	for uid in _actors:
		if _actors[uid]==sprite and bool(_dead.get(uid,false)):return
	if sprite.sprite_frames.has_animation("idle"):sprite.play("idle")

func _clip(art:Node2D,skill_id:String)->StringName:
	if art is not AnimatedSprite2D:return &""
	var frames:SpriteFrames=art.sprite_frames
	var mapped:=""
	match skill_id:
		"cassien_heavy_cleave":mapped="heavy_attack"
		"cassien_crimson_crescent":mapped="crimson_crescent"
		"cassien_crimson_requiem":mapped="crimson_requiem"
		"ravienna_eclipse":mapped="ravienna_eclipse"
	if mapped.is_empty() and frames.has_animation(skill_id):mapped=skill_id
	if mapped.is_empty():mapped="attack"
	return StringName(mapped) if frames.has_animation(mapped) else &""

func _play(art:Node2D,clip:StringName):
	if is_instance_valid(art) and art is AnimatedSprite2D and not clip.is_empty() and art.sprite_frames.has_animation(clip):
		art.play(clip)
		art.set_frame_and_progress(0,0.0)

func _set_playing(value:bool):
	if playing==value:return
	playing=value
	playback_changed.emit(value)

func _clip_time(art:Node2D,clip:StringName)->float:
	if art is not AnimatedSprite2D or clip.is_empty():return 0.28
	var frames:SpriteFrames=art.sprite_frames
	if not frames.has_animation(clip):return 0.28
	var duration:=0.0
	for i in frames.get_frame_count(clip):duration+=frames.get_frame_duration(clip,i)
	return clampf(duration/maxf(1.0,frames.get_animation_speed(clip)),0.28,2.4)

func _still_current(epoch:int)->bool:
	return epoch==_epoch and is_inside_tree()

func _wait_beat(seconds:float,epoch:int)->bool:
	await get_tree().create_timer(seconds).timeout
	return _still_current(epoch)

func _play_events(events:Array,epoch:int,view:Dictionary):
	# The engine emits action markers followed by their actual outcomes.
	# Respect their order; repeat attacks by the same actor are distinct actions.
	var blocks:Array=[]
	var current:Array=[]
	for event in events:
		if str(event.get("type",""))=="action" and not current.is_empty():
			blocks.append(current)
			current=[]
		current.append(event)
	if not current.is_empty():blocks.append(current)
	for block in blocks:
		if not _still_current(epoch):return
		var duration:=0.0
		var started:=false
		for event in block:
			if not _still_current(epoch):return
			var kind:=str(event.get("type",""))
			var source:=str(event.get("actor_uid",""))
			var target:=str(event.get("target_uid",""))
			match kind:
				"action":
					$Feedback.text="%s: %s" % [str(event.get("actor_name","")),str(event.get("skill_name","Skill"))]
					if _actors.has(source):
						var art:Node2D=_actors[source]
						var clip:=_clip(art,str(event.get("skill_id","")))
						duration=_clip_time(art,clip)
						_play(art,clip)
					else:duration=0.28
					started=true
					if not await _wait_beat(duration*0.45,epoch):return
				"damage":
					if not started and _actors.has(source):
						var art:Node2D=_actors[source]
						var clip:=_clip(art,str(event.get("skill_id","")))
						duration=_clip_time(art,clip)
						_play(art,clip)
						started=true
						if not await _wait_beat(duration*0.45,epoch):return
					if _actors.has(target):_play(_actors[target],&"hit")
					$Feedback.text="%s%s: -%d HP" % ["Critical! " if bool(event.get("crit",false)) else "",str(event.get("target_name","")),int(event.get("amount",0))]
					if not await _wait_beat(0.22,epoch):return
				"heal","shield":
					$Feedback.text="%s: +%d %s" % [str(event.get("target_name","")),int(event.get("amount",0)),"HP" if kind=="heal" else "shield"]
					if not await _wait_beat(0.22,epoch):return
				"miss":
					$Feedback.text="%s: Miss" % str(event.get("target_name",""))
					if not await _wait_beat(0.22,epoch):return
				"defend":
					$Feedback.text="%s defends" % str(event.get("actor_name",""))
					if not await _wait_beat(0.25,epoch):return
		if started and not await _wait_beat(maxf(0.15,duration*0.55),epoch):return
	if _still_current(epoch):
		_sync_life(view)
		_set_playing(false)

func _sync_life(view:Dictionary):
	for unit in view.get("units",[]):
		var uid:=str(unit.uid)
		if not _actors.has(uid):continue
		var art:Node2D=_actors[uid]
		var dead:=float(unit.hp)<=0
		var was_dead:=bool(_dead.get(uid,false))
		_dead[uid]=dead
		if dead and not was_dead:
			if art is AnimatedSprite2D and art.sprite_frames.has_animation("defeat"):_play(art,&"defeat")
			else:art.modulate.a=0.35
		elif not dead:
			art.modulate.a=1.0
