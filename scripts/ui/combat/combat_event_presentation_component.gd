class_name CombatEventPresentationComponent
extends Node
## Converts deterministic combat events into battle presentation and timed hit reactions.

var screen: CombatScreen
var _lilith_entrance_played := false
var _lilith_low_health_played := false
var _gerald_entrance_played := false
var _gerald_low_health_played := false
var _mirene_entrance_played := false
var _mirene_boss_entrance_played := false
var _mirene_low_health_played := {}
var _mirene_boss_defeated := false
var _cassien_entrance_played := false
var _cassien_boss_entrance_played := false
var _cassien_low_health_played := {}
var _cassien_boss_defeated := false
var _kael_entrance_played := false
var _kael_low_health_played := {}
var _kael_fell := false
var _final_voice_entrances := {}
var _final_voice_low_health := {}
var _final_voice_boss_defeated := false

func reset_character_voice() -> void:
	_lilith_entrance_played = false
	_lilith_low_health_played = false
	_gerald_entrance_played = false
	_gerald_low_health_played = false
	_mirene_entrance_played = false
	_mirene_boss_entrance_played = false
	_mirene_low_health_played.clear()
	_mirene_boss_defeated = false
	_cassien_entrance_played = false
	_cassien_boss_entrance_played = false
	_cassien_low_health_played.clear()
	_cassien_boss_defeated = false
	_kael_entrance_played = false
	_kael_low_health_played.clear()
	_kael_fell = false
	_final_voice_entrances.clear()
	_final_voice_low_health.clear()
	_final_voice_boss_defeated = false

func _has_living_lilith() -> bool:
	if screen.engine == null:
		return false
	for unit in screen.engine.living(CombatEngine.PLAYER_TEAM):
		if AudioDirector.is_lilith_voice_id(unit.def_id):
			return true
	return false


func _has_living_gerald() -> bool:
	if screen.engine == null:
		return false
	for unit in screen.engine.living(CombatEngine.PLAYER_TEAM):
		if AudioDirector.is_gerald_voice_id(unit.def_id):
			return true
	return false


func _has_living_mirene(team: int) -> bool:
	if screen.engine == null:
		return false
	for unit in screen.engine.living(team):
		if AudioDirector.is_mirene_voice_id(unit.def_id):
			return true
	return false


func _has_living_cassien(team: int) -> bool:
	if screen.engine == null:
		return false
	for unit in screen.engine.living(team):
		if AudioDirector.is_cassien_voice_id(unit.def_id):
			return true
	return false


func _has_living_kael() -> bool:
	if screen.engine == null:
		return false
	for unit in screen.engine.living(CombatEngine.PLAYER_TEAM):
		if AudioDirector.is_kael_voice_id(unit.def_id):
			return true
	return false


func bind(owner_screen: CombatScreen) -> void:
	screen = owner_screen

