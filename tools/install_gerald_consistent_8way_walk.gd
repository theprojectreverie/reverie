extends SceneTree

const RESOURCE_PATH := "res://assets/characters/gerald/world_sheet.tres"
const BACKUP_PATH := "res://assets/characters/gerald/world_sheet.tres.pre_consistent_8way_walk_20261118.bak"
const WALK_ATLAS_PATH := "res://assets/characters/gerald/walk_sheet.png"
const FRAME_WIDTH := 96
const FRAME_HEIGHT := 128
const FRAME_COUNT := 16

func _initialize() -> void:
    call_deferred("_install")

func _install() -> void:
    var absolute_resource := ProjectSettings.globalize_path(RESOURCE_PATH)
    var absolute_backup := ProjectSettings.globalize_path(BACKUP_PATH)
    if not FileAccess.file_exists(absolute_backup):
        var backup_error := DirAccess.copy_absolute(absolute_resource, absolute_backup)
        if backup_error != OK:
            push_error("BACKUP_FAILED: %s" % error_string(backup_error))
            quit(1)
            return

    var atlas := load(WALK_ATLAS_PATH) as Texture2D
    if atlas == null or atlas.get_width() != FRAME_WIDTH * FRAME_COUNT or atlas.get_height() != FRAME_HEIGHT * 8:
        push_error("INVALID_GERALD_WALK_ATLAS: expected 1536x1024")
        quit(1)
        return

    var sprite_frames := load(RESOURCE_PATH) as SpriteFrames
    if sprite_frames == null:
        push_error("WORLD_SHEET_LOAD_FAILED")
        quit(1)
        return

    for direction in range(8):
        var animation := StringName("walk_%d" % direction)
        if not sprite_frames.has_animation(animation):
            push_error("MISSING_WALK_ANIMATION: " + str(animation))
            quit(1)
            return
        sprite_frames.clear(animation)
        for frame_index in range(FRAME_COUNT):
            var frame := AtlasTexture.new()
            frame.atlas = atlas
            frame.region = Rect2(
                float(frame_index * FRAME_WIDTH),
                float(direction * FRAME_HEIGHT),
                float(FRAME_WIDTH),
                float(FRAME_HEIGHT)
            )
            if frame.get_width() != FRAME_WIDTH or frame.get_height() != FRAME_HEIGHT:
                push_error("INVALID_ATLAS_REGION: direction=%d frame=%d" % [direction, frame_index])
                quit(1)
                return
            sprite_frames.add_frame(animation, frame)
        sprite_frames.set_animation_speed(animation, 12.0)
        sprite_frames.set_animation_loop(animation, true)
        print("INSTALLED ", animation, " frames=", sprite_frames.get_frame_count(animation), " source=walk_sheet.png row=", direction)

    var save_error := ResourceSaver.save(sprite_frames, RESOURCE_PATH)
    if save_error != OK:
        push_error("WORLD_SHEET_SAVE_FAILED: %s" % error_string(save_error))
        quit(1)
        return
    print("GERALD_CONSISTENT_8WAY_WALK_INSTALL=PASS")
    print("BACKUP=", BACKUP_PATH)
    quit(0)

