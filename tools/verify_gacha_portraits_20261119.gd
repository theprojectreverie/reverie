extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    await process_frame
    var db := root.get_node_or_null("ContentDB")
    if db == null:
        push_error("VERIFY_FAIL: ContentDB autoload missing")
        quit(1)
        return
    var ids := ["kael","lilith","gerald","ravienna","crimson_witch","nyx","cassien","mirene","caelith"]
    var failures: Array[String] = []
    for cid in ids:
        var def: CharacterDef = db.get_character(cid)
        if def == null:
            failures.append("missing definition: " + cid)
            continue
        var view := PortraitView.new()
        view.setup_character(def)
        if view.portrait_texture == null:
            failures.append("portrait not loaded by PortraitView: " + cid)
        else:
            print("PORTRAIT_OK ", cid, " ", view.portrait_texture.get_width(), "x", view.portrait_texture.get_height())
        view.free()
    if db.banners.size() != 2:
        failures.append("expected 2 active banners, got " + str(db.banners.size()))
    var allowed := ["kael","lilith","gerald","ravienna","crimson_witch","nyx","cassien","mirene","caelith"]
    for bid in ["crimson_covenant","scarlet_requiem"]:
        var banner: Dictionary = db.get_banner(bid)
        if banner.is_empty():
            failures.append("missing banner: " + bid)
            continue
        for rarity in banner.get("pool",{}).keys():
            for cid in banner["pool"][rarity]:
                var character_id := str(cid)
                var character_def: CharacterDef = db.get_character(character_id)
                var belongs_to_live_roster := allowed.has(character_id)
                for base_id in allowed:
                    if character_id.begins_with(base_id + "_"):
                        belongs_to_live_roster = true
                        break
                if not belongs_to_live_roster:
                    failures.append("retired character remains in active pool " + bid + ": " + character_id)
                elif character_def == null:
                    failures.append("banner pool definition missing " + bid + ": " + character_id)
                elif character_def.rarity != str(rarity):
                    failures.append("banner pool rarity mismatch " + bid + ": " + character_id)
    if failures.is_empty():
        print("GACHA_PORTRAIT_VERIFY_OK: 9/9 base portraits loaded; all pool variants belong to the live nine; 2 banners.")
        quit(0)
    else:
        for message in failures:
            push_error("VERIFY_FAIL: " + message)
        quit(1)
