extends SceneTree

const SCENE_PATH := "res://assets/enemies/mossling/walk_pass_04/mossling_walk_all_directions_review.tscn"
const EXPECTED := ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "walk_6", "walk_7"]

func _initialize() -> void:
    var packed := load(SCENE_PATH) as PackedScene
    if packed == null:
        push_error("Could not load eight-direction review scene")
        quit(1)
        return
    var stage := packed.instantiate()
    root.add_child(stage)
    var found := 0
    for direction_index in range(8):
        var direction_name: String = ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"][direction_index]
        var sprite := stage.get_node_or_null(NodePath(direction_name + "/AnimatedSprite2D")) as AnimatedSprite2D
        var label := stage.get_node_or_null(NodePath(direction_name + "/DirectionLabel")) as Label
        if sprite == null or label == null:
            push_error("Missing sprite or direction label for " + direction_name)
            quit(1)
            return
        if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(EXPECTED[direction_index]):
            push_error("Missing SpriteFrames animation for " + direction_name)
            quit(1)
            return
        if sprite.sprite_frames.get_frame_count(EXPECTED[direction_index]) != 6:
            push_error("Unexpected frame count for " + direction_name)
            quit(1)
            return
        if not sprite.sprite_frames.get_animation_loop(EXPECTED[direction_index]):
            push_error("Walk animation must loop for " + direction_name)
            quit(1)
            return
        if not is_equal_approx(sprite.sprite_frames.get_animation_speed(EXPECTED[direction_index]), 12.0):
            push_error("Unexpected FPS for " + direction_name)
            quit(1)
            return
        found += 1
    print("PASS: eight-direction review stage instantiates all eight labelled AnimatedSprite2D nodes; 6 frames each, looping at 12 FPS.")
    stage.queue_free()
    quit(0)
