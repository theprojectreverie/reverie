class_name ActorPoseComponent
extends Node
## Owns sprite locomotion pose, secondary motion and legacy facing/walking reconciliation.

var visual: ActorVisual


func bind(owner_visual: ActorVisual) -> void:
	visual = owner_visual

func update_locomotion_pose(delta: float) -> void:
	if visual._sprite == null or not visual._sprite_active or visual._sprite.texture == null or visual.animator == null:
		return
	var state := visual.animator.state
	var locomotion := state == ActorVisual.S_WALK or state == ActorVisual.S_RUN
	var idle := state == ActorVisual.S_IDLE
	if visual.character_id == "kael":
		# Kael's editor-authored AnimationPlayer clips own all secondary body motion.
		return
	if visual.character_id != "gerald" and visual.character_id != "lilith" and visual.race != "Spirit":
		# Generic grounded actors use the reusable editor-authored locomotion
		# library. Do not write Sprite2D transforms from this runtime component.
		return
	if not locomotion and not idle:
		visual._sprite.position = Vector2.ZERO
		visual._sprite.rotation = 0.0
		visual._sprite.scale = Vector2.ONE * visual._base_visual_scale * visual.sprite_component.combat_clip_scale()
		return
	var phase := 0.0
	if locomotion:
		var count := float(maxi(1, visual.animator.frame_count()))
		var frame_progress := (float(visual.animator.frame) + visual.animator.elapsed * visual.animator.fps() * visual.animator.speed_scale) / count
		phase = frame_progress * TAU
	var bob := 0.0
	var sway := 0.0
	var squash := 0.0
	# Never carry a previous turn-pose rotation into the next locomotion
	# frame. Gerald changes visual.facing often; accumulating the small turn offset
	# made his entire sprite progressively spin around its origin.
	visual._sprite.rotation = 0.0
	if visual.character_id == "lilith" or visual.race == "Spirit":
		# Lilith's lower silhouette is spectral flame, not feet: keep her hovering.
		bob = sin(visual.anim_time * (3.0 if locomotion else 1.8)) * (2.5 if locomotion else 1.8)
		sway = sin(visual.anim_time * 1.65) * 0.8
		visual._sprite.rotation = sin(visual.anim_time * 1.25) * 0.018
	else:
		var cadence := 2.0 if locomotion else 1.0
		var contact := pow(maxf(0.0, cos(phase * cadence)), 8.0) if locomotion else 0.0
		var lift := absf(sin(phase * cadence)) if locomotion else 0.0
		if visual.character_id == "gerald":
			# Heavy guardian: compact rise, deliberate landing and a slow, weighty
			# idle breath. The tiny scale pulse expands from the grounded origin,
			# while the opposing lateral sway gives his long coat a soft secondary
			# motion without making an 8 m silhouette look weightless.
			var breath := sin(visual.anim_time * 1.45)
			bob = -1.45 * lift if locomotion else -0.42 * breath
			sway = sin(phase) * 0.65 if locomotion else sin(visual.anim_time * 0.92) * 0.42
			squash = 0.028 * contact
			if idle:
				visual._sprite.rotation = sin(visual.anim_time * 0.92) * 0.0025
		elif visual.character_id == "kael":
			# Kael: quick, light footwork with a more expressive idle breath.
			bob = -2.45 * lift if locomotion else sin(visual.anim_time * 2.15) * 0.78
			sway = sin(phase) * (1.2 if state == ActorVisual.S_RUN else 0.88) if locomotion else sin(visual.anim_time * 1.35) * 0.34
			squash = (0.042 if state == ActorVisual.S_RUN else 0.032) * contact
			visual._sprite.rotation = sin(visual.anim_time * 1.1) * 0.006 if idle else 0.0
		else:
			# Other grounded characters keep the restrained default motion.
			bob = -2.15 * lift
			sway = sin(phase) * 1.05 if locomotion else sin(visual.anim_time * 1.5) * 0.3
			squash = 0.035 * contact
			visual._sprite.rotation = 0.0
	var breath_scale := sin(visual.anim_time * 1.45) if visual.character_id == "gerald" and idle else 0.0
	var scale_x := visual._base_visual_scale * (1.0 + squash * 0.55 + breath_scale * 0.0015)
	var scale_y := visual._base_visual_scale * (1.0 - squash + breath_scale * 0.0035)
	visual._sprite.position = Vector2(sway, bob)
	visual._sprite.scale = Vector2(scale_x, scale_y)
	if visual._turn_pose_remaining > 0.0:
		visual._turn_pose_remaining = maxf(0.0, visual._turn_pose_remaining - delta)
		var turn_weight := sin(PI * (1.0 - visual._turn_pose_remaining / ActorVisual.TURN_POSE_DURATION))
		# Keep Gerald's turn cue subtle and bounded (rotation is reset each frame)
		# so he still shows a directional turn transition without progressive spin.
		var turn_deg := 1.6 if visual.character_id == "gerald" else 3.0
		visual._sprite.rotation += deg_to_rad(turn_deg) * visual._turn_pose_sign * turn_weight



## Backward compatibility: external writes to `visual.walking` / `visual.facing` are folded
## into the visual.animator here (rather than removing the vars). Only reacts on change
## edges and only touches pure locomotion states, so one-shots are never cut.

func reconcile_compat() -> void:
	if visual.walking != visual._last_walking:
		visual._last_walking = visual.walking
		if visual.walking:
			if visual.animator.state == ActorVisual.S_IDLE and visual.animator.is_looping():
				visual.animator.play(ActorVisual.S_WALK)
		elif visual.animator.state == ActorVisual.S_WALK or visual.animator.state == ActorVisual.S_RUN:
			visual.animator.play(ActorVisual.S_IDLE)
	if visual.facing != visual._last_facing:
		visual._last_facing = visual.facing
		if visual._sprite != null and visual._sprite_active:
			visual._sprite.flip_h = visual.facing < 0.0 and visual._mirrors_by_facing()


# ------------------------------------------------------------------ drawing

