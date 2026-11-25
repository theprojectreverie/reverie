extends SceneTree

const SCENES := [
    {"path":"res://assets/enemies/mossling/idle_pass_02/mossling_idle_frame_alignment_review.tscn", "frames":4, "state":"idle"},
    {"path":"res://assets/enemies/mossling/walk_pass_04/mossling_walk_frame_alignment_review.tscn", "frames":6, "state":"walk"}
]
const DIRECTIONS := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    for spec in SCENES:
        var packed := load(spec.path) as PackedScene
        if packed == null:
            push_error("Review scene failed to load: " + spec.path)
            quit(1)
            return
        var stage := packed.instantiate()
        root.add_child(stage)
        var expected_nodes: int = 2 + 8 + 8 + 8 * int(spec["frames"])
        if stage.get_child_count() != expected_nodes:
            push_error("Unexpected review node count for " + spec.state + ": " + str(stage.get_child_count()))
            quit(1)
            return
        for direction_index in range(8):
            var row := stage.get_node_or_null("Direction_" + str(direction_index))
            var baseline := stage.get_node_or_null("GroundBaseline_" + str(direction_index)) as Line2D
            if row == null or baseline == null:
                push_error("Missing row label or baseline for " + spec.state + " direction " + str(direction_index))
                quit(1)
                return
            for frame_index in range(spec.frames):
                var cell := stage.get_node_or_null("Cell_" + str(direction_index) + "_" + str(frame_index))
                var sprite := cell.get_node_or_null("Artwork") as Sprite2D if cell != null else null
                if sprite == null or sprite.texture == null:
                    push_error("Missing frame sprite for " + spec.state + " direction " + str(direction_index) + " frame " + str(frame_index))
                    quit(1)
                    return
                var guide := cell.get_node_or_null("Canvas96x128") as ReferenceRect
                if guide == null or guide.size != Vector2(96, 128):
                    push_error("Missing 96x128 canvas guide")
                    quit(1)
                    return
                if sprite.texture.get_size() != Vector2(96, 128):
                    push_error("Unexpected canvas size in review scene")
                    quit(1)
                    return
        stage.queue_free()
        await process_frame
        print("PASS: " + spec.state + " review scene — 8 directions, " + str(spec.frames) + " frame cells per direction, 96×128 textures and baseline guides.")
    quit(0)
