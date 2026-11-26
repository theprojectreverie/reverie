extends Node2D
func _ready() -> void:
	var player := preload("res://scenes/characters/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	var visual: ActorVisual = player.visual
	var fx := visual.get_node("KaelCombatEffects")
	var ok: bool = visual.character_id == "kael" and visual._sprite_active
	for state in [ActorVisual.S_CAST, ActorVisual.S_ATTACK, ActorVisual.S_INTERACT, ActorVisual.S_IDLE]:
		fx._play_state(state)
		await get_tree().process_frame
		for key in ["SlashTrail", "ImpactRing", "CastRing", "EruptionCenter", "AuraHalo"]:
			var shape: CanvasItem = fx.get_node(key)
			ok = ok and is_zero_approx(shape.self_modulate.a)
	print("KAEL_GEOMETRIC_OVERLAY_TEST=", ok)
	get_tree().quit(0 if ok else 1)
