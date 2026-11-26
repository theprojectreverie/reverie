
extends Node

## Verifies encounter-selected battle art, image-backed action controls,
## responsive HUD geometry, action filtering and combat action routing.
## Run: Godot --headless --path . res://tests/battle_visual_assets_smoke.tscn

var passed := 0
var failed := 0


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("[BattleVisualAssetsSmoke] " + label)


func _ready() -> void:
	var test_viewport := SubViewport.new()
	test_viewport.size = Vector2i(1280, 720)
	test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(test_viewport)

	var expected_backgrounds := {
		"castle_garden_sentinels": "moonlit_royal_garden.png",
		"royal_road_ambush": "frozen_castle_courtyard.png",
		"withered_grove_pack": "frozen_castle_courtyard.png",
		"fallen_aqueduct_sentinels": "frozen_castle_courtyard.png",
		"baltoria_encounter": "gothic_cathedral_hall.png",
		"corrupted_treant": "crimson_castle_ruins.png",
		"glade_mossling_pack": "greenward_battle.svg",
		"thornhound_hunt": "greenward_battle.svg",
		"fae_ambush": "greenward_battle.svg",
		"elder_hollow": "greenward_battle.svg",
		"moonpetal_sprite_pack": "greenward_battle.svg",
		"moonpetal_echoes_pack": "greenward_battle.svg",
		"fallen_matron_encounter": "withered_estate_battle.svg",
	}
	for group_id in expected_backgrounds:
		var path := BattlefieldLayoutComponent.battle_background_path_for_group(str(group_id))
		check(path.ends_with(str(expected_backgrounds[group_id])), "Encounter selects the correct battle artwork: " + str(group_id))
		check(load(path) is Texture2D, "Selected battle artwork loads: " + str(group_id))

	var bottom_scene := load("res://scenes/ui/combat/components/combat_bottom_hud.tscn") as PackedScene
	check(bottom_scene != null, "Combat bottom HUD scene loads")
	if bottom_scene != null:
		var bottom := bottom_scene.instantiate() as Control
		add_child(bottom)
		for button_name in ["AttackButton", "SkillButton", "UltimateButton", "DefendButton", "ItemButton", "EndTurnButton"]:
			var button := bottom.get_node_or_null("SkillsPanel/SkillsContent/ActionCategories/" + button_name) as TextureButton
			check(button != null, "Authored action button exists: " + button_name)
			check(button != null and button.texture_normal != null, "Action button texture is assigned: " + button_name)
		bottom.queue_free()

	var combat_scene := load("res://scenes/ui/combat_screen.tscn") as PackedScene
	check(combat_scene != null, "Playable combat screen scene loads")
	var battlefield_scene := load("res://scenes/ui/battlefield.tscn") as PackedScene
	check(battlefield_scene != null, "Battlefield scene loads with image-art backdrop")

	var battlefield_actor_scene := load("res://scenes/ui/battlefield_actor.tscn") as PackedScene
	check(battlefield_actor_scene != null, "Battlefield actor scene loads with authored boss animation library")

	# Guard the skill-presentation contract at both sides of the battlefield facade.
	# These checks complement the live-scene smoke test below without invoking
	# combat resolution or depending on the currently selected save roster.
	var effects_source := FileAccess.get_file_as_string("res://scripts/ui/combat/battlefield_effects_component.gd")
	var generic_source := FileAccess.get_file_as_string("res://scripts/ui/combat/generic_attack_presentation_component.gd")
	check(effects_source.contains("generic_attack_component.play_attack(attacker, target, element, skill_id, ultimate)"), "Battlefield facade forwards skill ID and ultimate flag to generic presentation")
	check(generic_source.contains("skill_id.to_lower() in [\"blade_wave\", \"guardian_aura\", \"ground_eruption\"]"), "Generic presentation recognizes all three authored Gerald skill IDs")
	check(generic_source.contains("attacker.visual.play_skill(skill_id)"), "Gerald skill route selects its matching authored visual variant")
	check(generic_source.contains("attacker.visual.play_cast()") and generic_source.contains("attacker.play_attack()"), "Non-basic skills and ordinary attacks retain separate animation routes")
	if battlefield_actor_scene != null:
		var gerald_probe := battlefield_actor_scene.instantiate() as BattlefieldActor
		test_viewport.add_child(gerald_probe)
		var gerald_unit := Combatant.new()
		gerald_unit.uid = "gerald_skill_route_probe"
		gerald_unit.def_id = "gerald"
		gerald_unit.display_name = "Gerald"
		gerald_unit.hp = 100.0
		gerald_unit.max_hp = 100.0
		gerald_unit.element = "fire"
		gerald_probe.setup(gerald_unit, true)
		var gerald_art_report := gerald_probe.visual.character_art_report()
		check(not bool(gerald_art_report.get("using_temporary_art", true)) and int(gerald_art_report.get("animation_count", 0)) >= 72, "Gerald uses validated disk-backed world sprite animations")
		var gerald_fx := gerald_probe.visual.get_node_or_null("Effects/GeraldCombatFX")
		for skill_variant in ["blade_wave", "guardian_aura", "ground_eruption"]:
			gerald_probe.visual.play_skill(skill_variant)
			check(gerald_probe.visual.animator.state == ActorVisual.S_CAST, "Gerald skill starts the CAST animation: " + skill_variant)
			check(gerald_fx != null and str(gerald_fx.get("skill_variant")) == skill_variant, "Gerald skill selects its matching authored FX rig: " + skill_variant)
		gerald_probe.queue_free()
	# Kael must keep the dedicated battlefield choreography, while Lilith's
	# cast/attack states must continue to draw through her own spectral FX layer.
	var kael_route_source := FileAccess.get_file_as_string("res://scripts/ui/combat/battlefield_effects_component.gd")
	var kael_presentation_source := FileAccess.get_file_as_string("res://scripts/ui/combat/kael_attack_presentation_component.gd")
	var generic_attack_source := FileAccess.get_file_as_string("res://scripts/ui/combat/generic_attack_presentation_component.gd")
	var identity_fx_source := FileAccess.get_file_as_string("res://scenes/characters/actor_visual.tscn")
	var matron_presentation_source := FileAccess.get_file_as_string("res://scripts/ui/combat/matron_attack_presentation_component.gd")
	check(matron_presentation_source.contains("target.home_position") and matron_presentation_source.contains("marked.home_position") and matron_presentation_source.contains("victim.home_position"), "Matron telegraphs and multi-target strikes use canonical actor slots")
	check(matron_presentation_source.contains("boss.home_position") and not matron_presentation_source.contains("victim.position"), "Matron phase and verdict choreography recover against canonical formation anchors")
	check(matron_presentation_source.contains("ground_telegraph.tscn") and matron_presentation_source.contains("player.play") and matron_presentation_source.contains("warning"), "Matron Verdict warnings reuse the authored ground telegraph scene")
	var verdict_function_start := matron_presentation_source.find("func _play_matron_verdict")
	var verdict_function_end := matron_presentation_source.find("func _spawn_verdict_seal", verdict_function_start)
	var verdict_function_source := matron_presentation_source.substr(verdict_function_start, verdict_function_end - verdict_function_start)
	check(verdict_function_source.contains('overlay_player.play("verdict")'), "Matron Verdict uses its authored overlay animation")
	check(verdict_function_source.contains("boss.track_attack_effect(overlay)"), "Matron Verdict overlay is owned and removed when its attack is interrupted")
	check(not verdict_function_source.contains('tween_property(veil') and not verdict_function_source.contains('modulate:a'), "Matron Verdict no longer drives overlay opacity with runtime tweens")
	var overlay_scene_text := FileAccess.get_file_as_string("res://scenes/ui/combat/components/matron_verdict_overlay.tscn")
	var seal_scene_text := FileAccess.get_file_as_string("res://scenes/ui/combat/components/matron_verdict_seal.tscn")
	var aura_scene_text := FileAccess.get_file_as_string("res://scenes/ui/combat/components/effect_glow_light.tscn")
	check(overlay_scene_text.contains("Animation_verdict") and overlay_scene_text.contains("verdict"), "Matron Verdict overlay owns authored veil/title animation")
	check(seal_scene_text.contains("Animation_seal") and seal_scene_text.contains("seal"), "Matron Verdict seal owns authored rotation/scale/fade animation")
	check(seal_scene_text.contains('points = PackedVector2Array') and seal_scene_text.contains('[node name="Spoke8"'), "Matron Verdict seal owns all circular paths and eight spokes in its scene")
	check(not matron_presentation_source.contains("range(97)") and not matron_presentation_source.contains("range(49)"), "Matron seal and ritual geometry are not generated at runtime")
	check(aura_scene_text.contains("Animation_pulse") and aura_scene_text.contains("pulse"), "Matron phase aura owns authored light pulse")
	var overlay_probe_scene := load("res://scenes/ui/combat/components/matron_verdict_overlay.tscn") as PackedScene
	var seal_probe_scene := load("res://scenes/ui/combat/components/matron_verdict_seal.tscn") as PackedScene
	var aura_probe_scene := load("res://scenes/ui/combat/components/effect_glow_light.tscn") as PackedScene
	if overlay_probe_scene != null:
		var overlay_probe := overlay_probe_scene.instantiate() as Control
		var overlay_anim := overlay_probe.get_node("AnimationPlayer") as AnimationPlayer
		overlay_anim.play("verdict")
		overlay_anim.advance(0.42)
		check((overlay_probe.get_node("Veil") as ColorRect).color.a > 0.5, "Authored Verdict overlay visibly raises the veil")
		overlay_probe.free()
	if seal_probe_scene != null:
		var seal_probe := seal_probe_scene.instantiate() as Node2D
		var seal_anim := seal_probe.get_node("AnimationPlayer") as AnimationPlayer
		seal_anim.play("seal")
		seal_anim.advance(0.85)
		check(seal_probe.scale.x > 1.0, "Authored Verdict seal expands")
		seal_probe.free()
	if aura_probe_scene != null:
		var aura_probe := aura_probe_scene.instantiate() as PointLight2D
		var aura_anim := aura_probe.get_node("AnimationPlayer") as AnimationPlayer
		aura_anim.play("pulse")
		aura_anim.advance(0.18)
		check(aura_probe.energy > 1.0, "Authored phase aura reaches its light pulse")
		aura_probe.free()
	var matron_orb_scene := load("res://scenes/ui/combat/components/matron_orb.tscn") as PackedScene
	var shadow_lash_scene := load("res://scenes/ui/combat/components/shadow_lash.tscn") as PackedScene
	var soul_beam_scene := load("res://scenes/ui/combat/components/soul_drain_beam.tscn") as PackedScene
	var orb_probe: Polygon2D = matron_orb_scene.instantiate() as Polygon2D if matron_orb_scene != null else null
	var lash_probe: Node2D = shadow_lash_scene.instantiate() as Node2D if shadow_lash_scene != null else null
	var beam_probe: Node2D = soul_beam_scene.instantiate() as Node2D if soul_beam_scene != null else null
	var orb_probe_player := orb_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer if orb_probe != null else null
	var lash_probe_player := lash_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer if lash_probe != null else null
	var beam_probe_player := beam_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer if beam_probe != null else null
	var lash_stroke := lash_probe.get_node_or_null("Stroke") as Line2D if lash_probe != null else null
	var beam_stroke := beam_probe.get_node_or_null("Stroke") as Line2D if beam_probe != null else null
	check(orb_probe_player != null and orb_probe_player.has_animation("travel"), "Matron orb owns an authored travel/fade clip")
	check(lash_probe_player != null and lash_probe_player.has_animation("fade") and lash_stroke != null and lash_stroke.points.size() >= 5, "Shadow lash owns authored curved geometry and a fade clip")
	check(beam_probe_player != null and beam_probe_player.has_animation("drain") and beam_stroke != null and beam_stroke.points.size() == 3, "Soul drain beam owns authored geometry and a width/fade clip")
	if orb_probe != null:
		orb_probe.free()
	if lash_probe != null:
		lash_probe.free()
	if beam_probe != null:
		beam_probe.free()
	var ritual_ring_scene := load("res://scenes/ui/combat/components/matron_ritual_ring.tscn") as PackedScene
	check(ritual_ring_scene != null, "Matron ritual ring scene loads")
	if ritual_ring_scene != null:
		var ritual_probe := ritual_ring_scene.instantiate() as Line2D
		var ritual_player := ritual_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		check(ritual_player != null and ritual_player.has_animation("ritual"), "Matron ritual ring owns an authored animation")
		if ritual_player != null:
			ritual_player.play("ritual")
			ritual_player.advance(0.36)
			check(ritual_probe.scale.x > 1.0 and ritual_probe.modulate.a < 1.0, "Authored ritual ring expands and fades")
		ritual_probe.queue_free()
	var verdict_column_scene := load("res://scenes/ui/combat/components/verdict_column.tscn") as PackedScene
	check(verdict_column_scene != null, "Matron Verdict column scene loads")
	if verdict_column_scene != null:
		var column_probe := verdict_column_scene.instantiate() as Polygon2D
		var column_player := column_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		check(column_player != null and column_player.has_animation("strike"), "Matron Verdict column owns an authored strike animation")
		if column_player != null:
			column_player.play("strike")
			column_player.advance(0.10)
			check(column_probe.color.a > 0.0 and (column_probe.get_node("Core") as Polygon2D).color.a > 0.0, "Authored strike clip illuminates column and core together")
		column_probe.queue_free()
	check(kael_route_source.contains("kael_attack_component.play_attack(attacker, target, skill_id, ultimate)"), "Kael skills remain routed through the dedicated choreography component")
	check(kael_presentation_source.contains("attacker.visual.play_cast()") and kael_presentation_source.contains("attacker.visual.play_attack()"), "Kael skills and basic attacks use distinct character animation states")
	var kael_ring_scene_text := FileAccess.get_file_as_string("res://scenes/ui/combat/components/magic_effect_line.tscn")
	check(kael_ring_scene_text.contains("points = PackedVector2Array") and kael_ring_scene_text.contains("MagicEffectLine"), "Kael magic rings reuse editor-authored ellipse geometry")
	var kael_slash_scene_text := FileAccess.get_file_as_string("res://scenes/ui/combat/components/kael_cross_slash.tscn")
	check(kael_slash_scene_text.contains("points = PackedVector2Array(-34, -25, -5, 2, 31, 27)") and kael_slash_scene_text.contains("Animation_slash"), "Kael cross slash owns its authored stroke and fade animation")
	check(not kael_presentation_source.contains("slash.points = PackedVector2Array") and not kael_presentation_source.contains("var normal := Vector2(-direction.y, direction.x)"), "Kael cross slash presentation positions and rotates its authored scene instead of generating points")
	check(not kael_presentation_source.contains("for i in 49") and not kael_presentation_source.contains("for i in 65") and not kael_presentation_source.contains("points.append(Vector2(cos(a)"), "Kael rally, ground seal and ultimate rings no longer generate geometry at runtime")
	check(kael_presentation_source.contains("target.home_position") and kael_presentation_source.contains("attacker.home_position"), "Kael choreography aims at canonical target slots and restores the attacker to formation")
	check(generic_attack_source.contains("hit_pose.play(\"battle_hit\")") and kael_presentation_source.contains("target.track_recoil_motion(recoil)") and kael_presentation_source.contains("target.track_recoil_motion(knock)"), "Generic authored hit pose and Kael recoil remain independent from attacker lunges")
	var actor_presentation_source := FileAccess.get_file_as_string("res://scripts/ui/combat/battlefield_actor.gd")
	check(actor_presentation_source.contains("_cancel_hit_flash()") and actor_presentation_source.contains("_hit_flash_tween = create_tween()"), "Hit-flash tint uses a replaceable presentation tween channel")
	check(matron_presentation_source.contains("boss.track_attack_motion(levitation)") and matron_presentation_source.contains("boss.track_attack_sequence(intro)"), "Matron body interruption cancels both levitation and pending verdict stages")
	check(identity_fx_source.contains("lilith_spectral_effects.tscn") and identity_fx_source.contains("LilithSpectralEffects"), "Lilith retains a dedicated scene-authored spectral identity FX rig")
	if battlefield_actor_scene != null:
		var kael_probe := battlefield_actor_scene.instantiate() as BattlefieldActor
		test_viewport.add_child(kael_probe)
		var kael_unit := Combatant.new()
		kael_unit.uid = "kael_skill_route_probe"
		kael_unit.def_id = "kael"
		kael_unit.display_name = "Kael"
		kael_unit.hp = 100.0
		kael_unit.max_hp = 100.0
		kael_unit.element = "fire"
		kael_probe.setup(kael_unit, true)
		var kael_art_report := kael_probe.visual.character_art_report()
		check(not bool(kael_art_report.get("using_temporary_art", true)) and int(kael_art_report.get("animation_count", 0)) >= 72, "Kael uses validated disk-backed playable world sprite animations")
		var kael_animation_player := kael_probe.get_node_or_null("KaelAnimationPlayer") as AnimationPlayer
		check(kael_animation_player != null, "Kael actor has a scene-owned combat AnimationPlayer")
		if kael_animation_player != null:
			for animation_name in ["kael_basic", "kael_cast", "kael_ultimate", "kael_recover"]:
				check(kael_animation_player.has_animation(animation_name), "Authored Kael combat animation exists: " + animation_name)
			kael_animation_player.play("kael_basic")
			kael_animation_player.advance(0.30)
			check(kael_animation_player.is_playing(), "Kael combo pose plays through AnimationPlayer")
			check(kael_probe.visual.scale.x > 1.0, "Kael AnimationPlayer keyframes animate the actual character visual")
			kael_animation_player.play("kael_recover")

			kael_animation_player.advance(0.12)
			check(kael_probe.visual.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(kael_probe.visual.rotation), "Kael authored recovery clip restores neutral pose after interruption")

		kael_probe.visual.play_cast()
		check(kael_probe.visual.character_id == "kael" and kael_probe.visual.animator.state == ActorVisual.S_CAST, "Kael probe enters its authored CAST state")
		kael_probe.visual.play_attack()
		check(kael_probe.visual.animator.state == ActorVisual.S_ATTACK, "Kael basic attack retains its dedicated attack state")
		kael_probe.set_home(Vector2(220, 180))
		kael_probe.position = kael_probe.home_position + Vector2(70, 0)
		var interrupted_motion := kael_probe.create_tween()
		interrupted_motion.tween_property(kael_probe, "position", kael_probe.home_position + Vector2(150, 0), 1.0)
		kael_probe.track_attack_motion(interrupted_motion)
		interrupted_motion.custom_step(0.05)
		kael_probe.take_hit()
		check(not interrupted_motion.is_running(), "Hit reaction cancels an in-flight attack movement tween")
		check(kael_probe.position.is_equal_approx(kael_probe.home_position), "Interrupted attack restores the actor to its canonical formation slot")
		var first_recoil := kael_probe.create_tween()
		first_recoil.tween_property(kael_probe, "position", kael_probe.home_position + Vector2(24, 0), 0.5)
		kael_probe.track_recoil_motion(first_recoil)
		first_recoil.custom_step(0.05)
		var replacement_recoil := kael_probe.create_tween()
		replacement_recoil.tween_property(kael_probe, "position", kael_probe.home_position + Vector2(36, 0), 0.5)
		kael_probe.track_recoil_motion(replacement_recoil)
		check(not first_recoil.is_running(), "A new target recoil cancels the previous recoil without touching attack motion")
		replacement_recoil.custom_step(0.05)
		kael_probe.take_hit()
		check(not replacement_recoil.is_running(), "Hit reaction cancels an active target recoil tween")
		check(kael_probe.position.is_equal_approx(kael_probe.home_position), "Interrupted target recoil restores the canonical formation slot")
		var first_hit_flash: Tween = kael_probe._hit_flash_tween
		kael_probe.take_hit()
		var replacement_hit_flash: Tween = kael_probe._hit_flash_tween
		check(first_hit_flash != null and not first_hit_flash.is_running(), "A repeated hit replaces the previous white-flash tween")
		kael_probe.play_victory()
		check(replacement_hit_flash != null and not replacement_hit_flash.is_running(), "Victory cancels any lingering hit-flash tween")
		check(kael_probe.visual.modulate.is_equal_approx(Color.WHITE), "Replacing or ending a hit flash restores the character tint")
		kael_probe.queue_free()
		var lilith_probe := battlefield_actor_scene.instantiate() as BattlefieldActor
		test_viewport.add_child(lilith_probe)
		var lilith_unit := Combatant.new()
		lilith_unit.uid = "lilith_skill_route_probe"
		lilith_unit.def_id = "lilith"
		lilith_unit.display_name = "Lilith"
		lilith_unit.hp = 100.0
		lilith_unit.max_hp = 100.0
		lilith_unit.element = "dark"
		lilith_probe.setup(lilith_unit, true)
		var lilith_art_report := lilith_probe.visual.character_art_report()
		check(not bool(lilith_art_report.get("using_temporary_art", true)) and int(lilith_art_report.get("animation_count", 0)) >= 72, "Lilith uses validated disk-backed world sprite animations")
		var lilith_pose_player := lilith_probe.get_node_or_null("BattlePoseAnimationPlayer") as AnimationPlayer
		check(lilith_pose_player != null and lilith_pose_player.has_animation("lilith_attack") and lilith_pose_player.has_animation("lilith_cast"), "Lilith has dedicated authored spectral attack and cast clips")
		if lilith_pose_player != null:
			lilith_pose_player.play("lilith_cast")
			lilith_pose_player.advance(0.30)
			check(lilith_pose_player.is_playing(), "Lilith cast pose plays through her dedicated AnimationPlayer clip")
		lilith_probe.visual.play_cast()
		check(lilith_probe.visual.character_id == "lilith" and lilith_probe.visual.animator.state == ActorVisual.S_CAST, "Lilith skill enters the CAST state for her spectral signature")
		check(lilith_probe.visual.character_effects_component != null, "Lilith spectral identity effects remain attached to the live actor")
		lilith_probe.visual.play_attack()
		check(lilith_probe.visual.animator.state == ActorVisual.S_ATTACK, "Lilith basic attack enters her distinct attack signature")
		check(is_equal_approx(lilith_unit.hp, 100.0), "Kael and Lilith presentation probes do not modify combat HP")
		lilith_probe.queue_free()
	if battlefield_actor_scene != null:
		var actor_probe := battlefield_actor_scene.instantiate() as Node2D
		test_viewport.add_child(actor_probe)
		var actor_animation_player := actor_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		var battle_pose_player := actor_probe.get_node_or_null("BattlePoseAnimationPlayer") as AnimationPlayer
		check(battle_pose_player != null, "Ordinary actors have a scene-owned authored battle pose AnimationPlayer")
		if battle_pose_player != null:
			check(battle_pose_player.has_animation("battle_basic") and battle_pose_player.has_animation("battle_cast") and battle_pose_player.has_animation("gerald_attack") and battle_pose_player.has_animation("gerald_cast"), "Default and Gerald-specific battle clips are authored Godot animations")
			check(battle_pose_player.has_animation("battle_recover"), "Ordinary battle pose library includes an authored recovery clip")
			battle_pose_player.play("battle_basic")
			battle_pose_player.advance(0.14)
			var ordinary_visual := actor_probe.get_node_or_null("ActorVisual") as Node2D
			check(ordinary_visual != null and not ordinary_visual.scale.is_equal_approx(Vector2.ONE), "Ordinary attack clip animates the actual character visual")
			battle_pose_player.play("battle_recover")
			battle_pose_player.advance(0.12)
			check(ordinary_visual != null and ordinary_visual.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(ordinary_visual.rotation), "Ordinary authored recovery restores the visual to neutral")
		check(actor_animation_player != null, "Battlefield actor has a scene-owned AnimationPlayer")
		if actor_animation_player != null:
			for animation_name in ["boss_idle", "boss_hit", "boss_attack", "boss_death"]:
				check(actor_animation_player.has_animation(animation_name), "Authored boss animation exists: " + animation_name)
			actor_animation_player.play("boss_attack")
			actor_animation_player.advance(0.15)
			var actor_probe_visual := actor_probe.get_node_or_null("ActorVisual") as Node2D
			check(actor_animation_player.is_playing(), "Boss attack plays through AnimationPlayer")
			check(actor_probe_visual != null and not actor_probe_visual.scale.is_equal_approx(Vector2.ONE), "Boss attack keyframes animate the actual actor visual")
		actor_probe.queue_free()

	var matron_scene := load("res://scenes/ui/combat/components/fallen_matron_presentation_component.tscn") as PackedScene
	check(matron_scene != null, "Fallen Matron presentation scene loads with authored animation library")
	if matron_scene != null:
		var matron_probe := matron_scene.instantiate()
		test_viewport.add_child(matron_probe)
		var matron_animation_player := matron_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		check(matron_animation_player != null, "Fallen Matron has a scene-owned AnimationPlayer")
		if matron_animation_player != null:
			for animation_name in ["idle", "phase_change", "hit", "attack", "death"]:
				check(matron_animation_player.has_animation(animation_name), "Authored Matron animation exists: " + animation_name)
			matron_animation_player.play("attack")
			matron_animation_player.advance(0.12)
			var matron_probe_art := matron_probe.get_node_or_null("Art") as Sprite2D
			check(matron_animation_player.is_playing(), "Matron attack plays through AnimationPlayer")
			check(matron_probe_art != null and absf(matron_probe_art.rotation) > 0.001, "Matron attack keyframes animate the illustrated boss cutout")
		matron_probe.queue_free()

	var floating_number_scene := load("res://scenes/ui/combat/components/floating_combat_number.tscn") as PackedScene
	check(floating_number_scene != null, "Floating combat number scene loads with authored motion")
	if floating_number_scene != null:
		var number_probe := floating_number_scene.instantiate() as Label
		test_viewport.add_child(number_probe)
		number_probe.position = Vector2(180, 260)
		number_probe.play_number(0.0, true)
		var number_player := number_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		check(number_player != null and number_player.has_animation("float"), "Floating combat number uses its scene-owned AnimationPlayer")
		if number_player != null:
			number_player.advance(0.16)
			check(number_probe.position.y < 260.0 and number_probe.scale.x > 1.0, "Authored floating-number clip animates rise and critical emphasis")
		number_probe.queue_free()
	var telegraph_scene := load("res://scenes/ui/combat/components/ground_telegraph.tscn") as PackedScene
	check(telegraph_scene != null, "Reusable ground telegraph scene loads")
	if telegraph_scene != null:
		var telegraph_probe := telegraph_scene.instantiate() as Node2D
		test_viewport.add_child(telegraph_probe)
		var telegraph_player := telegraph_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		check(telegraph_player != null and telegraph_player.has_animation("warning"), "Ground telegraph owns an authored warning animation")
		if telegraph_player != null:
			telegraph_player.play("warning")
			telegraph_player.advance(0.35)
			check(telegraph_probe.scale.x > 0.45 and telegraph_probe.modulate.a < 1.0, "Authored telegraph clip expands and fades the complete warning")
		telegraph_probe.queue_free()
	var floating_script := FileAccess.get_file_as_string("res://scripts/ui/combat/floating_combat_number.gd")
	check(floating_script.contains("clip.track_set_key_value(0, 0, position.y)") and floating_script.contains("clip.track_set_key_value(2, 0, scale)"), "Floating number animation retains per-instance starting height and critical scale")
	var kael_slash_scene := load("res://scenes/ui/combat/components/kael_cross_slash.tscn") as PackedScene
	var kael_flash_scene := load("res://scenes/ui/combat/components/kael_impact_flash.tscn") as PackedScene
	check(kael_slash_scene != null and kael_flash_scene != null, "Kael reusable slash and impact scenes load")
	if kael_slash_scene != null and kael_flash_scene != null:
		var slash_probe := kael_slash_scene.instantiate()
		var flash_probe := kael_flash_scene.instantiate()
		var slash_player := slash_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		var flash_player := flash_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		check(slash_player != null and slash_player.has_animation("slash"), "Kael slash lifecycle is editor-authored")
		check(flash_player != null and flash_player.has_animation("flash"), "Kael impact bloom lifecycle is editor-authored")
		slash_probe.queue_free()
		flash_probe.queue_free()
	var hit_effect_scene := load("res://scenes/ui/combat/components/battle_hit_effect.tscn") as PackedScene
	check(hit_effect_scene != null, "Reusable authored ordinary-hit effect scene loads")
	if hit_effect_scene != null:
		var hit_effect_probe := hit_effect_scene.instantiate() as Node2D
		test_viewport.add_child(hit_effect_probe)
		hit_effect_probe.call("play_impact", Vector2.RIGHT, Color("#65d9ff"), 1.0)
		var hit_effect_player := hit_effect_probe.get_node_or_null("AnimationPlayer") as AnimationPlayer
		var hit_effect_art := hit_effect_probe.get_node_or_null("Art") as Node2D
		check(hit_effect_player != null and hit_effect_player.has_animation("impact"), "Reusable hit effect exposes its authored impact animation")
		if hit_effect_player != null:
			hit_effect_player.advance(0.10)
			check(hit_effect_player.is_playing(), "Reusable hit effect animation runs")
		check(hit_effect_art != null and hit_effect_art.scale.x > 0.32, "Impact keyframes expand the authored slash artwork")
		var hit_effect_slash := hit_effect_probe.get_node_or_null("Art/Slash") as Line2D
		check(hit_effect_slash != null and hit_effect_slash.default_color.b > hit_effect_slash.default_color.r, "Impact accepts and applies the requested element tint")
		hit_effect_probe.queue_free()

	if combat_scene != null:
		var live_screen := combat_scene.instantiate() as CombatScreen
		live_screen.group_id = "corrupted_treant"
		test_viewport.add_child(live_screen)
		for _startup_frame in 10:
			if live_screen.find_child("BossIntroBanner", true, false) != null:
				break
			await get_tree().process_frame
		var boss_intro := live_screen.find_child("BossIntroBanner", true, false) as PanelContainer
		check(boss_intro != null, "Boss encounter creates the dedicated authored intro banner")
		var boss_rig_probe: Node = live_screen._boss_presentation_rig
		if boss_rig_probe != null:
			var pending_markers: Array[Node2D] = boss_rig_probe.show_target_telegraphs([Vector2(36, 36)], "elder_hollow", 1.0)
			var fired_impact: Node2D = boss_rig_probe.play_impact(Vector2(52, 52), "elder_hollow")
			boss_rig_probe.clear_target_telegraphs()
			await get_tree().process_frame
			check(pending_markers.size() == 1 and not is_instance_valid(pending_markers[0]), "Boss interruption clears pending warning markers")
			check(boss_rig_probe.transient_count() == 1 and is_instance_valid(fired_impact) and not fired_impact.is_queued_for_deletion(), "Boss interruption preserves an impact that has already fired")
			boss_rig_probe.clear_transients()

		var full_screen_art := live_screen.get_node_or_null("CombatScreenBackdrop/BattleArt") as TextureRect
		check(full_screen_art != null and full_screen_art.texture != null and full_screen_art.texture.resource_path.ends_with("crimson_castle_ruins.png"), "Live combat screen selects the encounter background")
		var live_battlefield := live_screen.find_child("Battlefield", true, false) as Battlefield
		var stage_art := live_battlefield.get_node_or_null("ArenaArtBackdrop") as TextureRect if live_battlefield != null else null
		check(stage_art != null and stage_art.visible and stage_art.texture != null and stage_art.texture.resource_path.ends_with("crimson_castle_ruins.png"), "Live battlefield displays the same encounter background")
		var generic_attack_fx := live_battlefield.get_node_or_null("GenericAttackPresentation") as GenericAttackPresentationComponent if live_battlefield != null else null
		check(generic_attack_fx != null, "Live battlefield owns the reusable ordinary attack presentation component")
		if generic_attack_fx != null:
			var effect_children_before := generic_attack_fx.get_child_count()
			var slash_owner := live_battlefield.actors()[0] as BattlefieldActor
			generic_attack_fx._spawn_slash(slash_owner, Vector2(500, 360), Vector2.RIGHT, "ice")
			var spawned_hit_effect := generic_attack_fx.get_child(generic_attack_fx.get_child_count() - 1) as Node2D if generic_attack_fx.get_child_count() > effect_children_before else null
			check(spawned_hit_effect != null and spawned_hit_effect.has_method("play_impact"), "Ordinary attack route instantiates the shared animated hit effect")
		if live_battlefield != null:
			var ordinary_attacker: BattlefieldActor = null
			var ordinary_target: BattlefieldActor = null
			for actor_entry in live_battlefield.actors():
				var candidate := actor_entry as BattlefieldActor
				if candidate.is_player and ordinary_attacker == null:
					ordinary_attacker = candidate
				elif not candidate.is_player and ordinary_target == null:
					ordinary_target = candidate
			for fx_actor_entry in live_battlefield.actors():
				var fx_actor := fx_actor_entry as BattlefieldActor
				if fx_actor.is_player and not fx_actor.dead and fx_actor.visual != null:
					await _check_character_effect_interruption(fx_actor)
			if ordinary_attacker != null and ordinary_target != null and ordinary_attacker.visual != null and ordinary_attacker.visual.animator != null:
				var target_hp_before: float = ordinary_target.unit.hp
				var target_home_before: Vector2 = ordinary_target.home_position
				live_battlefield.play_attack(ordinary_attacker, ordinary_target, "ice")
				check(ordinary_attacker.visual.animator.state == ActorVisual.S_ATTACK, "Ordinary battlefield attack triggers the character's authored attack state")
				check(is_equal_approx(ordinary_target.unit.hp, target_hp_before), "Presentation-only attack choreography never changes combat HP")
				check(ordinary_target.home_position.is_equal_approx(target_home_before), "Ordinary attack preserves the target's canonical formation anchor")
				var effects_before_attack := generic_attack_fx.get_child_count()
				await get_tree().create_timer(0.39).timeout
				var launched_effect_count := generic_attack_fx.get_child_count() - effects_before_attack
				check(launched_effect_count >= 2 and ordinary_attacker._attack_effects.is_empty(), "Ordinary attack releases its launched projectile and animated impact from caster cleanup")
				ordinary_attacker.take_hit()
				await get_tree().process_frame
				await get_tree().process_frame
				check(generic_attack_fx.get_child_count() >= effects_before_attack + launched_effect_count, "Interrupting an ordinary attack preserves already-launched visual effects")
				await get_tree().create_timer(0.75).timeout
				check(generic_attack_fx.get_child_count() == effects_before_attack, "Ordinary launched effects complete and clean themselves up")
		if boss_intro != null:
			var boss_intro_frame := boss_intro.get_theme_stylebox("panel") as StyleBoxTexture
			var boss_intro_name := boss_intro.get_node_or_null("Content/TextStack/BossName") as Label
			var boss_intro_crest := boss_intro.get_node_or_null("Content/Emblem") as TextureRect
			var boss_intro_standard := boss_intro.get_node_or_null("Content/RoyalStandard") as TextureRect
			check(boss_intro_frame != null and boss_intro_frame.texture.resource_path.ends_with("battle_dialogue_panel.png"), "Boss intro uses the ornate dialogue frame")
			check(boss_intro_name != null and boss_intro_name.text == live_screen._boss_name_label.text, "Boss intro displays the actual encounter boss name")
			check(boss_intro_crest != null and boss_intro_crest.texture.resource_path.ends_with("boss_emblem_crest.png"), "Boss intro displays the cropped glowing crest")
			check(boss_intro_standard != null and boss_intro_standard.texture.resource_path.ends_with("royal_banner.png"), "Boss intro displays the royal standard artwork")
			check(boss_intro.custom_minimum_size == Vector2(700, 164), "Boss intro keeps its authored wide cinematic dimensions")
		await get_tree().create_timer(2.35).timeout
		await get_tree().process_frame
		check(live_screen.find_child("BossIntroBanner", true, false) == null, "Boss intro banner releases itself after its timed presentation")
		var boss_rig := live_screen.get_node_or_null("BossPresentationRig")
		check(boss_rig != null, "Live combat screen includes the boss presentation rig")
		if boss_rig != null:
			live_screen._show_boss_phase_transition("corrupted_treant", 2,
				"The guardian's bark splits. Roots burst through the clearing.", "The Hollowed Guardian")
			await get_tree().process_frame
			var phase_cue := boss_rig.get_node_or_null("PhaseCue") as Control
			var root_mark := phase_cue.get_node_or_null("PhasePanel/Content/RootCrest") as TextureRect if phase_cue != null else null
			var matron_mark := phase_cue.get_node_or_null("PhasePanel/Content/MatronCrest") as TextureRect if phase_cue != null else null
			var root_phase_title := phase_cue.get_node_or_null("PhasePanel/Content/TextStack/PhaseTitle") as Label if phase_cue != null else null
			var root_boss_line := phase_cue.get_node_or_null("PhasePanel/Content/TextStack/BossLine") as Label if phase_cue != null else null
			var root_phase_message := phase_cue.get_node_or_null("PhasePanel/Content/TextStack/PhaseMessage") as Label if phase_cue != null else null
			var phase_frame := (phase_cue.get_node("PhasePanel") as PanelContainer).get_theme_stylebox("panel") as StyleBoxTexture if phase_cue != null else null
			check(phase_cue != null and phase_cue.visible, "Boss phase cue becomes visible through the combat-screen route")
			check(root_mark != null and root_mark.visible and root_mark.texture != null and root_mark.texture.resource_path.ends_with("elder_hollow_root_crest.png"), "Root-style boss uses the illustrated transparent root crest")
			check(matron_mark != null and not matron_mark.visible, "Root-style phase hides the Matron corruption crest")
			check(root_phase_title != null and root_phase_title.text == "THE ROOTS AWAKEN", "Elder-style phase uses its profile title")
			check(root_boss_line != null and root_boss_line.text.contains("THE HOLLOWED GUARDIAN") and root_boss_line.text.contains("PHASE 2 — HEARTWOOD BREAK"), "Root phase line identifies boss, phase number and phase identity")
			check(root_phase_message != null and root_phase_message.text.contains("bark splits"), "Root phase cue retains the actual combat event message")
			check(phase_frame != null and phase_frame.texture.resource_path.ends_with("battle_dialogue_panel.png"), "Boss phase cue uses the ornate dialogue frame")
			var elder_crest_texture := load("res://assets/ui/battle/boss/elder_hollow_root_crest.png") as Texture2D
			check(elder_crest_texture != null, "Illustrated Elder root crest imports as a texture")
			var elder_crest_image: Image = elder_crest_texture.get_image() if elder_crest_texture != null else null
			check(elder_crest_image != null and elder_crest_image.get_pixel(0, 0).a < 0.05 and elder_crest_image.get_pixel(383, 191).a < 0.05, "Illustrated Elder root crest preserves its transparent background")
			var root_telegraph: Node2D = boss_rig.call("show_target_telegraph", Vector2.ZERO, "corrupted_treant", 0.42) as Node2D
			var root_telegraph_crest := root_telegraph.get_node_or_null("Glyph/Artwork/RootCrest") as Sprite2D
			var root_telegraph_old_style := root_telegraph.get_node_or_null("Glyph/Artwork/ElderStyle") as Node2D
			check(root_telegraph_crest != null and root_telegraph_crest.visible and root_telegraph_crest.texture.resource_path.ends_with("elder_hollow_root_crest.png"), "Elder warning telegraph uses the illustrated root crest")
			check(root_telegraph_old_style == null, "Elder warning telegraph no longer contains the old geometric sigil")
			var root_impact: Node2D = boss_rig.call("play_impact", Vector2.ZERO, "corrupted_treant") as Node2D
			var root_impact_crest := root_impact.get_node_or_null("Glyph/Artwork/RootCrest") as Sprite2D
			var root_impact_old_style := root_impact.get_node_or_null("Glyph/Artwork/ElderStyle") as Node2D
			check(root_impact_crest != null and root_impact_crest.visible and root_impact_crest.texture.resource_path.ends_with("elder_hollow_root_crest.png"), "Elder impact flourish uses the illustrated root crest")
			check(root_impact_old_style == null, "Elder impact flourish no longer contains the old geometric sigil")
			var matron_telegraph: Node2D = boss_rig.call("show_target_telegraph", Vector2.ZERO, "fallen_matron", 0.42) as Node2D
			var matron_telegraph_crest := matron_telegraph.get_node_or_null("Glyph/Artwork/RootCrest") as Sprite2D
			var matron_telegraph_style := matron_telegraph.get_node_or_null("Glyph/Artwork/MatronStyle") as Node2D
			check(matron_telegraph_crest != null and not matron_telegraph_crest.visible and matron_telegraph_style != null and matron_telegraph_style.visible, "Matron telegraph retains its separate bloom treatment")
			var matron_impact: Node2D = boss_rig.call("play_impact", Vector2.ZERO, "fallen_matron") as Node2D
			var matron_impact_crest := matron_impact.get_node_or_null("Glyph/Artwork/RootCrest") as Sprite2D
			var matron_impact_style := matron_impact.get_node_or_null("Glyph/Artwork/MatronStyle") as Node2D
			check(matron_impact_crest != null and not matron_impact_crest.visible and matron_impact_style != null and matron_impact_style.visible, "Matron impact retains its separate bloom treatment")
			live_screen._show_boss_phase_transition("fallen_matron", 3,
				"The Matron screams. The ivory dress cracks, revealing the void beneath.", "The Fallen Matron")
			check(boss_rig._phase_queue.size() == 1, "Second phase cue queues behind the active first transition instead of replacing it")
			check(root_boss_line != null and root_boss_line.text.contains("THE HOLLOWED GUARDIAN"), "Queued second phase does not overwrite the active first phase")
			await get_tree().create_timer(1.7).timeout
			await get_tree().process_frame
			var matron_boss_line := phase_cue.get_node_or_null("PhasePanel/Content/TextStack/BossLine") as Label
			var matron_phase_title := phase_cue.get_node_or_null("PhasePanel/Content/TextStack/PhaseTitle") as Label
			check(matron_mark != null and matron_mark.visible and matron_mark.texture.resource_path.ends_with("boss_emblem_crest.png"), "Matron phase uses the supplied corruption-and-rose crest")
			check(root_mark != null and not root_mark.visible, "Matron phase hides the Elder root sigil")
			check(matron_phase_title != null and matron_phase_title.text == "THE GARDEN CLAIMS ITS DUE", "Matron phase uses its distinct profile title")
			check(matron_boss_line != null and matron_boss_line.text.contains("THE FALLEN MATRON") and matron_boss_line.text.contains("PHASE 3 — DESCENT"), "Matron phase identifies its descent stage")
			await get_tree().create_timer(1.7).timeout
			check(boss_rig._phase_queue.is_empty() and not boss_rig._phase_cue_busy, "Boss phase queue drains cleanly after both transitions finish")
		var hp_fill_style := live_screen._hp_bar.get_theme_stylebox("fill") as StyleBoxTexture
		var energy_fill_style := live_screen._energy_bar.get_theme_stylebox("fill") as StyleBoxTexture
		var meter_bg_style := live_screen._hp_bar.get_theme_stylebox("background") as StyleBoxTexture
		check(hp_fill_style != null and hp_fill_style.texture.resource_path.ends_with("hp_red_fill.png"), "Player HP bar uses the sliced authored meter")
		check(energy_fill_style != null and energy_fill_style.texture.resource_path.ends_with("energy_violet_fill.png"), "Player energy bar uses the sliced violet meter")
		check(meter_bg_style != null and meter_bg_style.texture.resource_path.ends_with("meter_empty_track.png"), "Player meters use the authored empty track")
		var boss_fill_style := live_screen._boss_hp_bar.get_theme_stylebox("fill") as StyleBoxTexture
		check(boss_fill_style != null and boss_fill_style.texture.resource_path.ends_with("hp_red_fill.png"), "Boss HP bar uses the sliced red meter")
		var turn_panel := live_screen.get_node("CombatScreenLayout/Root/TurnOrderPanel") as PanelContainer
		var turn_track_style := turn_panel.get_theme_stylebox("panel") as StyleBoxTexture
		check(turn_track_style != null and turn_track_style.texture.resource_path.ends_with("turn_order_track.png"), "Initiative panel uses the sliced six-slot track")
		check(turn_panel.custom_minimum_size == Vector2(533, 57), "Initiative track preserves its authored aspect ratio")
		var round_frame := load("res://assets/ui/battle/panels/sliced/portrait_frame_round_overlay.png") as Texture2D
		var tall_frame := load("res://assets/ui/battle/panels/sliced/portrait_frame_tall_overlay.png") as Texture2D
		var round_frame_image: Image = round_frame.get_image() if round_frame != null else null
		var tall_frame_image: Image = tall_frame.get_image() if tall_frame != null else null
		check(round_frame_image != null and round_frame_image.get_pixel(60, 72).a < 0.05, "Round portrait frame has a transparent center")
		check(tall_frame_image != null and tall_frame_image.get_pixel(102, 108).a < 0.05, "Tall portrait frame has a transparent center")

		# Force the max-party roster footprint even when the active save has fewer than four allies.
		if live_screen._roster_box != null and live_screen._roster_box.get_child_count() < 4:
			var fourth_roster_probe := preload("res://scenes/ui/combat/components/party_roster_entry.tscn").instantiate() as HBoxContainer
			var probe_portrait := Control.new()
			probe_portrait.custom_minimum_size = Vector2(28, 30)
			fourth_roster_probe.get_node("PortraitSlot").add_child(probe_portrait)
			(fourth_roster_probe.get_node("Info/Name") as Label).add_theme_font_size_override("font_size", 10)
			(fourth_roster_probe.get_node("Info/HPLabel") as Label).add_theme_font_size_override("font_size", 8)
			live_screen._roster_box.add_child(fourth_roster_probe)
		var bottom_hud := live_screen.get_node_or_null("CombatScreenLayout/Root/CombatBottomHUD") as HBoxContainer
		var layout_root := live_screen.get_node_or_null("CombatScreenLayout/Root") as VBoxContainer
		check(live_screen.size == Vector2(1280, 720), "Combat screen uses the tested 1280x720 viewport")
		check(bottom_hud != null and bottom_hud.size.x >= bottom_hud.get_combined_minimum_size().x, "Bottom HUD fits horizontally at the 1280px design viewport")
		check(bottom_hud != null and bottom_hud.position.y + bottom_hud.size.y <= 688.0, "Bottom HUD remains inside the 720px viewport safe margin")
		var roster_panel := live_screen.get_node("CombatScreenLayout/Root/CombatBottomHUD/RosterPanel") as Control
		check(roster_panel.get_combined_minimum_size().y <= 180.0, "Four-member roster fits within the fixed 180px bottom HUD")
		check(bottom_hud.get_combined_minimum_size().y <= 184.0, "Full bottom HUD minimum height stays within revised 184px")
		check(layout_root != null and layout_root.size.y <= 688.0, "Combat layout root fits the viewport safe area")

		var action_grid := live_screen.get_node_or_null("CombatScreenLayout/Root/CombatBottomHUD/SkillsPanel/SkillsContent/ActionCategories") as GridContainer
		check(action_grid != null and action_grid.get_child_count() == 6, "Live combat screen exposes all six image-based action controls")
		check(action_grid != null and action_grid.size.x >= action_grid.get_combined_minimum_size().x, "All six image buttons fit their authored three-column grid")

		# Wait for the authored encounter's initial presentation to finish, then
		# inject a deterministic local player turn for button-interaction checks.
		await get_tree().create_timer(0.7).timeout
		var first_roster_row := live_screen._roster_box.get_child(0) as HBoxContainer if live_screen._roster_box.get_child_count() > 0 else null
		var roster_portrait_slot := first_roster_row.get_node_or_null("PortraitSlot") as Control if first_roster_row != null else null
		var roster_portrait := roster_portrait_slot.get_child(0) as PortraitView if roster_portrait_slot != null and roster_portrait_slot.get_child_count() > 0 else null
		check(roster_portrait != null and roster_portrait._battle_frame_texture != null and roster_portrait._battle_frame_texture.resource_path.ends_with("portrait_frame_tall_overlay.png"), "Party roster portrait uses the transparent-center tall frame")
		live_screen._turn_token += 1
		var ui_defender := Combatant.new()
		ui_defender.uid = "ui_test_defender"
		ui_defender.display_name = "UI Test Defender"
		ui_defender.max_hp = 100.0
		ui_defender.hp = 100.0
		ui_defender.atk = 30.0
		ui_defender.defense = 20.0
		ui_defender.speed = 100.0
		ui_defender.skills = ["gale_shot", "zephyr_blessing"]
		ui_defender.statuses = [
			{"id": "atk_up", "turns": 2, "potency": 0.2},
			{"id": "poison", "turns": 3, "potency": 0.1},
			{"id": "def_down", "turns": 2, "potency": 0.2},
			{"id": "blind", "turns": 1, "potency": 0.25},
			{"id": "burn", "turns": 2, "potency": 0.05},
			{"id": "spd_up", "turns": 2, "potency": 0.2},
		]
		ui_defender.shield = 25.0

		var ui_opponent := Combatant.new()
		ui_opponent.uid = "ui_test_opponent"
		ui_opponent.display_name = "UI Test Opponent"
		ui_opponent.max_hp = 100.0
		ui_opponent.hp = 100.0
		ui_opponent.atk = 10.0
		ui_opponent.defense = 10.0
		ui_opponent.speed = 1.0

		var ui_engine := CombatEngine.new()
		ui_engine.setup([ui_defender], [ui_opponent], 90210)
		ui_engine.start()
		# Poison turn-start damage can consume shield; reset the UI fixture after
		# that real lifecycle tick so the shield tooltip has a deterministic value.
		ui_defender.shield = 25.0
		# Blind is injected after turn-start processing so its one-turn duration
		# is still active while the status text fallback is inspected.
		ui_defender.statuses.append({"id": "blind", "turns": 1, "potency": 0.25})
		live_screen.engine = ui_engine
		live_screen._resolved = false
		live_screen._animating = false
		live_screen._hud_component.refresh_skills()
		live_screen._hud_component.refresh_cards()
		check(ui_engine.current_actor() == ui_defender, "Live HUD interaction uses a deterministic player turn")
		check(CombatHudComponent.skill_icon_path(ContentDB.get_skill("gale_shot")).ends_with("general_strike.png"), "Unmodified damage skills use the general-strike icon")
		check(CombatHudComponent.skill_icon_path(ContentDB.get_skill("dawn_mend")).ends_with("support_bloom.png"), "Healing skills use the support-bloom icon")
		check(CombatHudComponent.skill_icon_path(ContentDB.get_skill("cinder_veil")).ends_with("support_bloom.png"), "Fire-element buffs retain the support-bloom icon")
		check(CombatHudComponent.skill_icon_path(ContentDB.get_skill("thorn_lash")).ends_with("control_chain.png"), "Status-control skills use the chain icon")
		check(CombatHudComponent.skill_icon_path(ContentDB.get_skill("blood_waltz")).ends_with("dark_arcane.png"), "Dark-element skills use the arcane icon")
		check(CombatHudComponent.skill_icon_path(ContentDB.get_skill("ember_lance")).ends_with("fire_burst.png"), "Fire-element skills use the fire-burst icon")
		for skill_icon_file in ["general_strike.png", "support_bloom.png", "control_chain.png", "dark_arcane.png", "fire_burst.png"]:
			var skill_icon_resource := load("res://assets/ui/battle/skills/sliced/" + skill_icon_file) as Texture2D
			check(skill_icon_resource != null, "Skill family icon imports: " + skill_icon_file)
		check(CombatHudComponent.status_icon_path("atk_up").ends_with("attack_modifier.png"), "Attack-up status maps to the crossed-swords crop")
		check(CombatHudComponent.status_icon_path("def_down").ends_with("defense_shield.png"), "Defense-down status maps to the shield crop")
		check(CombatHudComponent.status_icon_path("regen").ends_with("regeneration.png"), "Regeneration status maps to the healing crop")
		check(CombatHudComponent.status_icon_path("poison").ends_with("poison.png"), "Poison status maps to the droplet crop")
		check(CombatHudComponent.status_icon_path("stun").ends_with("stun.png"), "Stun status maps to the lightning crop")
		check(CombatHudComponent.status_icon_path("spd_down").ends_with("slow.png"), "Speed-down status maps to the hourglass crop")
		for icon_path in [
			"res://assets/ui/battle/icons/status/attack_modifier.png",
			"res://assets/ui/battle/icons/status/defense_shield.png",
			"res://assets/ui/battle/icons/status/regeneration.png",
			"res://assets/ui/battle/icons/status/poison.png",
			"res://assets/ui/battle/icons/status/stun.png",
			"res://assets/ui/battle/icons/status/slow.png",
		]:
			check(load(icon_path) is Texture2D, "Mapped status icon crop imports: " + icon_path.get_file())
		check(CombatHudComponent.status_icon_path("blind").is_empty() and CombatHudComponent.status_icon_path("burn").is_empty() and CombatHudComponent.status_icon_path("spd_up").is_empty(), "Unmatched statuses stay text-only rather than receiving guessed icons")
		var active_status_icons := live_screen.get_node("CombatScreenLayout/Root/CombatBottomHUD/ActiveInfoPanel/InfoContent/StatusIcons") as HBoxContainer
		check(active_status_icons != null and active_status_icons.get_child_count() == 4, "Active status row shows mapped effects and shield, not unmatched effects")
		if active_status_icons != null and active_status_icons.get_child_count() >= 4:
			check((active_status_icons.get_child(0) as TextureRect).texture.resource_path.ends_with("attack_modifier.png"), "Attack status icon uses the correct cropped PNG")
			check((active_status_icons.get_child(1) as TextureRect).texture.resource_path.ends_with("poison.png"), "Poison status icon uses the correct cropped PNG")
			var weakened_icon := active_status_icons.get_child(2) as TextureRect
			check(weakened_icon.texture.resource_path.ends_with("defense_shield.png"), "Defense-down uses the shield crop")
			check(weakened_icon.modulate.r > weakened_icon.modulate.g, "Down-effects tint their matched icon red")
			var shield_icon := active_status_icons.get_child(3) as TextureRect
			check(shield_icon.texture.resource_path.ends_with("defense_shield.png") and shield_icon.tooltip_text.contains("25 HP"), "Shield indicator shows the remaining shield amount")
		check(UIFactory.status_text(ui_defender).contains("Blind") and UIFactory.status_text(ui_defender).contains("Burn") and UIFactory.status_text(ui_defender).contains("Spd Up"), "Unmatched Blind, Burn and speed-up effects remain visible in text")
		live_screen._turn_order_component.refresh()
		check(live_screen._turn_box.get_child_count() == 6, "Initiative renderer always lays out six authored slots")
		var previous_slot := live_screen._turn_box.get_node_or_null("PreviousTurnSlot") as CenterContainer
		var active_turn_slot := live_screen._turn_box.get_node_or_null("ActiveTurnSlot") as CenterContainer
		check(previous_slot != null and previous_slot.get_child_count() == 1, "First diamond is reserved as the previous-turn spacer")
		check(active_turn_slot != null and active_turn_slot.get_child_count() == 1 and active_turn_slot.get_child(0) is PortraitView, "Current actor sits in the fixed highlighted second diamond")
		var active_portrait := active_turn_slot.get_child(0) as PortraitView if active_turn_slot != null else null
		check(active_portrait != null and active_portrait._battle_frame_texture != null and active_portrait._battle_frame_texture.resource_path.ends_with("portrait_frame_round_overlay.png"), "Initiative portrait uses the transparent-center round frame")
		check(active_turn_slot != null and is_equal_approx(active_turn_slot.custom_minimum_size.x, 70.0), "Initiative portraits align to the six background diamonds")

		if action_grid != null:
			var skill_button := action_grid.get_node("SkillButton") as TextureButton
			skill_button.pressed.emit()
			check(live_screen._hud_component._active_action_category == "skill", "Skill artwork button selects the live skill category")
			check(live_screen._skills_box.get_child_count() == 1, "Skill category filters to support and utility abilities")
			var support_skill_card := live_screen._skills_box.get_child(0) as Button if live_screen._skills_box.get_child_count() > 0 else null
			check(support_skill_card != null and (support_skill_card.get_node("CardContent/SkillIcon") as TextureRect).texture != null and (support_skill_card.get_node("CardContent/SkillIcon") as TextureRect).texture.resource_path.ends_with("support_bloom.png"), "Live support skill card displays its family icon")
			skill_button.mouse_entered.emit()
			check(skill_button.modulate.is_equal_approx(Color(1.0, 0.91, 0.68, 1.0)), "Action button receives gold hover/focus feedback")
			skill_button.mouse_exited.emit()

			var attack_button := action_grid.get_node("AttackButton") as TextureButton
			attack_button.pressed.emit()
			check(live_screen._hud_component._active_action_category == "attack", "Attack artwork button restores the attack category")
			check(live_screen._skills_box.get_child_count() == 1, "Attack category filters to damage abilities")
			var attack_skill_card := live_screen._skills_box.get_child(0) as Button if live_screen._skills_box.get_child_count() > 0 else null
			check(attack_skill_card != null and (attack_skill_card.get_node("CardContent/SkillIcon") as TextureRect).texture != null and (attack_skill_card.get_node("CardContent/SkillIcon") as TextureRect).texture.resource_path.ends_with("general_strike.png"), "Live attack skill card displays its family icon")

			(action_grid.get_node("ItemButton") as TextureButton).pressed.emit()
			check(live_screen.engine.current_actor() == ui_defender, "Unavailable Item action does not consume a turn")
			check(live_screen._hint_label.text.contains("No usable battle items"), "Unavailable Item action explains its current limitation")

			var defend_button := action_grid.get_node("DefendButton") as TextureButton
			defend_button.pressed.emit()
			check(ui_defender.defending, "Defend artwork button triggers the real defensive action")
			check(live_screen.engine.current_actor() == ui_opponent, "Defend artwork button advances the active turn")
			check(live_screen._animating, "Defend action holds the input lock while its event presentation finishes")
			defend_button.pressed.emit()
			check(live_screen.engine.current_actor() == ui_opponent, "Rapid repeat Defend click cannot consume a second turn")

			await get_tree().create_timer(0.7).timeout
			ui_engine.setup([ui_defender], [ui_opponent], 90211)
			ui_engine.start()
			live_screen._turn_token += 1
			live_screen._animating = false
			live_screen._hud_component.refresh_skills()
			var end_turn_button := action_grid.get_node("EndTurnButton") as TextureButton
			end_turn_button.pressed.emit()
			check(live_screen.engine.current_actor() == ui_opponent, "End Turn artwork button advances the active turn")
			check(live_screen._animating, "End Turn action holds the input lock while its event presentation finishes")
			end_turn_button.pressed.emit()
			check(live_screen.engine.current_actor() == ui_opponent, "Rapid repeat End Turn click cannot consume a second turn")

		for existing_banner in live_screen.get_children():
			if existing_banner is PanelContainer and existing_banner.name == "BattleEventBanner":
				existing_banner.queue_free()
		await get_tree().process_frame
		live_screen._show_banner("PHASE CHANGE")
		var event_banner := live_screen.find_child("BattleEventBanner", true, false) as PanelContainer
		check(event_banner != null, "Phase announcement creates the authored event banner panel")
		if event_banner != null:
			var event_frame := event_banner.get_theme_stylebox("panel") as StyleBoxTexture
			var event_title := event_banner.get_node_or_null("Title") as Label
			check(event_frame != null and event_frame.texture.resource_path.ends_with("battle_dialogue_panel.png"), "Event banner uses the ornate dialogue-panel artwork")
			check(event_title != null and event_title.text == "PHASE CHANGE", "Event banner displays the requested phase message")
			check(event_title != null and event_title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "Event banner title is center aligned")

		live_screen._result_component.show_result(true)
		await get_tree().process_frame
		var victory_layer := live_screen._result_layer
		var victory_panel := victory_layer.get_node_or_null("Center/Panel") as PanelContainer if victory_layer != null else null
		var victory_frame := victory_panel.get_theme_stylebox("panel") as StyleBoxTexture if victory_panel != null else null
		var victory_title := victory_layer.get_node_or_null("Center/Panel/Content/Title") as Label if victory_layer != null else null
		check(victory_frame != null and victory_frame.texture.resource_path.ends_with("battle_dialogue_panel.png"), "Victory result uses the ornate dialogue-panel frame")
		check(victory_title != null and victory_title.text == "VICTORY", "Victory result keeps its title and reward layout")
		var victory_crown := victory_layer.get_node_or_null("Center/Panel/Content/ResultCrownFlourish") as TextureRect if victory_layer != null else null
		check(victory_crown != null and victory_crown.texture.resource_path.ends_with("result_crown_flourish.png"), "Victory result includes the cropped transparent crown flourish")
		live_screen._result_component.show_result(false)
		await get_tree().process_frame
		var defeat_layer := live_screen._result_layer
		var defeat_panel := defeat_layer.get_node_or_null("Center/Panel") as PanelContainer if defeat_layer != null else null
		var defeat_frame := defeat_panel.get_theme_stylebox("panel") as StyleBoxTexture if defeat_panel != null else null
		var defeat_title := defeat_layer.get_node_or_null("Center/Panel/Content/Title") as Label if defeat_layer != null else null
		check(defeat_frame != null and defeat_frame.texture.resource_path.ends_with("battle_dialogue_panel.png"), "Defeat result uses the ornate dialogue-panel frame")
		check(defeat_title != null and defeat_title.text == "DEFEAT", "Defeat result keeps its retry and retreat layout")
		var defeat_crown := defeat_layer.get_node_or_null("Center/Panel/Content/ResultCrownFlourish") as TextureRect if defeat_layer != null else null
		check(defeat_crown != null and defeat_crown.texture.resource_path.ends_with("result_crown_flourish.png"), "Defeat result includes the same restrained crown flourish")

		live_screen.queue_free()
		await get_tree().process_frame
		await _check_live_background(combat_scene, "castle_garden_sentinels", "moonlit_royal_garden.png", test_viewport)
		await _check_live_background(combat_scene, "royal_road_ambush", "frozen_castle_courtyard.png", test_viewport)
		await _check_live_background(combat_scene, "corrupted_treant", "crimson_castle_ruins.png", test_viewport)
		await _check_live_background(combat_scene, "baltoria_encounter", "gothic_cathedral_hall.png", test_viewport)

	var defender := Combatant.new()
	defender.uid = "test_defender"
	defender.display_name = "Test Defender"
	defender.max_hp = 100.0
	defender.hp = 100.0
	defender.atk = 10.0
	defender.defense = 10.0
	defender.speed = 100.0

	var opponent := Combatant.new()
	opponent.uid = "test_opponent"
	opponent.display_name = "Test Opponent"
	opponent.max_hp = 100.0
	opponent.hp = 100.0
	opponent.atk = 10.0
	opponent.defense = 10.0
	opponent.speed = 1.0

	var phase_boss := Combatant.new()
	phase_boss.uid = "phase_boss"
	phase_boss.def_id = "elder_hollow"
	phase_boss.display_name = "The Elder Hollow"
	phase_boss.is_boss = true
	phase_boss.max_hp = 100.0
	phase_boss.hp = 55.0
	phase_boss.phases = [
		{"hp_below": 0.6, "message": "The roots awaken."},
		{"hp_below": 0.25, "message": "The Hollow enters its fury."},
	]
	var phase_engine := CombatEngine.new()
	phase_engine.setup([defender], [phase_boss], 4477)
	var first_phase_events := phase_engine.skill_resolver.check_boss_phases(phase_boss)
	check(first_phase_events.size() == 1, "First boss HP threshold emits one phase event")
	check(first_phase_events.size() == 1 and str(first_phase_events[0].get("boss_id", "")) == "elder_hollow", "Phase event carries the boss identity")
	check(first_phase_events.size() == 1 and int(first_phase_events[0].get("phase_index", -1)) == 0 and int(first_phase_events[0].get("phase_number", -1)) == 2, "First threshold is explicitly numbered as Phase 2")
	phase_boss.hp = 20.0
	var second_phase_events := phase_engine.skill_resolver.check_boss_phases(phase_boss)
	check(second_phase_events.size() == 1 and int(second_phase_events[0].get("phase_index", -1)) == 1 and int(second_phase_events[0].get("phase_number", -1)) == 3, "Second threshold is explicitly numbered as Phase 3")

	var engine := CombatEngine.new()
	engine.setup([defender], [opponent], 424242)
	engine.start()
	check(engine.current_actor() == defender, "Player begins first in the defend / end-turn test")
	var defend_events := engine.defend(engine.current_actor_index)
	check(not defend_events.is_empty() and defender.defending, "Defend is a real combat action")
	check(is_equal_approx(engine.incoming_multiplier(defender), 0.5), "Defend applies the existing 50% damage reduction")
	check(engine.current_actor() == opponent, "Defend advances the turn to the opponent")
	engine.advance_turn()
	check(engine.current_actor() == defender and not defender.defending, "Defend expires when the character's next turn begins")
	var end_turn_events := engine.end_turn(engine.current_actor_index)
	check(not end_turn_events.is_empty(), "End Turn is a real combat action")
	check(engine.current_actor() == opponent, "End Turn advances the turn to the opponent")

	# Matron Verdict interruption: actor motion is cancellable, arena timeline is not.
	var matron_battle_scene := load("res://scenes/ui/battlefield.tscn") as PackedScene
	var matron_battle := matron_battle_scene.instantiate() as Battlefield
	test_viewport.add_child(matron_battle)
	matron_battle.size = Vector2(1280, 720)
	var matron_ally := Combatant.new()
	matron_ally.uid = "verdict_interrupt_ally"
	matron_ally.def_id = "kael"
	matron_ally.display_name = "Kael"
	matron_ally.hp = 100.0
	matron_ally.max_hp = 100.0
	var matron_boss_unit := Combatant.new()
	matron_boss_unit.uid = "verdict_interrupt_boss"
	matron_boss_unit.def_id = "fallen_matron"
	matron_boss_unit.display_name = "Fallen Matron"
	matron_boss_unit.is_boss = true
	matron_boss_unit.hp = 1000.0
	matron_boss_unit.max_hp = 1000.0
	matron_battle.setup([matron_ally], [matron_boss_unit])
	await get_tree().process_frame
	var matron_boss := matron_battle.actor_for_uid("verdict_interrupt_boss")
	var matron_ally_actor := matron_battle.actor_for_uid("verdict_interrupt_ally")
	var matron_attack_component := matron_battle.get_node("MatronAttackPresentation") as MatronAttackPresentationComponent
	check(matron_boss != null and matron_ally_actor != null, "Matron interruption fixture creates both live battlefield actors")
	if matron_boss != null and matron_ally_actor != null:
		await _check_matron_attack_interrupt(matron_attack_component, matron_boss, matron_ally_actor, "corruption_bolt", "attack_sequence_tween")
		await _check_matron_attack_interrupt(matron_attack_component, matron_boss, matron_ally_actor, "soul_drain", "attack_sequence_tween")
		await _check_matron_attack_interrupt(matron_attack_component, matron_boss, matron_ally_actor, "shadow_lash", "attack_motion_tween")
		matron_attack_component.play_attack(matron_boss, matron_ally_actor, "corruption_bolt", false)
		await get_tree().create_timer(0.46).timeout
		var launched_orb: Node = null
		for effect in matron_attack_component.get_children():
			if effect.has_node("AnimationPlayer") and effect.get_node("AnimationPlayer").current_animation == "travel":
				launched_orb = effect
		check(launched_orb != null and matron_boss._attack_effects.is_empty(), "Matron corruption orb is released from caster cleanup after launch")
		matron_boss.take_hit()
		await get_tree().process_frame
		check(is_instance_valid(launched_orb) and not launched_orb.is_queued_for_deletion(), "Interrupting Matron does not erase an orb already in flight")
		await get_tree().create_timer(1.0).timeout
		await get_tree().process_frame
		check(not is_instance_valid(launched_orb), "Matron corruption orb completes its travel and self-cleans")
		matron_attack_component.play_attack(matron_boss, matron_ally_actor, "soul_drain", false)
		await get_tree().create_timer(0.46).timeout
		var launched_beam: Node = null
		for effect in matron_attack_component.get_children():
			if effect.has_node("AnimationPlayer") and effect.get_node("AnimationPlayer").current_animation == "drain":
				launched_beam = effect
		check(launched_beam != null and matron_boss._attack_effects.is_empty(), "Matron Soul Drain beam is released once its one-shot starts")
		matron_boss.take_hit()
		await get_tree().process_frame
		check(is_instance_valid(launched_beam) and not launched_beam.is_queued_for_deletion(), "Interrupting Matron preserves a Soul Drain beam already playing")
		await get_tree().create_timer(0.8).timeout
		check(matron_attack_component.get_child_count() == 0, "Soul Drain beam and burst finish and clean themselves up")
		matron_attack_component.play_attack(matron_boss, matron_ally_actor, "shadow_lash", false)
		await get_tree().create_timer(0.26).timeout
		var launched_lashes := 0
		for effect in matron_attack_component.get_children():
			if effect.has_node("AnimationPlayer") and effect.get_node("AnimationPlayer").current_animation == "fade":
				launched_lashes += 1
		check(launched_lashes == 3 and matron_boss._attack_effects.size() == 1, "Matron Shadow Lash releases its three strokes while retaining only the cancellable ground telegraph")
		matron_boss.take_hit()
		await get_tree().process_frame
		check(launched_lashes == 3 and matron_attack_component.get_child_count() == 3, "Interrupting Matron preserves all three launched Shadow Lash strokes")
		await get_tree().create_timer(0.7).timeout
		check(matron_attack_component.get_child_count() == 0, "Shadow Lash strokes finish their authored fades and self-clean")
		matron_attack_component.play_attack(matron_boss, matron_ally_actor, "matron_verdict", true)
		await get_tree().create_timer(0.12).timeout
		var verdict_overlay := matron_attack_component.get_child(0) as Control if matron_attack_component.get_child_count() > 0 else null
		var verdict_motion: Tween = matron_boss.get_meta("attack_motion_tween") if matron_boss.has_meta("attack_motion_tween") else null
		check(verdict_overlay != null and is_instance_valid(verdict_overlay), "Matron Verdict creates its arena-wide overlay")
		var verdict_sequence: Tween = matron_boss.get_meta("attack_sequence_tween") if matron_boss.has_meta("attack_sequence_tween") else null
		check(verdict_motion != null and verdict_motion.is_running(), "Matron Verdict registers its levitation as cancellable actor motion")
		check(verdict_sequence != null and verdict_sequence.is_running(), "Matron Verdict registers stage callbacks on an independent cancellable sequence channel")
		check(matron_boss._attack_effects.size() == 1 and matron_boss._attack_effects[0] == verdict_overlay, "Matron Verdict keeps its arena overlay owned until the attack completes or is interrupted")
		matron_boss.take_hit()
		check(verdict_motion != null and not verdict_motion.is_running(), "A hit interrupts Matron levitation")
		check(verdict_sequence != null and not verdict_sequence.is_running(), "A hit cancels pending Matron Verdict stage callbacks")
		await get_tree().process_frame
		check(matron_boss._attack_effects.is_empty(), "Matron interruption leaves no pending caster-owned Verdict effects")
		check(matron_boss.position.is_equal_approx(matron_boss.home_position), "Interrupted Matron levitation restores her canonical formation position")
		check(verdict_overlay == null or not is_instance_valid(verdict_overlay) or verdict_overlay.is_queued_for_deletion(), "Interrupting Matron immediately cancels and removes the arena-wide Verdict overlay")
		await get_tree().create_timer(2.2).timeout
		check(not is_instance_valid(verdict_overlay), "Matron Verdict overlay completes its authored exit and self-cleans")
		var kael_attack_component := matron_battle.get_node("KaelAttackPresentation") as KaelAttackPresentationComponent
		kael_attack_component.play_attack(matron_ally_actor, matron_boss, "ember_lance", false)
		await get_tree().create_timer(0.06).timeout
		var launched_spear: Node = null
		for effect in kael_attack_component.get_children():
			if effect.has_node("Shaft") and effect.has_node("Core"):
				launched_spear = effect
		check(launched_spear != null and matron_ally_actor._attack_effects.is_empty(), "Kael Ember Lance releases its travelling spear after launch")
		matron_ally_actor.take_hit()
		await get_tree().process_frame
		check(is_instance_valid(launched_spear) and not launched_spear.is_queued_for_deletion(), "Interrupting Kael preserves an Ember Lance spear already in flight")
		await get_tree().create_timer(0.42).timeout
		check(not is_instance_valid(launched_spear), "Kael Ember Lance spear reaches its endpoint and self-cleans")
	matron_battle.queue_free()
	# Drain deferred frees from transient AnimationPlayer effects before shutdown.
	for _cleanup_frame in range(3):
		await get_tree().process_frame
	print("BATTLE VISUAL ASSETS SMOKE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)




func _check_character_effect_interruption(actor: BattlefieldActor) -> void:
	actor.visual.play(ActorVisual.S_ATTACK)
	await get_tree().process_frame
	await get_tree().process_frame
	var effect_components: Array[Node] = []
	for child in actor.visual.get_children():
		if child.has_method("_clear_transient_particles"):
			effect_components.append(child)
	if effect_components.is_empty():
		return
	var particles_started := false
	for component in effect_components:
		for child in component.get_children():
			if child is CPUParticles2D and child.emitting:
				particles_started = true
	check(particles_started, "%s starts its authored attack particles" % actor.visual.character_id)
	actor.take_hit()
	await get_tree().process_frame
	await get_tree().process_frame
	var particles_remaining := false
	for component in effect_components:
		for child in component.get_children():
			if child is CPUParticles2D and child.emitting and child.name not in ["ImpactSparks", "AttackSparks", "SlashParticles"]:
				particles_remaining = true
	check(not particles_remaining, "%s clears attack particles when damage interrupts its action" % actor.visual.character_id)
	await get_tree().create_timer(0.36).timeout


func _check_matron_attack_interrupt(component: MatronAttackPresentationComponent, boss: BattlefieldActor, target: BattlefieldActor, skill_id: String, channel: String) -> void:
	component.play_attack(boss, target, skill_id, false)
	await get_tree().create_timer(0.06).timeout
	var attack_tween: Tween = boss.get_meta(channel) if boss.has_meta(channel) else null
	check(attack_tween != null and attack_tween.is_running(), "Matron %s registers its wind-up on the cancellable %s channel" % [skill_id, channel])
	boss.take_hit()
	check(attack_tween != null and not attack_tween.is_running(), "A hit interrupts the pending Matron %s wind-up" % skill_id)
	await get_tree().create_timer(0.9).timeout
	check(component.get_child_count() == 0, "Interrupted Matron %s leaves no delayed attack or warning effects" % skill_id)
func _check_live_background(scene: PackedScene, group_id: String, filename: String, host: SubViewport) -> void:
	var live_screen := scene.instantiate() as CombatScreen
	live_screen.group_id = group_id
	host.add_child(live_screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var full_art := live_screen.get_node_or_null("CombatScreenBackdrop/BattleArt") as TextureRect
	check(full_art != null and full_art.texture != null and full_art.texture.resource_path.ends_with(filename), "Live combat screen loads " + filename)
	var battlefield := live_screen.find_child("Battlefield", true, false) as Battlefield
	var stage_art := battlefield.get_node_or_null("ArenaArtBackdrop") as TextureRect if battlefield != null else null
	check(stage_art != null and stage_art.visible and stage_art.texture != null and stage_art.texture.resource_path.ends_with(filename), "Live battlefield displays " + filename)
	if group_id == "royal_road_ambush":
		check(live_screen.find_child("BossIntroBanner", true, false) == null, "Ordinary encounter does not display the boss-intro banner")
		var boss_rig := live_screen.get_node_or_null("BossPresentationRig")
		var phase_cue := boss_rig.get_node_or_null("PhaseCue") as Control if boss_rig != null else null
		check(phase_cue != null and not phase_cue.visible, "Ordinary encounter keeps the boss phase transition cue hidden")
	live_screen.queue_free()
	await get_tree().process_frame


