@tool
extends EditorPlugin

const PATHS := [
	"res://assets/cinematics/crimson_oath/part_1/sequence.json",
	"res://assets/cinematics/crimson_oath/part_2/sequence.json"
]
const TARGETS := [208.0, 222.77]
var dock: VBoxContainer
var chapter: OptionButton
var scene_list: ItemList
var preview: TextureRect
var duration: SpinBox
var dissolve: SpinBox
var status: Label
var total_label: Label
var shots: Array = []
var selected := -1
var loaded_chapter := 0
var original_text := ""
var dirty := false

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Crimson Oath Storyboard"
	dock.custom_minimum_size = Vector2(320, 400)
	var heading := Label.new()
	heading.text = "RAVIENNA & CASSIEN"
	dock.add_child(heading)
	chapter = OptionButton.new()
	chapter.add_item("I - Forbidden Blossoms")
	chapter.add_item("II - The Adagio of Unresolved Grief")
	chapter.item_selected.connect(_switch_chapter)
	dock.add_child(chapter)
	total_label = Label.new()
	dock.add_child(total_label)
	scene_list = ItemList.new()
	scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_list.custom_minimum_size.y = 170
	scene_list.fixed_icon_size = Vector2i(100, 56)
	scene_list.item_selected.connect(_select_shot)
	dock.add_child(scene_list)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(300, 169)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dock.add_child(preview)
	duration = _add_number("Seconds:", 1.0, 120.0, 0.01, _duration_changed)
	dissolve = _add_number("Dissolve:", 0.1, 8.0, 0.1, _dissolve_changed)
	for labels in [["Move Up", "Move Down", "Save"], ["Fit to Music", "Reload"]]:
		var row := HBoxContainer.new()
		for label in labels:
			var button := Button.new()
			button.text = label
			button.pressed.connect(_action.bind(label))
			row.add_child(button)
		dock.add_child(row)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_load_chapter(0)
	if OS.get_environment("REVERIE_STORYBOARD_SMOKE") == "1":
		assert(shots.size() == 14 and absf(_sum_duration() - 208.0) < 0.01)
		_select_shot(4)
		assert(preview.texture != null)
		var original_image := str(shots[4]["image"])
		_action("Move Down")
		assert(str(shots[5]["image"]) == original_image)
		_duration_changed(20.0)
		_fit()
		assert(absf(_sum_duration() - 208.0) < 0.01)
		_load_chapter(1)
		assert(shots.size() == 20 and absf(_sum_duration() - 222.77) < 0.01)
		_select_shot(11)
		assert(preview.texture != null)
		_load_chapter(0)
		print("CRIMSON OATH STORYBOARD SMOKE PASS: chapters, preview, reorder, fit; no save")

