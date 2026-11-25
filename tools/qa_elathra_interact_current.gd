extends SceneTree
func _initialize():
    call_deferred("run")
func run():
    change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
    for i in range(20): await physics_frame
    var player = get_first_node_in_group("player")
    var npc = current_scene.get_node("Zone/RoyalGardenV3Decorations/Elathra")
    print("NPC SCALE ", npc.global_scale, " PLAYER SCALE ", player.global_scale)
    player.global_position = npc.global_position + Vector2(40,0)
    for i in range(10): await physics_frame
    var action = InputEventAction.new()
    action.action = &"interact"
    action.pressed = true
    Input.parse_input_event(action)
    for i in range(10): await process_frame
    var box = current_scene.get_node("NPCDialogueLayer/Dialogue")
    print("DIALOGUE VISIBLE ", box.visible, " PROMPT ", player.current_prompt())
    quit(0 if box.visible else 1)