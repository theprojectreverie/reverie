extends Control
## Developer-only, read-only review of the real story scenes and boss encounter.
const CHAPTERS := [
	"res://scenes/world/six_zone_reverie/crimson_oath_part_1.tscn",
	"res://scenes/world/six_zone_reverie/crimson_oath_part_2.tscn",
]
const TRACKS := ["ravienna_story_1", "ravienna_story_2"]
@onready var menu: Control = $Menu
@onready var playback: Control = $Playback
@onready var return_button: Button = $ReturnButton
var active_story: GeraldBossIntro
var active_battle: CombatScreen

func _ready() -> void:
	theme = UITheme.build()
	$Menu/Content/Before.pressed.connect(_show_chapter.bind(0))
	$Menu/Content/After.pressed.connect(_show_chapter.bind(1))
	$Menu/Content/Full.pressed.connect(_show_battle)
	return_button.pressed.connect(_return_to_menu)
	AudioDirector.stop_music_immediately()
	if "--ravienna-preview-smoke" in OS.get_cmdline_user_args():
		_smoke.call_deferred()
	if not SaveService.story_preview_mode:
		$Menu/Content/Full.disabled = true
		$Menu/Content/Notice.text = "Run this scene directly with F6 to enable the isolated battle."

func _smoke() -> void:
	assert(SaveService.story_preview_mode and not AuthGateway.is_authenticated())
	var music := AudioDirector.get_node("MusicPlayer") as AudioStreamPlayer
	for index in [0, 1]:
		_show_chapter(index)
		await get_tree().create_timer(0.7).timeout
		assert(is_instance_valid(active_story) and music.playing)
		assert(AudioDirector.requested_music_track() == TRACKS[index])
		var present := active_story.presentation_component
		var sequence := active_story.playback_component
		assert(sequence.shots.size() == (14 if index == 0 else 20))
		assert(str(sequence.shots[-1 if index == 0 else 0]["image"]).ends_with("04_decision_to_escape.png" if index == 0 else "05_castle_side_passage_escape.png"))
		await get_tree().create_timer(0.7).timeout
		var outgoing := present._artwork.texture
		sequence.request_advance()
		await get_tree().create_timer(0.3).timeout
		assert(sequence.shot_index == 1)
		assert(present._previous_artwork.visible and present._previous_artwork.texture == outgoing)
		assert(present._previous_artwork.modulate.a == 1.0)
		assert(present._artwork.modulate.a > 0.0 and present._artwork.modulate.a < 1.0)
		await get_tree().create_timer(1.7).timeout
		assert(not present._previous_artwork.visible and present._artwork.modulate.a == 1.0)
		_return_to_menu()
		await get_tree().create_timer(1.5).timeout
		assert(menu.visible and not is_instance_valid(active_story))
		print("PREVIEW chapter ", index + 1, " PASS")
	_show_battle()
	await get_tree().create_timer(1.5).timeout
	assert(is_instance_valid(active_battle) and active_battle.engine != null)
	assert(active_battle.engine.living(0).size() == 3)
	assert(active_battle.engine.living(1)[0].max_hp == 1000.0)
	assert(AudioDirector.requested_music_track() == "ravienna_boss")
	var flags := GameState.quest_domain.flags.duplicate(true)
	active_battle._claim(true)
	await get_tree().create_timer(1.0).timeout
	assert(menu.visible and not is_instance_valid(active_battle))
	assert(GameState.quest_domain.flags == flags)
	print("PREVIEW battle and read-only victory PASS")
	await AudioDirector.drain_for_shutdown()
	get_tree().quit()

func _show_chapter(index: int) -> void:
	if is_instance_valid(active_story) or is_instance_valid(active_battle):
		return
	menu.hide()
	return_button.show()
	active_story = (load(CHAPTERS[index]) as PackedScene).instantiate() as GeraldBossIntro
	if AudioDirector.play_track(TRACKS[index], 0.35):
		active_story.music_track_id = TRACKS[index]
	playback.add_child(active_story)
	await active_story.finished
	active_story.queue_free()
	await active_story.tree_exited
	active_story = null
	_reset_menu()

func _show_battle() -> void:
	if not SaveService.story_preview_mode or is_instance_valid(active_story) or is_instance_valid(active_battle):
		return
	menu.hide()
	return_button.show()
	active_battle = (load("res://scenes/ui/combat_screen.tscn") as PackedScene).instantiate() as CombatScreen
	active_battle.group_id = "revienna_encounter"
	active_battle.closed.connect(_battle_closed)
	playback.add_child(active_battle)

func _battle_closed() -> void:
	if is_instance_valid(active_battle):
		await active_battle.tree_exited
	active_battle = null
	_reset_menu()

func _return_to_menu() -> void:
	if is_instance_valid(active_story):
		active_story.call("_finish")
	elif is_instance_valid(active_battle):
		active_battle._claim(false)

func _reset_menu() -> void:
	AudioDirector.stop_music(0.4)
	return_button.hide()
	menu.show()

func _exit_tree() -> void:
	if is_instance_valid(AudioDirector):
		AudioDirector.stop_music_immediately()
