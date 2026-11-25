extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/enemies/boss/gerald_boss_intro.tscn") as PackedScene
	assert(packed != null)
	var intro := packed.instantiate() as GeraldBossIntro
	get_tree().root.add_child(intro)
	await get_tree().process_frame
	var playback := intro.get_node("Playback") as GeraldCinematicPlaybackComponent
	assert(playback.active and playback.auto_play, "Autoplay should be enabled on cinematic start.")
	for shot in playback.shots:
		shot["duration"] = 0.55
	var seen := [0]
	playback.shot_changed.connect(func(_index: int, _shot: Dictionary, _total: int) -> void: seen[0] += 1)
	var completed := [false]
	intro.finished.connect(func() -> void: completed[0] = true)
	await get_tree().create_timer(12.0).timeout
	assert(completed[0], "Autoplay did not complete the sequence. index=%d active=%s elapsed=%.2f seen=%d" % [playback.shot_index, str(playback.active), playback.shot_elapsed, seen[0]])
	assert(seen[0] == 6, "Expected transitions through all six following shots; got %d." % seen[0])
	assert(playback.shot_index == 7 and not playback.active, "Playback did not reach the terminal sequence state.")
	print("[GeraldPlaybackSmoke] PASS — autoplay advances all seven shots and finishes cleanly.")
	intro.queue_free()
	get_tree().quit()
