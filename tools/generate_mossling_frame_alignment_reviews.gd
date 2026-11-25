extends SceneTree

const DIRECTIONS := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
const SPECS := [
    {"name":"idle", "source":"res://assets/enemies/mossling/idle_pass_02/mossling_idle_preview.tres", "frames":4, "fps":9, "output":"res://assets/enemies/mossling/idle_pass_02/mossling_idle_frame_alignment_review.tscn"},
    {"name":"walk", "source":"res://assets/enemies/mossling/walk_pass_04/mossling_walk_preview.tres", "frames":6, "fps":12, "output":"res://assets/enemies/mossling/walk_pass_04/mossling_walk_frame_alignment_review.tscn"}
]

func _initialize() -> void:
    for spec in SPECS:
        if not _build(spec):
            quit(1)
            return
    print("PASS: generated two frame-by-frame alignment review scenes from existing SpriteFrames; source artwork unchanged.")
    quit(0)

func _build(spec: Dictionary) -> bool:
    var frames := load(spec.source) as SpriteFrames
    if frames == null:
        push_error("Cannot load preview SpriteFrames: " + spec.source)
        return false
    var root_node := Node2D.new()
    root_node.name = spec.name.capitalize() + "FrameAlignmentReview"
    var camera := Camera2D.new()
    camera.name = "ReviewCamera"
    camera.position = Vector2(400, 700)
    camera.zoom = Vector2(0.62, 0.62)
    camera.enabled = true
    camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
    root_node.add_child(camera)
    camera.owner = root_node
    var label := Label.new()
    label.name = "ReviewTitle"
    label.text = "Mossling " + spec.name + " — frame alignment review (96×128 cells)"
    label.position = Vector2(24, 12)
    root_node.add_child(label)
    label.owner = root_node
    for direction_index in range(8):
        var anim: String = str(spec["name"]) + "_" + str(direction_index)
        if not frames.has_animation(anim) or frames.get_frame_count(anim) != spec.frames:
            push_error("Animation contract mismatch: " + anim)
            return false
        var row_y := 72.0 + direction_index * 168.0
        var direction_label := Label.new()
        direction_label.name = "Direction_" + str(direction_index)
        direction_label.text = str(direction_index) + "  " + DIRECTIONS[direction_index]
        direction_label.position = Vector2(24, row_y - 28)
        root_node.add_child(direction_label)
        direction_label.owner = root_node
        var baseline := Line2D.new()
        baseline.name = "GroundBaseline_" + str(direction_index)
        baseline.points = PackedVector2Array([Vector2(24, row_y + 64), Vector2(24 + spec.frames * 112, row_y + 64)])
        baseline.width = 1.0
        baseline.default_color = Color(0.35, 0.8, 0.45, 0.9)
        root_node.add_child(baseline)
        baseline.owner = root_node
        for frame_index in range(spec.frames):
            var cell := Node2D.new()
            cell.name = "Cell_" + str(direction_index) + "_" + str(frame_index)
            cell.position = Vector2(24 + frame_index * 112 + 48, row_y)
            root_node.add_child(cell)
            cell.owner = root_node
            var canvas_guide := ReferenceRect.new()
            canvas_guide.name = "Canvas96x128"
            canvas_guide.position = Vector2(-48, -64)
            canvas_guide.size = Vector2(96, 128)
            canvas_guide.border_color = Color(0.45, 0.65, 0.9, 0.55)
            canvas_guide.border_width = 1.0
            canvas_guide.editor_only = false
            cell.add_child(canvas_guide)
            canvas_guide.owner = root_node
            var sprite := Sprite2D.new()
            sprite.name = "Artwork"
            sprite.texture = frames.get_frame_texture(anim, frame_index)
            sprite.centered = true
            sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
            cell.add_child(sprite)
            sprite.owner = root_node
            var frame_label := Label.new()
            frame_label.name = "FrameNumber"
            frame_label.text = "F" + str(frame_index + 1)
            frame_label.position = Vector2(-44, 68)
            cell.add_child(frame_label)
            frame_label.owner = root_node
    var packed := PackedScene.new()
    var result := packed.pack(root_node)
    if result != OK:
        push_error("Could not pack review scene: " + str(result))
        return false
    result = ResourceSaver.save(packed, spec.output)
    if result != OK:
        push_error("Could not save review scene: " + spec.output)
        return false
    print("Created " + spec.output)
    return true
