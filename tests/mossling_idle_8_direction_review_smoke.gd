extends SceneTree

const SCENE_PATH := "res://assets/enemies/mossling/idle_pass_02/mossling_idle_all_directions_review.tscn"
const EXPECTED := ["idle_0", "idle_1", "idle_2", "idle_3", "idle_4", "idle_5", "idle_6", "idle_7"]
const DIRECTIONS := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]

func _initialize() -> void:
    var packed := load(SCENE_PATH) as PackedScene
    if packed == null:
        push_error("Could not load eight-direction idle review scene")
        quit(1)
        return
    var stage := packed.instantiate()
    root.add_child(stage)
    for i in range(8):
        var sprite := stage.get_node_or_null(NodePath(DIRECTIONS[i] + "/AnimatedSprite2D")) as AnimatedSprite2D
        var label := stage.get_node_or_null(NodePath(DIRECTIONS[i] + "/DirectionLabel")) as Label
        if sprite == null or label == null:
            push_error("Missing idle sprite or label: " + DIRECTIONS[i])
            quit(1)
            return
        if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(EXPECTED[i]):
            push_error("Missing idle SpriteFrames animation: " + EXPECTED[i])
            quit(1)
            return
        if sprite.sprite_frames.get_frame_count(EXPECTED[i]) != 4:
            push_error("Idle preview frame count changed: " + EXPECTED[i])
            quit(1)
            return
        if not sprite.sprite_frames.get_animation_loop(EXPECTED[i]):
            push_error("Idle animation must loop: " + EXPECTED[i])
            quit(1)
            return
        if not is_equal_approx(sprite.sprite_frames.get_animation_speed(EXPECTED[i]), 9.0):
            push_error("Idle preview FPS mismatch: " + EXPECTED[i])
            quit(1)
            return
    print("PASS: eight-direction idle review stage loads all eight labelled AnimatedSprite2D nodes; 4 preview frames each, looping at 9 FPS.")
    stage.queue_free()
    quit(0)
