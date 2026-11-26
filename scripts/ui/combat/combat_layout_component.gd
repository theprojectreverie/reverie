class_name CombatLayoutComponent
extends Node
## Binds authored combat presentation and configures combat HUD styling.


var screen


func bind(owner_screen) -> void:
	screen = owner_screen


func build() -> void:
	if screen == null:
		return
	if screen.get_node_or_null("CombatScreenBackdrop") == null:
		push_error("CombatScreen requires its authored backdrop scene.")
		return
	if screen.get_node_or_null("CombatScreenLayout") == null:
		push_error("CombatScreen requires its authored layout scene.")
		return
	build_layout()

func build_background() -> void:
	if screen != null and screen.get_node_or_null("CombatScreenBackdrop") == null:
		push_error("CombatScreenBackdrop must be authored in combat_screen.tscn.")


func build_layout() -> void:
	# Use the same encounter-selected artwork behind the complete battle HUD
	# and inside the battlefield stage.
	var battle_art := screen.get_node_or_null("CombatScreenBackdrop/BattleArt") as TextureRect
	if battle_art != null:
		var battle_art_path := BattlefieldLayoutComponent.battle_background_path_for_group(screen.group_id)
		var selected_art := load(battle_art_path) as Texture2D
		if selected_art != null:
			battle_art.texture = selected_art
	# Bind only the static layout authored in combat_screen_layout.tscn.
	var layout := screen.get_node_or_null("CombatScreenLayout") as Control
	if layout == null:
		push_error("CombatScreenLayout is not authored under CombatScreen.")
		return
	var root := layout.get_node("Root") as VBoxContainer
	var header := root.get_node("CombatHeader") as HBoxContainer
	screen._title_label = header.get_node("TitleLabel") as Label


	screen._round_label = header.get_node("RoundLabel") as Label


	# Keep the supplied control icons and frame them with authored battle-panel art.
	screen._auto_button = header.get_node("AutoButton") as Button
	var auto_icon := load("res://assets/ui/battle/controls/auto_icon_28.png") as Texture2D
	if auto_icon != null:
		screen._auto_button.icon = auto_icon
		screen._auto_button.expand_icon = false
	screen._auto_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	screen._auto_button.toggled.connect(screen._on_auto_toggled)
	screen._speed_button = header.get_node("SpeedButton") as Button
	var speed_icon := load("res://assets/ui/battle/controls/speed_icon_28.png") as Texture2D
	if speed_icon != null:
		screen._speed_button.icon = speed_icon
		screen._speed_button.expand_icon = false
	screen._speed_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	screen._speed_button.pressed.connect(screen._cycle_speed)
	var retreat := header.get_node("RetreatButton") as Button
	retreat.tooltip_text = "Leave this battle"
	retreat.pressed.connect(screen._confirm_retreat)

	screen._boss_bar_container = root.get_node("BossHealthPanel") as VBoxContainer
	screen._boss_name_label = screen._boss_bar_container.get_node("Panel/Content/BossName") as Label


	screen._boss_hp_bar = screen._boss_bar_container.get_node("Panel/Content/HealthBar") as ProgressBar
	screen._boss_phase_label = screen._boss_bar_container.get_node("Panel/Content/PhaseLabel") as Label



	var turn_panel := root.get_node("TurnOrderPanel") as PanelContainer

	turn_panel.custom_minimum_size = Vector2(533, 57)
	turn_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	turn_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var turn_caption := turn_panel.get_node("TurnRow/Caption") as Label

	turn_caption.visible = false
	screen._turn_box = turn_panel.get_node("TurnRow/TurnItems") as HBoxContainer
	screen._turn_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen._turn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	screen._turn_box.add_theme_constant_override("separation", 0)

	screen._battlefield = root.get_node("Battlefield") as Battlefield
	screen._battlefield.arena_id = screen.group_id
	# Bind arena visuals after the encounter ID is assigned; Battlefield is nested
	# below the authored layout and cannot discover CombatScreen via its parent.
	screen._battlefield._build_environment()
	if screen.group_id in ["gerald_boss_encounter", "cassien_encounter", "revienna_encounter"]:
		# One continuous backdrop; no second differently cropped image rectangle.
		screen._battlefield.get_node("ArenaArtBackdrop").hide()
		var vignette := screen.get_node_or_null("CombatScreenBackdrop/Vignette") as ColorRect
		if vignette != null:
			vignette.color = Color(0, 0, 0, 0.16)
		if screen.group_id in ["cassien_encounter", "revienna_encounter"]:
			# The wide ruin painting has its floor near its lower edge.
			# Frame that floor inside the playable stage, above the bottom HUD.
			var sky := screen.get_node_or_null("CombatScreenBackdrop/Sky") as TextureRect
			if sky != null:
				sky.show()
			if battle_art != null:
				battle_art.anchor_top = -0.16
				battle_art.anchor_bottom = 0.78

	screen._battlefield.actor_clicked.connect(screen._on_battlefield_actor_clicked)
	screen._battlefield.cinematic_impact.connect(screen._camera_shake)

	var bottom := root.get_node("CombatBottomHUD") as HBoxContainer
	# Blank authored frame: show the actual log caption.
	bottom.get_node("LogPanel/LogContent/LogCaption").visible = true

	screen._actor_label = bottom.get_node("ActiveInfoPanel/InfoContent/ActorLabel") as Label


	screen._hp_bar = bottom.get_node("ActiveInfoPanel/InfoContent/HPBar") as ProgressBar
	screen._energy_bar = bottom.get_node("ActiveInfoPanel/InfoContent/EnergyBar") as ProgressBar
	screen._status_label = bottom.get_node("ActiveInfoPanel/InfoContent/StatusLabel") as Label



	var roster_caption := bottom.get_node("RosterPanel/RosterContent/RosterCaption") as Label


	screen._roster_box = bottom.get_node("RosterPanel/RosterContent/RosterItems") as VBoxContainer

	screen._skills_box = bottom.get_node("SkillsPanel/SkillsContent/SkillItems") as HFlowContainer
	screen._hint_label = bottom.get_node("SkillsPanel/SkillsContent/HintLabel") as Label



	var log_caption := bottom.get_node("LogPanel/LogContent/LogCaption") as Label


	screen._log_label = bottom.get_node("LogPanel/LogContent/LogText") as RichTextLabel