func process_events(events: Array) -> void:
	if screen._resolved:
		return
	var entrance_cues: Array = []
	if screen.engine != null:
		for team in [1, CombatEngine.PLAYER_TEAM]:
			for unit in screen.engine.living(team):
				var voice_character := AudioDirector.final_voice_character(unit.def_id)
				var entrance_key := "%s:%s" % [team, voice_character]
				if not voice_character.is_empty() and not _final_voice_entrances.has(entrance_key):
					_final_voice_entrances[entrance_key] = true
					entrance_cues.append([voice_character, "battle/entrance"])
	if not _cassien_boss_entrance_played and _has_living_cassien(1):
		_cassien_boss_entrance_played = true
		entrance_cues.append(["cassien", "boss_entrance"])
	if not _mirene_boss_entrance_played and _has_living_mirene(1):
		_mirene_boss_entrance_played = true
		entrance_cues.append(["mirene", "battle/entrance"])
	if not _kael_entrance_played and _has_living_kael():
		_kael_entrance_played = true
		entrance_cues.append(["kael", "battle/entrance"])
	if not _gerald_entrance_played and _has_living_gerald():
		_gerald_entrance_played = true
		entrance_cues.append(["gerald", "protect_lilith" if _has_living_lilith() else "battle/entrance"])
	if not _lilith_entrance_played and _has_living_lilith():
		_lilith_entrance_played = true
		entrance_cues.append(["lilith", "battle/entrance"])
	if not _mirene_entrance_played and _has_living_mirene(CombatEngine.PLAYER_TEAM):
		_mirene_entrance_played = true
		entrance_cues.append(["mirene", "summon_greeting"])
	if not _cassien_entrance_played and _has_living_cassien(CombatEngine.PLAYER_TEAM):
		_cassien_entrance_played = true
		entrance_cues.append(["cassien", "summon_greeting"])
	if not entrance_cues.is_empty():
		AudioDirector.play_sibling_voice_sequence(entrance_cues, screen)
	var pending_deaths: Array[BattlefieldActor] = []
	for event in events:
		var event_type := str(event.get("type", ""))
		match event_type:
			"bond":
				var bond_id := str(event.get("bond_id", ""))
				if CombatEngine.BOND_PAIRS.has(bond_id):
					screen._log("[color=#d8afff]%s[/color]" % str(event.get("skill_name", "")))
					var path := "res://assets/characters/bond_skills/%s/%s_preview.tscn" % [bond_id,bond_id]
					var packed := load(path) as PackedScene
					if packed != null:
						var cinematic := packed.instantiate() as Node2D
						var layer := CanvasLayer.new()
						layer.layer = 50
						screen.add_child(layer)
						var dim := ColorRect.new()
						dim.size = screen.get_viewport_rect().size
						dim.color = Color(0.025, 0.015, 0.045, 0.93)
						dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
						layer.add_child(dim)
						layer.add_child(cinematic)
						var factor := minf(dim.size.x / 1280.0, dim.size.y / 720.0)
						cinematic.scale = Vector2.ONE * factor
						cinematic.position = (dim.size - Vector2(1280,720) * factor) * 0.5
						var player := cinematic.get_node("AnimationPlayer") as AnimationPlayer
						player.speed_scale = maxf(1.0, screen._speed)
						player.play(bond_id)
						await player.animation_finished
						if not is_instance_valid(screen) or not screen.is_inside_tree(): return
						layer.queue_free()
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
				# Authoritative replies may bundle the player action and subsequent enemy actions.
				# Let the authored withdrawal finish before presenting the next action.
				if _kael_sequence_running():
					await screen._wait_for_cinematic_impact()
					if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved: return
					screen._flush_pending_deaths(pending_deaths)
					pending_deaths.clear()
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
				var heal_delay := 0.16
				var heal_source: Combatant = screen.engine.get_by_uid(str(event.get("actor_uid", ""))) if screen.engine != null else null
				if str(event.get("status", "")) == "lifesteal" and _is_revienna(heal_source):
					heal_delay = _revienna_impact_delay(str(event.get("skill_id", "")))
					if heal_amount > 0:
						screen.get_tree().create_timer(heal_delay).timeout.connect(func() -> void:
							if is_instance_valid(screen) and screen.is_inside_tree() and not screen._resolved:
								AudioDirector.play_variant("healing"))
				elif heal_amount > 0:
					AudioDirector.play_variant("healing")
				screen._log("[color=#8fe3a0]%s recovers %d HP.[/color]" % [str(event.get("target_name", "Unit")), heal_amount])
				screen._float_text(heal_actor, "+%d" % heal_amount, UITheme.GREEN, heal_delay)
			"shield":
				screen._log("[color=#7fe3e0]%s gains a %d shield.[/color]" % [str(event.get("target_name", "Unit")), int(event.get("amount", 0))])
			"status":
				var status_id := str(event.get("status",""))
				var status_actor := screen._actor_for_uid(str(event.get("target_uid","")))
				if status_id == "cleanse":
					screen._float_text(status_actor,"CLEANSED",UITheme.TEAL)
				elif status_id == "bond_guard":
					screen._float_text(status_actor,"GUARDED",UITheme.TEAL)
				elif status_id == "bond_survive" and int(event.get("turns",0)) == 0:
					screen._float_text(status_actor,"BEYOND DEATH",UITheme.GREEN)
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
				if fallen != null and fallen.unit != null and fallen.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_lilith_voice_id(fallen.unit.def_id):
					AudioDirector.play_sibling_voice_sequence([["lilith", "gerald_distress"], ["gerald", "comfort"]] if _has_living_gerald() else [["lilith", "gerald_distress"]], screen)
				elif fallen != null and fallen.unit != null and fallen.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_gerald_voice_id(fallen.unit.def_id) and _has_living_lilith():
					AudioDirector.play_lilith_voice("gerald_distress", screen, true)
				if fallen != null and fallen.unit != null and AudioDirector.is_mirene_voice_id(fallen.unit.def_id):
					if fallen.unit.team != CombatEngine.PLAYER_TEAM:
						_mirene_boss_defeated = true
					AudioDirector.play_mirene_voice("battle/defeat", screen, true)
				if fallen != null and fallen.unit != null and AudioDirector.is_cassien_voice_id(fallen.unit.def_id):
					if fallen.unit.team != CombatEngine.PLAYER_TEAM:
						_cassien_boss_defeated = true
					AudioDirector.play_cassien_voice("defeat", screen, true)
				if fallen != null and fallen.unit != null and fallen.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_kael_voice_id(fallen.unit.def_id):
					_kael_fell = true
					AudioDirector.play_kael_voice("defeat", screen, true)
				if fallen != null and fallen.unit != null:
					var voice_character := AudioDirector.final_voice_character(fallen.unit.def_id)
					if not voice_character.is_empty():
						if fallen.unit.team != CombatEngine.PLAYER_TEAM:
							_final_voice_boss_defeated = true
						AudioDirector.play_character_voice(voice_character, "battle/defeat" if voice_character == "ravienna" else "defeat", screen, true)
				if fallen != null and fallen.unit != null and fallen.unit.is_boss and screen._boss_presentation_rig != null:
					if screen._boss_presentation_rig.has_method("clear_target_telegraphs"):
						screen._boss_presentation_rig.call("clear_target_telegraphs")
				if screen._cinematic_finish_delay > 0.0:
					if fallen != null:
						pending_deaths.append(fallen)
				elif screen._battlefield != null:
					screen._battlefield.play_death(fallen)
			"phase":
				if _kael_sequence_running():
					await screen._wait_for_cinematic_impact()
					if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved: return
					screen._flush_pending_deaths(pending_deaths)
					pending_deaths.clear()
				var phase_message := str(event.get("message", "The boss changes."))
				var phase_uid := str(event.get("actor_uid", ""))
				var phase_boss: Combatant = screen.engine.get_by_uid(phase_uid) if screen.engine != null else null
				var phase_boss_id := str(event.get("boss_id", phase_boss.def_id if phase_boss != null else ""))
				var phase_boss_name := str(event.get("boss_name", phase_boss.display_name if phase_boss != null else ""))
				var phase_number := int(event.get("phase_number", 2))
				if screen._hud_component != null:
					screen._hud_component.refresh_boss_header(phase_number)
				screen._log("[color=#ffc95e]%s[/color]" % phase_message)
				screen._camera_shake(10.0, 0.5)
				if phase_boss_id.is_empty():
					screen._show_banner(phase_message)
				else:
					await screen._show_boss_phase_transition(phase_boss_id, phase_number, phase_message, phase_boss_name)
				if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved:
					return
				if phase_boss_id == "revienna_boss":
					var ravienna := screen._actor_for_uid(phase_uid)
					if is_instance_valid(ravienna) and is_instance_valid(ravienna.ravienna_art):
						ravienna.ravienna_art.get_node("PoseAnimation").play("phase")
				if screen._battlefield != null and phase_boss_id == "fallen_matron":
					screen._battlefield.play_matron_phase(phase_number)
			"victory":
				await screen._wait_for_cinematic_impact()
				if not is_instance_valid(screen) or not screen.is_inside_tree():
					return
				screen._flush_pending_deaths(pending_deaths)
				await _wait_for_gerald_surrender()
				if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved:
					return
				screen._refresh_cards()
				if screen._battlefield != null:
					screen._battlefield.play_victory_animations()
				var victory_cues: Array = []
				if _has_living_kael():
					victory_cues.append(["kael", "battle/victory"])
				if _has_living_gerald():
					victory_cues.append(["gerald", "battle/victory"])
				if _has_living_lilith():
					victory_cues.append(["lilith", "battle/victory"])
				if _has_living_mirene(CombatEngine.PLAYER_TEAM):
					victory_cues.append(["mirene", "battle/victory"])
				if _has_living_cassien(CombatEngine.PLAYER_TEAM):
					victory_cues.append(["cassien", "battle/victory"])
				if screen.engine != null:
					var voiced := {}
					for unit in screen.engine.living(CombatEngine.PLAYER_TEAM):
						var voice_character := AudioDirector.final_voice_character(unit.def_id)
						if not voice_character.is_empty() and not voiced.has(voice_character):
							voiced[voice_character] = true
							victory_cues.append([voice_character, "battle/victory"])
				if not victory_cues.is_empty() and not _mirene_boss_defeated and not _cassien_boss_defeated and not _final_voice_boss_defeated:
					AudioDirector.play_sibling_voice_sequence(victory_cues, screen)
				screen._finish_battle(true)
				return
			"defeat":
				await screen._wait_for_cinematic_impact()
				if not is_instance_valid(screen) or not screen.is_inside_tree():
					return
				screen._flush_pending_deaths(pending_deaths)
				screen._refresh_cards()
				if _has_living_mirene(1):
					AudioDirector.play_mirene_voice("battle/victory", screen, true)
				if _has_living_cassien(1):
					AudioDirector.play_cassien_voice("battle/victory", screen, true)
				if not _kael_fell and _has_living_kael():
					AudioDirector.play_kael_voice("defeat", screen, true)
				if screen.engine != null:
					for unit in screen.engine.living(1):
						var voice_character := AudioDirector.final_voice_character(unit.def_id)
						if not voice_character.is_empty():
							AudioDirector.play_character_voice(voice_character, "battle/victory", screen, true)
							break
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


