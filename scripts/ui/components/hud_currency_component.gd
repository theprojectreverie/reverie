class_name HUDCurrencyComponent
extends Node
## Owns the HUD wallet and binds the hand-authored currency icon assets.

var hud: HUD

const ICONS := {
	"gold": "res://assets/ui/currencies/gold.png",
	"crystals": "res://assets/ui/currencies/summoning_crystals.png",
	"ancient_coins": "res://assets/ui/currencies/ancient_coins.png",
	"gems": "res://assets/ui/currencies/gems.png",
	"guild_tokens": "res://assets/ui/currencies/guild_tokens.png",
	"event_tokens": "res://assets/ui/currencies/event_tokens.png",
}
const TINTS := {
	"gold": UITheme.GOLD,
	"crystals": UITheme.TEAL,
	"ancient_coins": Color("#d9ff9f"),
	"gems": UITheme.VIOLET,
	"guild_tokens": Color("#83c9e8"),
	"event_tokens": Color("#f18caa"),
}

func bind(owner: HUD) -> void:
	hud = owner

func refresh_currency() -> void:
	if hud == null or hud._currency_box == null:
		return
	UIFactory.clear(hud._currency_box)
	for currency_id in ICONS:
		var amount: int = GameState.inventory_domain.currency(currency_id)
		if currency_id in ["ancient_coins", "gems", "guild_tokens", "event_tokens"] and amount <= 0:
			continue
		_add_currency_icon_chip(currency_id, amount)

## Backwards-compatible presentation entry point used by HUD callers.
func add_currency_chip(value_text: String, tint: Color) -> void:
	var chip := _create_chip(value_text, tint)
	var dot := chip.get_node("Content/Dot") as TextureRect
	dot.modulate = tint
	hud._currency_box.add_child(chip)

func _add_currency_icon_chip(currency_id: String, amount: int) -> void:
	var tint: Color = TINTS.get(currency_id, UITheme.TEXT)
	var value_text := UIFactory.number(amount)
	var chip := _create_chip(value_text, tint)
	var icon := chip.get_node("Content/Dot") as TextureRect
	var texture_path := str(ICONS.get(currency_id, ""))
	if ResourceLoader.exists(texture_path):
		icon.texture = load(texture_path) as Texture2D
	hud._currency_box.add_child(chip)

func _create_chip(value_text: String, tint: Color) -> PanelContainer:
	var chip := HUD.CURRENCY_CHIP_SCENE.instantiate() as PanelContainer
	var value_label := chip.get_node("Content/ValueLabel") as Label
	value_label.text = value_text
	value_label.add_theme_color_override("font_color", tint)
	var style := chip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.10)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.45)
	chip.add_theme_stylebox_override("panel", style)
	return chip
