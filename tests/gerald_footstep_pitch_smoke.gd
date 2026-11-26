extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var audio=root.get_node("AudioDirector")
 var stream=load("res://assets/audio/sfx/extended/dirt_step/dirt_step_1.wav")
 var count=audio._sfx_players.size()
 for player in audio._sfx_players:
  player.stop()
 for i in range(count):
  audio._play_sfx_stream(stream,-7.0,0.72)
 var low=true
 for player in audio._sfx_players:
  low=low and is_equal_approx(player.pitch_scale,0.72)
 print("TITAN_PITCH=",low)
 for i in range(count):
  audio._play_sfx_stream(stream,-30.0)
 var reset=true
 for player in audio._sfx_players:
  reset=reset and is_equal_approx(player.pitch_scale,1.0)
 print("POOLED_PITCH_RESET=",reset)
 audio.stop_all_audio_immediately()
 await process_frame
 quit(0 if low and reset else 1)
