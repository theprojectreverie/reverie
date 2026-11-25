@tool
extends EditorPlugin

var dock: VBoxContainer
var chapter: OptionButton
var shots: Array = []
var selected := -1
var scene_list: ItemList
var preview: TextureRect
var duration: SpinBox
var status: Label

const PATHS := [
    "res://assets/cinematics/gerald_story/before_the_fall_sequence.json",
    "res://assets/cinematics/gerald_boss/gerald_boss_sequence.json"
]

func _enter_tree() -> void:
    dock = VBoxContainer.new()
    dock.name = "Gerald Storyboard"
    dock.custom_minimum_size = Vector2(320, 380)
    var heading := Label.new()
    heading.text = "GERALD STORYBOARD"
    dock.add_child(heading)
    chapter = OptionButton.new()
    chapter.add_item("Before the Fall")
    chapter.add_item("The Fallen Guardian")
    chapter.item_selected.connect(_load_chapter)
    dock.add_child(chapter)
    scene_list = ItemList.new()
    scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scene_list.custom_minimum_size.y = 170
    scene_list.select_mode = ItemList.SELECT_SINGLE
    scene_list.item_selected.connect(_select_shot)
    dock.add_child(scene_list)
    preview = TextureRect.new()
    preview.custom_minimum_size = Vector2(300, 160)
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    dock.add_child(preview)
    var buttons := HBoxContainer.new()
    for label in ["Move Up", "Move Down", "Save"]:
        var b := Button.new()
        b.text = label
        b.pressed.connect(_action.bind(label))
        buttons.add_child(b)
    dock.add_child(buttons)
    var timing := HBoxContainer.new()
    var time_label := Label.new()
    time_label.text = "Seconds:"
    timing.add_child(time_label)
    duration = SpinBox.new()
    duration.min_value = 1.0
    duration.max_value = 30.0
    duration.step = 0.5
    duration.value_changed.connect(_duration_changed)
    timing.add_child(duration)
    dock.add_child(timing)
    status = Label.new()
    status.text = "Select a shot to preview."
    dock.add_child(status)
    add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
    _load_chapter(0)

func _exit_tree() -> void:
    remove_control_from_docks(dock)
    dock.queue_free()

func _load_chapter(index: int) -> void:
    selected = -1
    shots.clear()
    var path: String = PATHS[index]
    if FileAccess.file_exists(path):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if parsed is Dictionary:
            for entry in parsed.get("shots", []):
                if entry is Dictionary:
                    shots.append(entry)
    _refresh()
    status.text = str(shots.size()) + " shots loaded"

func _refresh() -> void:
    scene_list.clear()
    for i in shots.size():
        var path: String = str(shots[i].get("image", ""))
        scene_list.add_item(str(i + 1) + ". " + path.get_file().trim_prefix("0"))
        if ResourceLoader.exists(path):
            var texture := load(path) as Texture2D
            if texture:
                scene_list.set_item_icon(i, texture)
                scene_list.set_item_icon_region(i, Rect2())
    if selected >= 0 and selected < shots.size():
        scene_list.select(selected)
        _select_shot(selected)
    else:
        preview.texture = null

func _select_shot(index: int) -> void:
    selected = index
    var path: String = str(shots[index].get("image", ""))
    preview.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
    duration.set_value_no_signal(float(shots[index].get("duration", 5.0)))
    status.text = path.get_file()

func _duration_changed(value: float) -> void:
    if selected >= 0 and selected < shots.size():
        shots[selected]["duration"] = value
        status.text = "Unsaved duration change"

func _action(label: String) -> void:
    if label == "Save":
        _save()
        return
    if selected < 0:
        return
    var target := selected + (-1 if label == "Move Up" else 1)
    if target < 0 or target >= shots.size():
        return
    var temp: Variant = shots[selected]
    shots[selected] = shots[target]
    shots[target] = temp
    selected = target
    _refresh()
    status.text = "Unsaved order change"

func _save() -> void:
    var path: String = PATHS[chapter.selected]
    var original: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not original is Dictionary:
        status.text = "Cannot read sequence file"
        return
    var backup_path := path + ".storyboard_backup"
    if FileAccess.file_exists(path):
        DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        status.text = "Could not save sequence"
        return
    original["shots"] = shots
    file.store_string(JSON.stringify(original, "\t") + "\n")
    file.close()
    status.text = "Saved! Preview the scene with F6."
