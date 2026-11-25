from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scripts/world/six_zone_reverie/standalone_zone_controller.gd'
t=f.read_text(encoding='utf-8-sig')
shutil.copy2(f,str(f)+'.before_elathra_interaction_fix')
start=t.index('func _open_local_npc_dialogue')
end=t.index('func _process',start)
t=t[:start]+'''func _open_local_npc_dialogue(id: String) -> void:
    if id != "elathra":
        return
    var dialogue = get_node_or_null("NPCDialogueLayer/Dialogue")
    if dialogue == null or dialogue.visible:
        return
    dialogue.open(id)
    if dialogue.visible and is_instance_valid(checkpoint_player):
        checkpoint_player.set("input_enabled", false)

func _on_local_dialogue_finished(_id: String) -> void:
    if is_instance_valid(checkpoint_player):
        checkpoint_player.set("input_enabled", true)

func _input(event: InputEvent) -> void:
    var dialogue = get_node_or_null("NPCDialogueLayer/Dialogue")
    if dialogue == null or dialogue.visible or not is_instance_valid(checkpoint_player):
        return
    var npc := get_node_or_null("Zone/RoyalGardenV3Decorations/Elathra") as Interactable
    if npc == null or not npc.can_interact():
        return
    if checkpoint_player.global_position.distance_to(npc.global_position) > npc.interaction_radius:
        return
    var pressed := event.is_action_pressed("interact") and not event.is_echo()
    if event is InputEventKey and event.pressed and not event.echo:
        pressed = pressed or event.physical_keycode == KEY_E or event.keycode == KEY_E
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var local := npc.to_local(npc.get_global_mouse_position())
        pressed = pressed or Rect2(-64, -128, 128, 128).has_point(local)
    if pressed:
        npc.interact()
        get_viewport().set_input_as_handled()

'''+t[end:]
t=t.replace('EventBus.dialogue_requested.connect(_open_local_npc_dialogue)','EventBus.dialogue_requested.connect(_open_local_npc_dialogue)\n        EventBus.dialogue_finished.connect(_on_local_dialogue_finished)')
f.write_text(t,encoding='utf-8')
g=p/'scripts/world/six_zone_reverie/elathra.gd'
t=g.read_text(encoding='utf-8-sig')
shutil.copy2(g,str(g)+'.before_interaction_fix')
t=t.replace('interaction_radius = 110.0','interaction_radius = 140.0')
t=t.replace('var talking := false','var talking := false\n@onready var talk_prompt: Label = $TalkPrompt')
t=t.replace('if talking:\n\t\treturn\n\tvar player :=','var player :=',1)
t=t.replace('if player != null and global_position.distance_to(player.global_position) < 36.0:', 'talk_prompt.visible = not talking and player != null and global_position.distance_to(player.global_position) <= interaction_radius\n\tif talking:\n\t\treturn\n\tif player != null and global_position.distance_to(player.global_position) < 36.0:')
g.write_text(t,encoding='utf-8')
s=p/'scenes/world/six_zone_reverie/elathra.tscn'
t=s.read_text(encoding='utf-8-sig')
if 'name="TalkPrompt"' not in t:
 shutil.copy2(s,str(s)+'.before_interaction_fix')
 t+='\n[node name="TalkPrompt" type="Label" parent="."]\nvisible = false\noffset_left = -100.0\noffset_top = -170.0\noffset_right = 100.0\noffset_bottom = -145.0\nmouse_filter = 2\ntheme_override_colors/font_color = Color(1, 0.9, 0.68, 1)\ntheme_override_colors/font_outline_color = Color(0.05, 0.04, 0.1, 1)\ntheme_override_constants/outline_size = 6\ntheme_override_font_sizes/font_size = 24\ntext = "E - Talk"\nhorizontal_alignment = 1\n'
 s.write_text(t,encoding='utf-8')
print('Direct interaction, click, prompt and dialogue movement lock installed.')
