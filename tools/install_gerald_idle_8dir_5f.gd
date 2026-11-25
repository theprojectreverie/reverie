extends SceneTree

const RESOURCE_PATH := "res://assets/characters/gerald/world_sheet.tres"
const BACKUP_PATH := "res://assets/characters/gerald/world_sheet.tres.pre_idle_8dir_5f_20261118.bak"
const ROOT := "res://assets/characters/gerald/generated/gerald_idle_8dir_5f_96x128/"

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

    var sprite_frames := load(RESOURCE_PATH) as SpriteFrames
    if sprite_frames == null:
        push_error("WORLD_SHEET_LOAD_FAILED")
        quit(1)
        return

    for direction in range(8):
        var animation := StringName("idle_%d" % direction)
        if not sprite_frames.has_animation(animation):
            push_error("MISSING_IDLE_ANIMATION: " + str(animation))
            quit(1)
            return
        var textures: Array[Texture2D] = []
        # Five unique hand-authored poses match the shared idle contract.
        for frame_number in range(1, 6):
            var frame_path := ROOT + "idle_%d/idle_%d_%02d.png" % [direction, direction, frame_number]
            if not FileAccess.file_exists(ProjectSettings.globalize_path(frame_path)):
                push_error("MISSING_IDLE_FRAME: " + frame_path)
                quit(1)
                return
            var texture := load(frame_path) as Texture2D
            if texture == null or texture.get_width() != 96 or texture.get_height() != 128:
                push_error("INVALID_IDLE_TEXTURE: " + frame_path)
                quit(1)
                return
            textures.append(texture)
        sprite_frames.clear(animation)
        for texture in textures:
            sprite_frames.add_frame(animation, texture)
        sprite_frames.set_animation_speed(animation, CharacterAnimator.fps_for(CharacterAnimator.State.IDLE))
        sprite_frames.set_animation_loop(animation, true)
        print("INSTALLED ", animation, " frames=", sprite_frames.get_frame_count(animation), " unique_source_poses=5 fps=", CharacterAnimator.fps_for(CharacterAnimator.State.IDLE))

    var save_error := ResourceSaver.save(sprite_frames, RESOURCE_PATH)
    if save_error != OK:
        push_error("WORLD_SHEET_SAVE_FAILED: %s" % error_string(save_error))
        quit(1)
        return
    print("GERALD_8WAY_IDLE_INSTALL=PASS")
    print("BACKUP=", BACKUP_PATH)
    quit(0)

