class_name GenericAttackPresentationComponent
extends Control
## Owns ordinary unit lunge, strike-trail and impact-slash choreography.
## Character-specific moves are delegated to their own presentation components.

var battlefield: Battlefield


func bind(owner: Battlefield) -> void:
	battlefield = owner
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play_attack(attacker: BattlefieldActor, target: BattlefieldActor, element: String = "neutral", skill_id: String = "", ultimate: bool = false) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var origin: Vector2 = attacker.home_position
	var target_home := target.home_position if target != null and is_instance_valid(target) else origin + Vector2.RIGHT * 150.0
	var direction := Vector2.RIGHT
	if target != null and is_instance_valid(target):
		direction = (target_home - origin).normalized()
	attacker.face(direction)
	var is_gerald_skill := attacker.visual != null and attacker.visual.character_id == "gerald" and skill_id.to_lower() in ["blade_wave", "guardian_aura", "ground_eruption"]
	if attacker.unit != null and attacker.unit.def_id in ["rose_slime", "crownling"]:
		attacker.play_attack()
	elif is_gerald_skill:
		# Gerald owns authored per-skill FX variants; select them before the CAST one-shot starts.
		attacker.visual.play_skill(skill_id)
	elif not skill_id.is_empty() or ultimate:
		# Kael has a dedicated choreography component; Lilith and other heroes use
		# their own identity-layer cast signature for ordinary skill presentations.
		if attacker.visual != null:
			attacker.visual.play_cast()
	else:
		attacker.play_attack()
	var pose_player := attacker.get_node_or_null("BattlePoseAnimationPlayer") as AnimationPlayer
	if pose_player != null:
		var pose_name := "battle_cast" if not skill_id.is_empty() or ultimate else "battle_basic"
		if attacker.visual != null:
			match attacker.visual.character_id:
				"lilith":
					pose_name = "lilith_cast" if not skill_id.is_empty() or ultimate else "lilith_attack"
				"gerald":
					pose_name = "gerald_cast" if not skill_id.is_empty() or ultimate else "gerald_attack"
		if pose_player.has_animation(pose_name):
			pose_player.play(pose_name)

# Attackers travel toward the selected enemy, stopping just outside its
# silhouette; the effect then lands on the enemy's upper body.
	var reach := origin
	var impact_point := origin + direction * 42.0
	if target != null and is_instance_valid(target):
		var distance: float = origin.distance_to(target_home)
		# Close the full gap and stop just outside the boss silhouette. A short
		# percentage lunge leaves the attacker stranded mid-arena and reads as
		# attacking another party member instead of the selected enemy.
		var safe_gap := 118.0 if target.unit != null and target.unit.is_boss else 48.0
		reach = target_home - direction * minf(safe_gap, maxf(28.0, distance * 0.16))
		# Aim the visible hit at the Matron's torso, not at the ground between units.
		impact_point = target_home + (Vector2(-14.0, -88.0) if target.unit != null and target.unit.def_id == "fallen_matron" else Vector2(0, -28.0))
	var tween := create_tween()
	attacker.track_attack_motion(tween)
	tween.tween_property(attacker, "position", origin - direction * 18.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(attacker, "position", reach, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if target != null and is_instance_valid(target):
			_spawn_attack_trail(attacker, origin + Vector2(0, -42.0), impact_point, element)
			_spawn_slash(attacker, impact_point, direction, element, 1.35 if ultimate else 1.0)
			# Recoil is an editor-authored pose clip on the reusable actor scene;
			# gameplay position remains stable and cannot drift between turns.
			var hit_pose := target.get_node_or_null("BattlePoseAnimationPlayer") as AnimationPlayer
			if hit_pose != null and hit_pose.has_animation("battle_hit"):
				hit_pose.play("battle_hit")
			else:
				var boss_pose := target.get_node_or_null("AnimationPlayer") as AnimationPlayer
				if boss_pose != null and boss_pose.has_animation("boss_hit"):
					boss_pose.play("boss_hit")
		else:
			_spawn_slash(attacker, attacker.position + direction * 24.0, direction, element, 0.72))
	# Reconcile to the authored slot, not the lunge's starting point. This
	# prevents small layout changes or a partially interrupted previous move
	# from accumulating battlefield drift across successive turns.
	tween.tween_property(attacker, "position", attacker.home_position, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A visible strike trail connects the attacker to the actual target.
## It makes the hit direction unambiguous, especially against large bosses.
func _spawn_attack_trail(owner: BattlefieldActor, from: Vector2, to: Vector2, element: String) -> void:
	var color := UITheme.element_color(element)
	if color == UITheme.TEXT_DIM:
		color = Color(0.88, 0.9, 1.0)
	var projectile := preload("res://scenes/ui/combat/components/projectile_bolt.tscn").instantiate() as Node2D
	add_child(projectile)
	owner.track_attack_effect(projectile)
	projectile.call("launch", from + Vector2(0, -38), to, color, 0.26)
	owner.release_attack_effect(projectile)


## Reusable, scene-authored impact flourish at the target's actual position.
func _spawn_slash(owner: BattlefieldActor, pos: Vector2, direction: Vector2, element: String, strength: float = 1.0) -> void:
	var color := UITheme.element_color(element)
	if color == UITheme.TEXT_DIM:
		color = Color(0.92, 0.92, 0.98)
	var impact := preload("res://scenes/ui/combat/components/battle_hit_effect.tscn").instantiate() as Node2D
	impact.position = pos
	impact.z_index = 36
	add_child(impact)
	owner.track_attack_effect(impact)
	impact.call("play_impact", direction, color, strength)
	owner.release_attack_effect(impact)
	if battlefield != null:
		battlefield.spawn_attack_elemental_burst(owner, pos, element)
