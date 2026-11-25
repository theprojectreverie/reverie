class_name CombatEventPresentationComponent
extends Node
## Converts deterministic combat events into battle presentation and timed hit reactions.

var screen: CombatScreen


func bind(owner_screen: CombatScreen) -> void:
	screen = owner_screen

func process_events(events: Array) -> void:
	if screen._resolved:
		return
	var pending_deaths: Array[BattlefieldActor] = []
	for event in events:
		var event_type := str(event.get("type", ""))
		match event_type:
			"defend":
				var defending_actor := screen._actor_for_uid(str(event.get("actor_uid", "")))
				screen._log("[color=#7fe3e0]%s takes a defensive stance. Incoming damage is halved until their next turn.[/color]" % str(event.get("actor_name", "Unit")))
				if defending_actor != null:
					screen._float_text(defending_actor, "DEFEND", UITheme.TEAL)
			"end_turn":
				screen._log("[color=#9aa8c2]%s ends their turn.[/color]" % str(event.get("actor_name", "Unit")))
			"round":
				screen._round_label.text = "Round %d" % int(event.get("round", 1))
				screen._log("[color=#9aa8c2]— Round %d —[/color]" % int(event.get("round", 1)))
			"turn":
				screen._log("[color=#e9eef9]%s's turn.[/color]" % str(event.get("actor_name", "Unit")))
			"action":
				var actor_name := str(event.get("actor_name", "Unit"))
				var skill_name := str(event.get("skill_name", "skill"))
				screen._log("[color=#7fe3e0]%s uses %s.[/color]" % [actor_name, skill_name])
				var actor: BattlefieldActor = screen._actor_for_uid(str(event.get("actor_uid", "")))
				var target_uids: Array = event.get("target_uids", [])
				var target_uid := str(target_uids[0]) if not target_uids.is_empty() else ""
				var target: BattlefieldActor = screen._actor_for_uid(target_uid) if not target_uid.is_empty() else null
				var should_present_attack := true
				if actor != null and actor.unit != null and actor.unit.is_boss:
					should_present_attack = await _show_boss_telegraphs(actor, target_uids)
					if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved:
						return
				if should_present_attack:
					animate_attack(actor, target, str(event.get("skill_id", "")), bool(event.get("ultimate", false)))
			"damage":
				handle_damage(event)
			"heal":
				var heal_actor: BattlefieldActor = screen._actor_for_uid(str(event.get("target_uid", "")))
				var heal_amount := int(event.get("amount", 0))
				if heal_amount > 0:
					AudioDirector.play_variant("healing")
					screen._log("[color=#8fe3a0]%s recovers %d HP.[/color]" % [str(event.get("target_name", "Unit")), heal_amount])
					screen._float_text(heal_actor, "+%d" % heal_amount, UITheme.GREEN)
			"shield":
				screen._log("[color=#7fe3e0]%s gains a %d shield.[/color]" % [str(event.get("target_name", "Unit")), int(event.get("amount", 0))])
			"status":
				screen._log("[color=#b78bff]%s: %s[/color]" % [str(event.get("target_name", "Unit")), str(event.get("status", "")).replace("_", " ").capitalize()])
			"status_tick":
				screen._log("[color=#ff9f9f]%s takes %d %s damage.[/color]" % [
					str(event.get("target_name", "Unit")), int(event.get("amount", 0)), str(event.get("status", ""))
				])
				var tick_actor: BattlefieldActor = screen._actor_for_uid(str(event.get("target_uid", "")))
				if tick_actor != null:
					tick_actor.take_hit()
					if screen._battlefield != null:
						screen._battlefield.spawn_hit_effect(tick_actor, null, UITheme.DANGER, 0.78)
					screen._float_text(tick_actor, "-%d" % int(event.get("amount", 0)), UITheme.DANGER)
			"miss":
				screen._log("[color=#9aa8c2]%s misses.[/color]" % str(event.get("target_name", "Unit")))
			"skip":
				screen._log("[color=#9aa8c2]%s loses the turn (%s).[/color]" % [
					str(event.get("actor_name", "Unit")), str(event.get("reason", "stunned"))
				])
			"death":
				AudioDirector.play_variant("defeat", -5.0)
				screen._log("[color=#ff7a8a]%s falls.[/color]" % str(event.get("target_name", "Unit")))
				var fallen: BattlefieldActor = screen._actor_for_uid(str(event.get("target_uid", "")))
				if fallen != null and fallen.unit != null and fallen.unit.is_boss and screen._boss_presentation_rig != null:
					if screen._boss_presentation_rig.has_method("clear_target_telegraphs"):
						screen._boss_presentation_rig.call("clear_target_telegraphs")
				if screen._cinematic_finish_delay > 0.0:
					if fallen != null:
						pending_deaths.append(fallen)
				elif screen._battlefield != null:
					screen._battlefield.play_death(fallen)
			"phase":
				var phase_message := str(event.get("message", "The boss changes."))
				var phase_uid := str(event.get("actor_uid", ""))
				var phase_boss: Combatant = screen.engine.get_by_uid(phase_uid) if screen.engine != null else null
				var phase_boss_id := str(event.get("boss_id", phase_boss.def_id if phase_boss != null else ""))
				var phase_boss_name := str(event.get("boss_name", phase_boss.display_name if phase_boss != null else ""))
				var phase_number := int(event.get("phase_number", 2))
				screen._log("[color=#ffc95e]%s[/color]" % phase_message)
				screen._camera_shake(10.0, 0.5)
				if phase_boss_id.is_empty():
					screen._show_banner(phase_message)
				else:
					await screen._show_boss_phase_transition(phase_boss_id, phase_number, phase_message, phase_boss_name)
				if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved:
					return
				if screen._battlefield != null and phase_boss_id == "fallen_matron":
					screen._battlefield.play_matron_phase(phase_number)
			"victory":
				await screen._wait_for_cinematic_impact()
				if not is_instance_valid(screen) or not screen.is_inside_tree():
					return
				screen._flush_pending_deaths(pending_deaths)
				screen._refresh_cards()
				if screen._battlefield != null:
					screen._battlefield.play_victory_animations()
				screen._finish_battle(true)
				return
			"defeat":
				await screen._wait_for_cinematic_impact()
				if not is_instance_valid(screen) or not screen.is_inside_tree():
					return
				screen._flush_pending_deaths(pending_deaths)
				screen._refresh_cards()
				screen._finish_battle(false)
				return
	# Keep the party HUD / turn progression in lockstep with the Matron's
	# telegraphed pillar impact before exposing the next actor.
	await screen._wait_for_cinematic_impact()
	if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved:
		return
	screen._flush_pending_deaths(pending_deaths)
	screen._refresh_cards()
	screen._update_turn_order()
	if screen._resolved:
		return
	var actor: Combatant = screen.engine.current_actor()
	if actor == null:
		return
	screen._refresh_skills()
	if actor.team == CombatEngine.ENEMY_TEAM:
		screen._schedule_enemy_turn()
	elif screen._auto:
		screen._schedule_auto_player()


