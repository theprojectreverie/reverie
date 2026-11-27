extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func unit(id: String, team: int = 0) -> Combatant:
	var u := Combatant.new()
	u.uid = id
	u.def_id = id
	u.display_name = id
	u.team = team
	u.ascension = 3
	u.hp = 1000
	u.max_hp = 1000
	u.atk = 100
	u.defense = 100
	u.speed = 100
	return u
func run() -> void:
	var g := unit("gerald_mythic")
	var l := unit("lilith_mythic")
	var c := unit("cassien_mythic")
	var r := unit("ravienna_mythic")
	var e := unit("enemy",1)
	e.hp = 5000
	e.max_hp = 5000
	var b = load("res://scripts/combat/combat_engine.gd").new()
	b.setup([g,l,c,r],[e])
	b.start()
	b.current_actor_index = g.combat_index
	assert(b.execute(g.combat_index,"beyond_death").is_empty())
	l.ascension = 2
	assert(b.bond_for(g).is_empty())
	l.ascension = 3
	for i in range(4): b._charge_bond(g if i%2==0 else l)
	assert(b.bond_ready(g,"beyond_death"))
	for ally in [g,l,c,r]: ally.hp = 400
	var events = b.execute(g.combat_index,"beyond_death")
	assert(events[0].type == "bond")
	for ally in [g,l,c,r]:
		assert(ally.hp == 900 and ally.shield == 300)
	assert(b.bond_uses["beyond_death"] == 1 and b.bond_gauges["beyond_death"] == 0)
	# Direct damage splits before shields; one fatal hit per sibling.
	g.shield = 0
	l.shield = 0
	l.take_damage(100)
	assert(g.hp == 865 and l.hp == 835)
	l.take_damage(5000)
	assert(l.hp == 1 and g.hp == 1)
	l.take_damage(100)
	assert(not l.is_alive())
	assert(b.bond_for(g).is_empty())
	b.current_actor_index = c.combat_index
	for i in range(4): b._charge_bond(c if i%2==0 else r)
	c.apply_status("poison",3,0.1)
	c.apply_status("atk_up",3,0.2)
	r.apply_status("blind",3,1.0)
	c.hp = 400
	r.hp = 400
	events = b.execute(c.combat_index,"eternal_eclipse")
	assert(events[0].type == "bond")
	assert(e.hp < 5000 and e.has_status("def_down") and e.has_status("eclipse_curse"))
	assert(not c.has_status("poison") and c.has_status("atk_up") and not r.has_status("blind"))
	assert(c.hp > 400 and r.hp > 400)
	assert(b.bond_gauges["eternal_eclipse"] == 0)
	b.current_actor_index = c.combat_index
	b.bond_gauges["eternal_eclipse"] = 100
	assert(not b.execute(c.combat_index,"eternal_eclipse").is_empty())
	b.current_actor_index = c.combat_index
	b.bond_gauges["eternal_eclipse"] = 100
	assert(b.execute(c.combat_index,"eternal_eclipse").is_empty())
	assert(b.bond_uses["eternal_eclipse"] == 2)
	print("BOND SKILLS: eligibility, charge, heal, shield, redirect, lethal protection, AoE, cleanse, lifesteal, use cap PASS")
	quit(0)


