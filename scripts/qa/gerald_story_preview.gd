extends Control
## Developer-only playback of the real authored Gerald cinematics and dialogues.
## No village, combat, quest actions, rewards or checkpoints are instantiated.

const CHAPTERS := [
	"res://scenes/enemies/boss/gerald_before_the_fall.tscn",
	"res://scenes/enemies/boss/gerald_boss_intro.tscn",
]
const TRACKS := ["gerald_childhood", "gerald_tragedy"]
const DIALOGUES := ["gerald_kael_after_battle", "gerald_kael_after_the_fall", "gerald_kael_farewell"]

@onready var menu: Control = $Menu
@onready var playback: Control = $Playback
@onready var dialogue: DialogueBox = $Dialogue
@onready var return_button: Button = $ReturnButton
@onready var status: Label = $Status
var active_story: Control
var running := false
var cancelled := false

func _ready() -> void:
	theme = UITheme.build()
	$Menu/Content/Before.pressed.connect(_start.bind(0))
	$Menu/Content/After.pressed.connect(_start.bind(1))
	$Menu/Content/Full.pressed.connect(_start.bind(2))
	return_button.pressed.connect(_cancel)
	_show_menu()
	AudioDirector.stop_music_immediately()

func _show_menu() -> void:
	menu.show()
	return_button.hide()
	status.hide()
	running = false
	cancelled = false

func _start(mode: int) -> void:
	if running:
		return
	running = true
	cancelled = false
	menu.hide()
	return_button.show()
	return_button.disabled = false
	status.show()
	if mode == 2:
		await _show_dialogue(0)
		if not cancelled:
			await _show_chapter(0)
		if not cancelled:
			await _show_dialogue(1)
		if not cancelled:
			await _show_chapter(1)
		if not cancelled:
			await _show_dialogue(2)
	else:
		await _show_chapter(mode)
	AudioDirector.stop_music_immediately()
	_show_menu()

func _show_dialogue(index: int) -> void:
	AudioDirector.stop_music(0.8)
	status.text = "POST-BATTLE DIALOGUE" if index == 0 else ("BETWEEN CHAPTERS" if index == 1 else "FAREWELL")
	dialogue.open(DIALOGUES[index])
	if dialogue.visible:
		await dialogue.closed
	await get_tree().process_frame

func _show_chapter(index: int) -> void:
	status.text = "BEFORE THE FALL" if index == 0 else "AFTER THE FALL"
	var packed := load(CHAPTERS[index]) as PackedScene
	if packed == null or not packed.can_instantiate():
		push_error("[GeraldPreview] Missing cinematic scene.")
		return
	active_story = packed.instantiate() as Control
	if AudioDirector.play_track(TRACKS[index], 1.4):
		active_story.set("music_track_id", TRACKS[index])
	playback.add_child(active_story)
	await active_story.finished
	active_story.queue_free()
	await active_story.tree_exited
	active_story = null
	await get_tree().process_frame
	AudioDirector.stop_music(0.8)

func _cancel() -> void:
	if not running:
		return
	cancelled = true
	return_button.disabled = true
	if dialogue.visible:
		dialogue.close()
	elif is_instance_valid(active_story):
		active_story.call("_finish")

func _exit_tree() -> void:
	if is_instance_valid(AudioDirector):
		AudioDirector.stop_music_immediately()