func _add_number(caption: String, low: float, high: float, step: float, callback: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = low
	number.max_value = high
	number.step = step
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number.value_changed.connect(callback)
	row.add_child(number)
	dock.add_child(row)
	return number

func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()

func _switch_chapter(index: int) -> void:
	if dirty:
		chapter.select(loaded_chapter)
		status.text = "Save your changes or press Reload to discard them first."
		return
	_load_chapter(index)

func _load_chapter(index: int) -> void:
	loaded_chapter = index
	selected = -1
	shots = []
	original_text = FileAccess.get_file_as_string(PATHS[index])
	var parsed: Variant = JSON.parse_string(original_text)
	if parsed is Dictionary:
		for entry in parsed.get("shots", []):
			if entry is Dictionary:
				shots.append(entry)
	dirty = false
	_refresh()
	status.text = "%d shots loaded. Select one to edit." % shots.size()

func _clock(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

func _sum_duration() -> float:
	var total := 0.0
	for shot in shots:
		total += float(shot.get("duration", 5.0))
	return total

func _update_total() -> void:
	var total := _sum_duration()
	var diff := total - float(TARGETS[loaded_chapter])
	total_label.text = "%d shots | %.2fs / %.2fs" % [shots.size(), total, TARGETS[loaded_chapter]]
	if absf(diff) > 0.05:
		total_label.text += " (%+.2fs)" % diff

func _refresh() -> void:
	scene_list.clear()
	var cue := 0.0
	for i in shots.size():
		var shot: Dictionary = shots[i]
		var path := str(shot.get("image", ""))
		var name := path.get_file().get_basename().replace("_", " ")
		scene_list.add_item("%02d  %s  %s" % [i + 1, _clock(cue), name])
		scene_list.set_item_tooltip(i, "%s | %.2fs" % [path.get_file(), float(shot.get("duration", 5.0))])
		if ResourceLoader.exists(path, "Texture2D"):
			scene_list.set_item_icon(i, load(path) as Texture2D)
		cue += float(shot.get("duration", 5.0))
	_update_total()
	if selected >= 0 and selected < shots.size():
		scene_list.select(selected)
		_select_shot(selected)
	else:
		preview.texture = null
		duration.editable = false
		dissolve.editable = false

func _select_shot(index: int) -> void:
	selected = index
	var shot: Dictionary = shots[index]
	var path := str(shot.get("image", ""))
	preview.texture = load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	duration.editable = true
	dissolve.editable = true
	duration.set_value_no_signal(float(shot.get("duration", 5.0)))
	dissolve.set_value_no_signal(float(shot.get("dissolve", 1.5)))
	status.text = ("Unsaved | " if dirty else "") + path.get_file()

func _duration_changed(value: float) -> void:
	if selected < 0 or selected >= shots.size():
		return
	shots[selected]["duration"] = value
	dirty = true
	var cue := 0.0
	for i in shots.size():
		var name := str(shots[i]["image"]).get_file().get_basename().replace("_", " ")
		scene_list.set_item_text(i, "%02d  %s  %s" % [i + 1, _clock(cue), name])
		scene_list.set_item_tooltip(i, "%s | %.2fs" % [str(shots[i]["image"]).get_file(), float(shots[i]["duration"])])
		cue += float(shots[i]["duration"])
	_update_total()
	status.text = "Unsaved duration change"

func _dissolve_changed(value: float) -> void:
	if selected >= 0 and selected < shots.size():
		shots[selected]["dissolve"] = value
		dirty = true
		status.text = "Unsaved dissolve change"

func _action(label: String) -> void:
	match label:
		"Save":
			_save()
		"Reload":
			_load_chapter(loaded_chapter)
		"Fit to Music":
			_fit()
		_:
			if selected < 0:
				return
			var target := selected + (-1 if label == "Move Up" else 1)
			if target < 0 or target >= shots.size():
				return
			var entry: Variant = shots[selected]
			shots[selected] = shots[target]
			shots[target] = entry
			selected = target
			dirty = true
			_refresh()
			status.text = "Unsaved order change"

func _fit() -> void:
	var total := _sum_duration()
	if shots.is_empty() or total <= 0.0:
		return
	var target := float(TARGETS[loaded_chapter])
	var remaining := target - float(shots.size())
	var weight := total - float(shots.size())
	var running := 0.0
	for i in shots.size():
		var seconds := target / float(shots.size()) if weight <= 0.0 else 1.0 + remaining * (float(shots[i]["duration"]) - 1.0) / weight
		seconds = snappedf(seconds, 0.01)
		if i == shots.size() - 1:
			seconds = snappedf(target - running, 0.01)
		shots[i]["duration"] = seconds
		running += seconds
	dirty = true
	_refresh()
	status.text = "Timings fitted proportionally; press Save to apply."

func _save() -> void:
	var path: String = PATHS[loaded_chapter]
	if FileAccess.get_file_as_string(path) != original_text:
		status.text = "Sequence changed on disk. Reload before saving."
		return
	var original: Variant = JSON.parse_string(original_text)
	if not original is Dictionary or shots.is_empty():
		status.text = "Cannot save an empty or invalid sequence."
		return
	if absf(_sum_duration() - float(TARGETS[loaded_chapter])) > 0.05:
		status.text = "Timing does not match the soundtrack. Adjust durations or use Fit to Music."
		return
	var backup_path := path + ".storyboard_backup"
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path)) != OK:
		status.text = "Backup failed; no changes saved."
		return
	original["shots"] = shots
	var next_text := JSON.stringify(original, "\t") + "\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status.text = "Could not save sequence."
		return
	file.store_string(next_text)
	file.close()
	original_text = next_text
	dirty = false
	status.text = "Saved! Reopen the soundtrack preview to review."
