extends SceneTree

func _initialize() -> void:
    call_deferred("_verify")

func _verify() -> void:
    var source := SpriteFramesActorSource.from_playable("gerald") as SpriteFramesActorSource
    if source == null or not source.loaded_from_disk:
        push_error("GERALD_SOURCE_NOT_DISK_BACKED")
        quit(1)
        return

    var errors := source.validate_sheets()
    print("GERALD_VALIDATION_ERRORS=", errors.size())
    for error_text in errors:
        push_error(error_text)
    var ok := errors.is_empty()

    for direction in range(8):
        var idle_name := StringName("idle_%d" % direction)
        var idle_count := source.sprite_frames.get_frame_count(idle_name)
        var idle_unique := {}
        var idle_frames_ok := idle_count == 5
        for i in range(idle_count):
            var texture := source.sprite_frames.get_frame_texture(idle_name, i)
            if texture == null or texture.get_width() != 96 or texture.get_height() != 128:
                idle_frames_ok = false
            else:
                idle_unique[texture.get_instance_id()] = true
        idle_frames_ok = idle_frames_ok and idle_unique.size() == 5
        print("VERIFY ", idle_name, " frames=", idle_count, " unique=", idle_unique.size(), " valid=", idle_frames_ok)
        ok = ok and idle_frames_ok

        var walk_name := StringName("walk_%d" % direction)
        var walk_count := source.sprite_frames.get_frame_count(walk_name)
        var walk_unique := {}
        var walk_frames_ok := walk_count == 16
        for i in range(walk_count):
            var texture := source.sprite_frames.get_frame_texture(walk_name, i)
            if texture == null or texture.get_width() != 96 or texture.get_height() != 128 or not (texture is AtlasTexture):
                walk_frames_ok = false
                continue
            var atlas_texture := texture as AtlasTexture
            var expected_region := Rect2(float(i * 96), float(direction * 128), 96.0, 128.0)
            if atlas_texture.atlas == null or atlas_texture.atlas.resource_path != "res://assets/characters/gerald/walk_sheet.png" or atlas_texture.region != expected_region:
                walk_frames_ok = false
            walk_unique[texture.get_instance_id()] = true
        walk_frames_ok = walk_frames_ok and walk_unique.size() == 16
        print("VERIFY ", walk_name, " frames=", walk_count, " unique_atlas_regions=", walk_unique.size(), " valid=", walk_frames_ok)
        ok = ok and walk_frames_ok

    var packed := load("res://scenes/characters/actor_visual.tscn") as PackedScene
    if packed == null:
        push_error("GERALD_RUNTIME_TEST_SCENE_MISSING")
        quit(1)
        return
    var visual := packed.instantiate() as ActorVisual
    root.add_child(visual)
    await process_frame
    visual.setup({"skin": "#d5a28a", "primary": "#3b2635", "secondary": "#e6a12e", "hair": "#241b25", "accent": "#ff6a2e"}, ActorVisual.Kind.HUMAN, "gerald", "Human", "fire")
    var report := visual.configure_character("gerald")
    if not bool(report.get("registered", false)):
        push_error("GERALD_ACTOR_VISUAL_NOT_REGISTERED: " + str(report))
        quit(1)
        return

    for direction in range(8):
        visual.play(CharacterAnimator.State.IDLE, direction)
        visual.animator.tick(1.0 / CharacterAnimator.fps_for(CharacterAnimator.State.IDLE))
        visual._update_sprite_frame()
        var idle_texture: Texture2D = visual._sprite.texture if visual._sprite != null else null
        var idle_filename := idle_texture.resource_path.get_file() if idle_texture != null else ""
        var idle_runtime_ok := idle_filename.begins_with("idle_%d_" % direction) and visual._sprite.visible
        print("RUNTIME IDLE dir=", direction, " file=", idle_filename, " matches=", idle_runtime_ok)
        ok = ok and idle_runtime_ok

        visual.play(CharacterAnimator.State.WALK, direction)
        visual.animator.tick(1.0 / CharacterAnimator.fps_for(CharacterAnimator.State.WALK))
        visual._update_sprite_frame()
        var walk_texture: Texture2D = visual._sprite.texture if visual._sprite != null else null
        var walk_runtime_ok := false
        if walk_texture is AtlasTexture:
            var walk_atlas := walk_texture as AtlasTexture
            walk_runtime_ok = walk_atlas.atlas != null and walk_atlas.atlas.resource_path == "res://assets/characters/gerald/walk_sheet.png" and int(walk_atlas.region.position.y) == direction * 128 and int(walk_atlas.region.position.x) == 96 and visual._sprite.visible
        print("RUNTIME WALK dir=", direction, " atlas=", walk_texture is AtlasTexture, " matches=", walk_runtime_ok)
        ok = ok and walk_runtime_ok

    print("GERALD_COMPLETE_8WAY_MOVEMENT_PASS=", ok)
    visual.queue_free()
    await process_frame
    quit(0 if ok else 1)