func _kael_sequence_running() -> bool:
	if not is_instance_valid(screen._battlefield): return false
	for actor in screen._battlefield.actors():
		if is_instance_valid(actor) and actor.kael_boss_sequence_active: return true
	return false


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
				positions.append(rig.get_global_transform_with_canvas().affine_inverse() * target_actor.get_global_transform_with_canvas().origin)
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


static func _is_revienna(source: Combatant) -> bool:
	return source != null and (source.def_id == "revienna_boss" or source.def_id == "ravienna" or source.def_id.begins_with("ravienna_"))


static func _revienna_impact_delay(skill_id: String) -> float:
	match BattlefieldActor.ravienna_visual_skill(skill_id):
		"ravienna_eclipse": return 1.25
		"corruption_bolt": return 0.885
		"shadow_lash": return 0.76
		"soul_drain": return 1.01
		"hollow_wail": return 0.75
		_: return 0.5


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
		if source != null and KaelAttackPresentationComponent.is_kael(source.def_id):
			var kael_actor := screen._actor_for_uid(str(event.get("actor_uid", "")))
			if KaelAttackPresentationComponent.uses_boss_combo(kael_actor, str(event.get("skill_id", "")), bool(event.get("ultimate", false))):
				impact_delay = KaelAttackPresentationComponent.BOSS_IMPACT_TIME
		if _is_revienna(source):
			impact_delay = _revienna_impact_delay(str(event.get("skill_id", "")))
		if source != null and source.def_id == "fairy_spar":
			impact_delay = BattlefieldActor.fairy_impact_time(str(event.get("skill_id", "")), bool(event.get("ultimate", false)))
		if source != null and (source.def_id == "cassien_boss" or source.def_id == "cassien" or source.def_id.begins_with("cassien_")):
			impact_delay = BattlefieldActor.cassien_impact_time(str(event.get("skill_id", "")), bool(event.get("ultimate", false)))
		if source != null and source.def_id == "gerald_boss":
			impact_delay = 0.88 if str(event.get("skill_id", "")) in ["gerald_earthquake", "gerald_village_earthquake"] else 0.98
			var gerald_actor := screen._actor_for_uid(str(event.get("actor_uid", "")))
			if is_instance_valid(gerald_actor) and gerald_actor.gerald_walk_sequence_active:
				impact_delay += BattlefieldActor.GERALD_WALK_TIME
		screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, impact_delay)
		screen.get_tree().create_timer(impact_delay).timeout.connect(func() -> void:
			if not is_instance_valid(screen) or not screen.is_inside_tree() or screen._resolved or not is_instance_valid(actor):
				return
			if actor.unit != null and actor.unit.is_boss and screen._boss_presentation_rig != null and screen._boss_presentation_rig.has_method("clear_target_telegraphs"):
				screen._boss_presentation_rig.call("clear_target_telegraphs")
			if source != null and source.is_boss and screen._boss_presentation_rig != null:
				var rig: Node = screen._boss_presentation_rig
				if rig.has_method("play_impact"):
					rig.call("play_impact", rig.get_global_transform_with_canvas().affine_inverse() * actor.get_global_transform_with_canvas().origin, source.def_id, 1.0 if crit else 0.82)
			if absorbed > 0:
				AudioDirector.play_variant("shield_block")
			if amount > 0:
				var impact_skill: SkillDef = ContentDB.get_skill(str(event.get("skill_id", "")))
				var impact_category := "critical_hit" if crit else ("magic_impact" if _is_revienna(source) or (impact_skill != null and impact_skill.animation_key == "cast") else "sword_impact")
				if absorbed <= 0:
					AudioDirector.play_variant(impact_category)
				if actor.unit != null and actor.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_lilith_voice_id(actor.unit.def_id):
					if actor.unit.hp > 0 and actor.unit.hp <= actor.unit.max_hp * 0.25 and not _lilith_low_health_played:
						if AudioDirector.play_lilith_voice("battle/low_health", screen):
							_lilith_low_health_played = true
					elif actor.unit.hp > 0:
						AudioDirector.play_lilith_voice("battle/hurt", screen)
				elif actor.unit != null and actor.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_gerald_voice_id(actor.unit.def_id):
					if actor.unit.hp > 0 and actor.unit.hp <= actor.unit.max_hp * 0.25 and not _gerald_low_health_played:
						if AudioDirector.play_gerald_voice("battle/low_health", screen):
							_gerald_low_health_played = true
					elif actor.unit.hp > 0:
						AudioDirector.play_gerald_voice("battle/hurt", screen)
				elif actor.unit != null and AudioDirector.is_mirene_voice_id(actor.unit.def_id):
					if actor.unit.hp > 0 and actor.unit.hp <= actor.unit.max_hp * 0.25 and not _mirene_low_health_played.has(actor.unit.uid):
						if AudioDirector.play_mirene_voice("battle/low_health", screen):
							_mirene_low_health_played[actor.unit.uid] = true
					elif actor.unit.hp > 0:
						AudioDirector.play_mirene_voice("battle/hurt", screen)
				elif actor.unit != null and AudioDirector.is_cassien_voice_id(actor.unit.def_id):
					if actor.unit.hp > 0 and actor.unit.hp <= actor.unit.max_hp * 0.25 and not _cassien_low_health_played.has(actor.unit.uid):
						if AudioDirector.play_cassien_voice("battle/low_health", screen):
							_cassien_low_health_played[actor.unit.uid] = true
					elif actor.unit.hp > 0:
						AudioDirector.play_cassien_voice("battle/hurt", screen)
				elif actor.unit != null and actor.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_kael_voice_id(actor.unit.def_id):
					if actor.unit.hp > 0 and actor.unit.hp <= actor.unit.max_hp * 0.25 and not _kael_low_health_played.has(actor.unit.uid):
						if AudioDirector.play_kael_voice("battle/low_health", screen):
							_kael_low_health_played[actor.unit.uid] = true
					elif actor.unit.hp > 0:
						AudioDirector.play_kael_voice("battle/hurt", screen)
				elif actor.unit != null and not AudioDirector.final_voice_character(actor.unit.def_id).is_empty():
					var voice_character := AudioDirector.final_voice_character(actor.unit.def_id)
					if actor.unit.hp > 0 and actor.unit.hp <= actor.unit.max_hp * 0.25 and not _final_voice_low_health.has(actor.unit.uid):
						if AudioDirector.play_character_voice(voice_character, "battle/low_health", screen):
							_final_voice_low_health[actor.unit.uid] = true
					elif actor.unit.hp > 0:
						AudioDirector.play_character_voice(voice_character, "battle/hurt", screen)
				else:
					AudioDirector.play_damage_reaction(actor.unit)
			actor.take_hit()
			if screen._battlefield != null and is_instance_valid(screen._battlefield):
				screen._battlefield.spawn_elemental_burst(actor.position + Vector2(0, -18.0), element)
			if source != null and source.def_id == "cassien_boss" and str(event.get("skill_id", "")) == "cassien_crimson_requiem":
				screen._camera_shake(7.0, 0.35)
			elif crit or amount > 50:
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
	if attacker.unit != null and attacker.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_lilith_voice_id(attacker.unit.def_id):
		var voice_line := "ghosts_call" if ultimate else ("battle/special_attack" if skill_definition != null and skill_definition.animation_key != "strike" else "battle/basic_attack")
		AudioDirector.play_lilith_voice(voice_line, screen)
	elif attacker.unit != null and attacker.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_gerald_voice_id(attacker.unit.def_id):
		var voice_line := "battle/special_attack" if ultimate or (skill_definition != null and skill_definition.animation_key != "strike") else "battle/basic_attack"
		AudioDirector.play_gerald_voice(voice_line, screen)
	elif attacker.unit != null and AudioDirector.is_mirene_voice_id(attacker.unit.def_id):
		var voice_line := "ultimate" if ultimate or skill_id == "hollow_wail" else ("illusion" if skill_id in ["shadow_feint", "corruption_bolt"] else "battle/basic_attack")
		AudioDirector.play_mirene_voice(voice_line, screen)
	elif attacker.unit != null and AudioDirector.is_cassien_voice_id(attacker.unit.def_id):
		var voice_line := "battle/ultimate" if ultimate or skill_id in ["soul_drain", "cassien_crimson_requiem"] else ("battle/special_attack" if skill_id in ["blood_waltz", "cassien_heavy_cleave", "cassien_crimson_crescent"] else "battle/basic_attack")
		AudioDirector.play_cassien_voice(voice_line, screen)
	elif attacker.unit != null and attacker.unit.team == CombatEngine.PLAYER_TEAM and AudioDirector.is_kael_voice_id(attacker.unit.def_id):
		var voice_line := "ultimate" if ultimate or skill_id == "blazing_charge" else ("battle/special_attack" if skill_id in ["ember_lance", "rally_cry"] else "battle/basic_attack")
		AudioDirector.play_kael_voice(voice_line, screen)
	elif attacker.unit != null and not AudioDirector.final_voice_character(attacker.unit.def_id).is_empty():
		var voice_character := AudioDirector.final_voice_character(attacker.unit.def_id)
		var voice_line := "ultimate" if ultimate or skill_id in ["hollow_moon_eclipse", "matron_verdict", "ravienna_eclipse"] or (voice_character == "elathra" and skill_id == "hollow_wail") else ("battle/special_attack" if skill_id in ["lunar_wisp", "velvet_hex", "crimson_binding", "corruption_bolt", "shadow_lash", "soul_drain", "hollow_wail"] else "battle/basic_attack")
		AudioDirector.play_character_voice(voice_character, voice_line, screen)
	if _is_revienna(attacker.unit):
		AudioDirector.play_variant("magic_charge" if BattlefieldActor.ravienna_visual_skill(skill_id) == "ravienna_eclipse" else "magic_projectile")
	elif skill_definition != null and (skill_definition.ultimate or skill_definition.animation_key in ["cast", "heal", "guard"]):
		if skill_definition.animation_key == "cast":
			AudioDirector.play_variant("magic_projectile")
		else:
			AudioDirector.play_spell_cast()
	elif attacker.unit != null and (attacker.unit.def_id.begins_with("kael") or attacker.unit.def_id == "cassien_boss"):
		AudioDirector.play_variant("sword_swing")
	screen._battlefield.play_attack(attacker, target, element, skill_id, ultimate)
	if KaelAttackPresentationComponent.uses_boss_combo(attacker, skill_id, ultimate):
		screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, KaelAttackPresentationComponent.BOSS_TOTAL_TIME + 0.06)
	if is_instance_valid(attacker.ravienna_art):
		skill_id = BattlefieldActor.ravienna_visual_skill(skill_id)
		screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, 2.1 if skill_id == "ravienna_eclipse" else 1.56 if skill_id in ["soul_drain", "hollow_wail"] else 1.06 if skill_id in ["shadow_lash", "corruption_bolt"] else 0.85)
		if skill_id == "ravienna_eclipse":
			screen.get_tree().create_timer(1.25).timeout.connect(func() -> void:
				if is_instance_valid(screen) and screen.is_inside_tree() and not screen._resolved:
					screen._camera_shake(6.0, 0.35))
		return
	if is_instance_valid(attacker.fairy_art):
		screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, attacker.fairy_action_duration(skill_id, ultimate) + 0.06)
		return
	if is_instance_valid(attacker.cassien_art):
		screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, attacker.cassien_action_duration(skill_id, ultimate) + 0.06)
		return
	if attacker.unit != null and attacker.unit.def_id == "gerald_boss":
		# Hold the next turn through the full authored recovery.
		screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, 1.99 if ultimate else 1.74)
		if attacker.gerald_walk_sequence_active:
			screen._cinematic_finish_delay = maxf(screen._cinematic_finish_delay, BattlefieldActor.GERALD_STRIKE_TIME + 2.0 * BattlefieldActor.GERALD_WALK_TIME + 0.06)
		if ultimate:
			screen.get_tree().create_timer(0.88).timeout.connect(func() -> void:
				if is_instance_valid(screen) and screen.is_inside_tree() and not screen._resolved and is_instance_valid(attacker) and not attacker.dead:
					screen._camera_shake(10.0, 0.48)
					screen._battlefield.shake_gerald_earthquake())
		return
	if attacker.unit != null and attacker.unit.def_id == "fallen_matron" and (ultimate or skill_id == "matron_verdict"):
		screen._camera_shake(8.0, 0.42)
	elif attacker.unit != null and attacker.unit.def_id == "kael" and ultimate:
		# A short anticipation tremor followed by the larger final-impact shake.
		screen._camera_shake(3.0, 0.24)
		screen.get_tree().create_timer(0.78).timeout.connect(func() -> void:
			if is_instance_valid(screen) and screen.is_inside_tree() and not screen._resolved:
				screen._camera_shake(10.0, 0.52)
		)



# Keep the victory overlay from covering the authored surrender.
func _wait_for_gerald_surrender() -> void:
	if screen._battlefield == null:
		return
	for actor in screen._battlefield.actors():
		if is_instance_valid(actor) and actor.dead and is_instance_valid(actor.fairy_art):
			if actor.fairy_art.animation == &"surrender" and actor.fairy_art.is_playing():
				await actor.fairy_art.animation_finished
			return
		if is_instance_valid(actor) and actor.dead and is_instance_valid(actor.ravienna_art):
			var sprite := actor.ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
			if sprite.animation == &"defeat" and sprite.is_playing():
				await sprite.animation_finished
			return
		if is_instance_valid(actor) and actor.dead and (is_instance_valid(actor.gerald_art) or is_instance_valid(actor.cassien_art)):
			var sprite: AnimatedSprite2D = actor.gerald_art if is_instance_valid(actor.gerald_art) else actor.cassien_art
			if sprite.animation == &"defeat" and sprite.is_playing():
				await sprite.animation_finished
			return
