extends Control

const DIRECTIONS := ["DOWN", "DOWN-RIGHT", "RIGHT", "UP-RIGHT", "UP", "UP-LEFT", "LEFT", "DOWN-LEFT"]
const CELL_SIZE := Vector2(36, 48)

func _ready() -> void:
    DisplayServer.window_set_title("Reverie - Gerald SpriteFrames Visual QA")
    DisplayServer.window_set_size(Vector2i(1680, 900))
    var background := ColorRect.new()
    background.color = Color("#171923")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)

    var scroll := ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    scroll.offset_left = 24
    scroll.offset_top = 18
    scroll.offset_right = -24
    scroll.offset_bottom = -18
    add_child(scroll)

    var content := VBoxContainer.new()
    content.custom_minimum_size = Vector2(1580, 0)
    content.add_theme_constant_override("separation", 2)
    scroll.add_child(content)

    var title := Label.new()
    title.text = "GERALD — 8-WAY IDLE + WALK / ACTIVE SPRITEFRAMES"
    title.add_theme_font_size_override("font_size", 25)
    title.add_theme_color_override("font_color", Color("#f2dfc6"))
    content.add_child(title)

    var note := Label.new()
    note.text = "Each row is one game direction. First 5 cells = idle poses; next 16 cells = walking cycle."
    note.add_theme_font_size_override("font_size", 14)
    note.add_theme_color_override("font_color", Color("#aeb3c1"))
    content.add_child(note)

    var sheet := load("res://assets/characters/gerald/world_sheet.tres") as SpriteFrames
    if sheet == null:
        push_error("GERALD_SPRITEFRAMES_MISSING")
        return

    for direction in range(8):
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 3)
        var label := Label.new()
        label.text = DIRECTIONS[direction]
        label.custom_minimum_size = Vector2(112, 28)
        label.add_theme_font_size_override("font_size", 12)
        label.add_theme_color_override("font_color", Color("#d7ad73"))
        row.add_child(label)
        for state in ["idle", "walk"]:
            var animation := StringName("%s_%d" % [state, direction])
            var count := sheet.get_frame_count(animation)
            for frame_index in range(count):
                var texture := sheet.get_frame_texture(animation, frame_index)
                var view := TextureRect.new()
                view.custom_minimum_size = CELL_SIZE
                view.texture = texture
                view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
                row.add_child(view)
        content.add_child(row)

    print("GERALD_SPRITEFRAMES_VISUAL_QA_READY directions=8 idle_frames=40 walk_frames=128")