func _show_boss_telegraphs(boss_actor: BattlefieldActor, target_uids: Array) -> bool:
	var rig: Node = screen._boss_presentation_rig
	if rig == null or not rig.has_method("show_target_telegraphs"):
		return true
	var interruption_at_start := boss_actor.interruption_serial
	var positions: Array = []
	for uid in target_uids:
		var target_actor: BattlefieldActor = screen._actor_for_uid(str(uid))
		if target_actor != null and is_instance_valid(target_actor) and target_actor.unit != null:
			if target_actor.unit.team != boss_actor.unit.team:
				positions.append(rig.to_local(target_actor.global_position))
	if positions.is_empty():
		return true
	rig.call("show_target_telegraphs", positions, boss_actor.unit.def_id, 0.42)
	await screen.get_tree().create_timer(0.42).timeout
	if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved:
		return false
	if not is_instance_valid(boss_actor) or boss_actor.dead or boss_actor.interruption_serial != interruption_at_start:
		if rig.has_method("clear_target_telegraphs"):
			rig.call("clear_target_telegraphs")
		return false
	return true


func handle_damage(event: Dictionary) -> void:
	var actor := screen._actor_for_uid(str(event.get("target_uid", "")))
	var amount := int(event.get("amount", 0))
	var absorbed := int(event.get("absorbed", 0))
	var crit := bool(event.get("crit", false))
	var advantage := str(event.get("advantage", "Neutral"))
	var suffix := ""
	if crit:
		suffix += " CRIT"
	if advantage == "Advantage":
		suffix += " WEAK"
	elif advantage == "Resisted":
		suffix += " RESIST"
	screen._log("[color=#ff9f9f]%s takes %d damage%s.[/color]" % [str(event.get("target_name", "Unit")), amount, suffix])
	if actor != null:
		var element := str(event.get("element", "neutral"))
		var color := UITheme.element_color(element)
		if color == UITheme.TEXT_DIM:
			color = UITheme.DANGER
		if crit:
			color = UITheme.GOLD_BRIGHT
		elif advantage == "Advantage":
			color = UITheme.GREEN
		elif advantage == "Resisted":
			color = UITheme.TEXT_DIM
		var elem_color := UITheme.element_color(element)
		if elem_color == UITheme.TEXT_DIM:
			elem_color = Color(1.4, 0.9, 0.9, 1.0)
		# The attack choreography reaches impact after its anticipation and
		# lunge. Delay the hit reaction to that exact point; status ticks keep
		# their separate immediate reaction path.
		var impact_delay := CombatScreen.IMPACT_DELAY
		var source: Combatant = screen.engine.get_by_uid(str(event.get("actor_uid", ""))) if screen.engine != null else null
		if source != null and source.def_id == "fallen_matron" and str(event.get("skill_id", "")) == "matron_verdict":
			# The generic boss warning has already occupied 0.42s of the
			# Matron's ~1.88s verdict choreography. Preserve the original total
			# impact beat instead of stacking a second full windup.
			impact_delay = 1.46
			screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, impact_delay)
		screen.get_tree().create_timer(impact_delay).timeout.connect(func() -> void:
			if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved or not is_instance_valid(actor):
				return
			if actor.unit != null and actor.unit.is_boss and screen._boss_presentation_rig != null and screen._boss_presentation_rig.has_method("clear_target_telegraphs"):
				screen._boss_presentation_rig.call("clear_target_telegraphs")
			if source != null and source.is_boss and screen._boss_presentation_rig != null:
				var rig: Node = screen._boss_presentation_rig
				if rig.has_method("play_impact"):
					rig.call("play_impact", rig.to_local(actor.global_position), source.def_id, 1.0 if crit else 0.82)
			if absorbed > 0:
				AudioDirector.play_variant("shield_block")
			if amount > 0:
				var impact_skill: SkillDef = ContentDB.get_skill(str(event.get("skill_id", "")))
				var impact_category := "critical_hit" if crit else ("magic_impact" if impact_skill != null and impact_skill.animation_key == "cast" else "sword_impact")
				if absorbed <= 0:
					AudioDirector.play_variant(impact_category)
				AudioDirector.play_damage_reaction(actor.unit)
			actor.take_hit()
			if screen._battlefield != null and is_instance_valid(screen._battlefield):
				screen._battlefield.spawn_elemental_burst(actor.position + Vector2(0, -18.0), element)
			if crit or amount > 50:
				screen._camera_shake(4.0 if crit else 2.0, 0.2))
		# Damage numbers share the exact same per-skill impact beat.
		screen._float_text(actor, "-%d%s" % [amount, "!" if crit else ""], color, impact_delay)


