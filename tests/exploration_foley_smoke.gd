extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var audio=root.get_node("AudioDirector")
 audio.stop_all_audio_immediately()
 var foley=audio.get_node("ExplorationFoley")
 for category in ["stone_step","grass_step","dirt_step","wood_step","water_entry","water_step"]:
  audio.play_variant(category,-5.0,1.0,true)
  await process_frame
  assert(foley.playing and foley.stream.resource_path.contains(category))
  assert(foley.max_polyphony==1)
  assert(foley.volume_db<=float(audio.EXPLORATION_FOLEY_LEVELS[category]))
  assert(not audio._sfx_players.any(func(p):return p.playing))
 assert(audio.play_kael_voice("exploration/ahead",root,true))
 audio.play_variant("dirt_step",-5.0,1.0,true)
 assert(foley.volume_db==-20.0)
 audio.play_variant("dirt_step",-5.0)
 assert(audio._sfx_players.any(func(p):return p.playing and p.volume_db==-5.0))
 audio.stop_all_audio_immediately()
 assert(not foley.playing and foley.stream==null)
 print("SINGLE EXPLORATION FOLEY, MATERIAL LEVELS, VOICE DUCKING, COMBAT UNCHANGED, CLEANUP PASS")
 quit(0)