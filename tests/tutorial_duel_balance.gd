extends Node
func _ready() -> void:
	var wins := 0
	var total_turns := 0
	var min_hp := 1000.0
	var max_turns := 0
	for seed in range(1, 101):
		var players := CombatFactory.player_units().filter(func(u): return u.def_id == "kael")
		assert(players.size() == 1)
		var engine := CombatEngine.new()
		engine.setup(players, CombatFactory.enemy_units("tutorial_fairy_spar"), seed)
		engine.start()
		var turns := 0
		while not engine.finished and turns < 60:
			var idx := engine.current_actor_index
			assert(idx >= 0)
			var choice := CombatAI.choose(engine, idx)
			if str(choice.skill_id).is_empty():
				engine.advance_turn()
			else:
				var events := engine.execute(idx, str(choice.skill_id), choice.targets)
				assert(not events.is_empty())
			turns += 1
		assert(engine.finished)
		if engine.winner_team == 0:
			wins += 1
			min_hp = minf(min_hp, players[0].hp)
		total_turns += turns
		max_turns = maxi(max_turns, turns)
	print("DUEL: wins=", wins, "/100 mean turns=", float(total_turns)/100, " max turns=", max_turns, " lowest winning HP=", min_hp)
	get_tree().quit(0 if wins >= 90 else 1)