func animate_attack(attacker: BattlefieldActor, target: BattlefieldActor,
		skill_id: String = "", ultimate: bool = false) -> void:
	if screen._battlefield == null or attacker == null:
		return
	var element := "neutral"
	if screen.engine != null and attacker.unit != null:
		var combat_index := attacker.unit.combat_index
		if combat_index >= 0 and combat_index < screen.engine.combatants.size():
			var source: Combatant = screen.engine.combatants[combat_index]
			element = str(source.element)
	var skill_definition: SkillDef = ContentDB.get_skill(skill_id) if not skill_id.is_empty() else null
	if skill_definition != null and (skill_definition.ultimate or skill_definition.animation_key in ["cast", "heal", "guard"]):
		if skill_definition.animation_key == "cast":
			AudioDirector.play_variant("magic_projectile")
		else:
			AudioDirector.play_spell_cast()
	elif attacker.unit != null and attacker.unit.def_id.begins_with("kael"):
		AudioDirector.play_variant("sword_swing")
	screen._battlefield.play_attack(attacker, target, element, skill_id, ultimate)
	if attacker.unit != null and attacker.unit.def_id == "fallen_matron" and (ultimate or skill_id == "matron_verdict"):
		screen._camera_shake(8.0, 0.42)
	elif attacker.unit != null and attacker.unit.def_id == "kael" and ultimate:
		# A short anticipation tremor followed by the larger final-impact shake.
		screen._camera_shake(3.0, 0.24)
		screen.get_tree().create_timer(0.78).timeout.connect(func() -> void:
			if is_instance_valid(screen) and screen.is_inside_tree() and not screen._resolved:
				screen._camera_shake(10.0, 0.52)
		)


