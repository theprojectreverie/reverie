extends SceneTree

func _initialize() -> void:
    var script := load("res://tools/import_mossling_spriteframes.gd") as Script
    if script == null:
        push_error("Mossling importer script failed to load or parse")
        quit(1)
        return
    if script.get_instance_base_type() != "EditorScript":
        push_error("Mossling importer must remain an EditorScript")
        quit(1)
        return
    print("PASS: Mossling production importer parses and remains an EditorScript.")
    quit(0)
