extends SceneTree

func _initialize() -> void:
    call_deferred("_verify")

func _verify() -> void:
    var source := SpriteFramesActorSource.from_playable("gerald") as SpriteFramesActorSource
    if source == null or not source.loaded_from_disk or not source.has_frames():
        push_error("GERALD_VERIFY_SOURCE_NOT_DISK_BACKED")
        quit(1)
        return
    var errors := source.validate_sheets()
    print("GERALD_SOURCE_LOADED=true")
    print("GERALD_VALIDATION_ERRORS=", errors.size())
    for error_text in errors:
        push_error(error_text)
    var ok := errors.is_empty()
    for direction in range(8):
        var animation := StringName("walk_%d" % direction)
        var count := source.sprite_frames.get_frame_count(animation)
        var valid := count == 16
        for i in range(count):
            var texture := source.sprite_frames.get_frame_texture(animation, i)
            if texture == null or not (texture is AtlasTexture) or texture.get_width() != 96 or texture.get_height() != 128:
                valid = false
                continue
            var atlas_texture := texture as AtlasTexture
            var expected_region := Rect2(float(i * 96), float(direction * 128), 96.0, 128.0)
            if atlas_texture.atlas == null or atlas_texture.atlas.resource_path != "res://assets/characters/gerald/walk_sheet.png" or atlas_texture.region != expected_region:
                valid = false
        print("GERALD_WALK_%d_COUNT=%d ATLAS_ROW=%d VALID=%s" % [direction, count, direction, valid])
        ok = ok and valid
    print("GERALD_DIAGONAL_WALKS_PRESERVED=", ok)
    quit(0 if ok else 1)

