extends Button
signal character_changed(id: String)
signal gallery_visibility_changed(open: bool)
## Account-owned menu appearance; independent of profile picture and party.
const ART := {
 "default": "res://assets/characters/ravienna/main_menu_illustration.png",
 "ravienna": "res://assets/characters/ravienna/main_menu_illustration.png",
 "kael_crouching": "res://assets/ui/menu_characters/02_kael_crouching.png",
 "kael_seated": "res://assets/ui/menu_characters/03_kael_seated.png",
 "kael_standing": "res://assets/ui/menu_characters/04_kael_standing.png",
 "mirene": "res://assets/ui/menu_characters/01_crimson_jester.png",
 "crimson_witch": "res://assets/ui/menu_characters/05_lily_witch.png",
 "elathra": "res://assets/ui/menu_characters/06_elathra.png"
}
const LABELS := {"default":"Ravienna (default)","ravienna":"Ravienna","kael_crouching":"Kael - Crouching","kael_seated":"Kael - Seated","kael_standing":"Kael - Standing","mirene":"Miréne","crimson_witch":"Elathra","elathra":"Companion"}
const TILE := preload("res://scenes/ui/components/menu_character_gallery_tile.tscn")
# Normalized artwork bounds: keep faces below currencies and feet above navigation.
const FRAMES := {
 "default": Rect2(0.53,0.105,0.47,0.86),
 "ravienna": Rect2(0.53,0.105,0.47,0.86),
 "kael_crouching": Rect2(0.53,0.13,0.45,0.74),
 "kael_seated": Rect2(0.52,0.13,0.46,0.74),
 "kael_standing": Rect2(0.57,0.13,0.39,0.74),
 "mirene": Rect2(0.53,0.13,0.45,0.74),
 "crimson_witch": Rect2(0.54,0.13,0.44,0.74),
 "elathra": Rect2(0.52,0.13,0.46,0.74)
}
var _request: HTTPRequest
var _owner := ""
var _saved := "default"
var _pending := ""
var _retry_at := 0
var _loaded := false
var _refresh_requested := false
var _choices: Array = []
var _fade: Tween
var _displayed := ""
var _companion_name := ""
@onready var artwork: TextureRect = $"../RaviennaPortrait"
@onready var gallery: Control = $"../MenuCharacterGallery"
@onready var grid: GridContainer = gallery.get_node("Panel/Margin/Content/Scroll/Grid")
@onready var scroll: ScrollContainer = gallery.get_node("Panel/Margin/Content/Scroll")
@onready var status: Label = gallery.get_node("Panel/Margin/Content/Status")

func _ready() -> void:
 _request = HTTPRequest.new()
 _request.timeout = 10.0
 add_child(_request)
 _request.request_completed.connect(_completed)
 pressed.connect(_open_gallery)
 gallery.get_node("Panel/Margin/Content/Header/Close").pressed.connect(_close_gallery)
 scroll.resized.connect(_resize_grid)
 AuthGateway.authentication_changed.connect(_identity_changed)
 AuthGateway.account_roster_changed.connect(_roster_changed)
 GraphicsSettings.quality_changed.connect(_on_quality_changed)
 _identity_changed(AuthGateway.is_authenticated(), AuthGateway.current_player())

func _identity_changed(signed_in: bool, player: Dictionary) -> void:
 var next_owner := str(player.get("id","")) if signed_in else ""
 if not next_owner.is_empty() and next_owner == _owner:
  _roster_changed()
  return
 _request.cancel_request()
 _refresh_requested = false
 _owner = str(player.get("id","")) if signed_in else ""
 _saved = "default"
 _pending = ""
 _loaded = false
 _choices.clear()
 _companion_name = ""
 _retry_at = 0
 _close_gallery()
 disabled = true
 text = "Change character"
 _apply_art(_saved,false)
 tooltip_text = "Sign in to customize your main menu" if _owner.is_empty() else "Loading menu characters..."
 if not _owner.is_empty():_load_choices()

func _process(_delta: float) -> void:
 if not _owner.is_empty() and (not _loaded or _refresh_requested) and _pending.is_empty() and Time.get_ticks_msec() >= _retry_at:
  _load_choices()

func _roster_changed() -> void:
 if _owner.is_empty():return
 # Roster events arriving during a save/load must not be discarded.
 _refresh_requested = true
 _retry_at = 0

func _load_choices() -> void:
 if _send("load"):_refresh_requested = false

func _open_gallery() -> void:
 if not _loaded or not _pending.is_empty():return
 gallery.show()
 gallery_visibility_changed.emit(true)
 if not _owner.is_empty():_roster_changed()
 _render_gallery()
 _resize_grid()

func _unhandled_input(event: InputEvent) -> void:
 if gallery.visible and event.is_action_pressed("ui_cancel"):
  _close_gallery()
  get_viewport().set_input_as_handled()

func _close_gallery() -> void:
 var was_open := gallery.visible
 gallery.hide()
 if was_open:gallery_visibility_changed.emit(false)
 for child in grid.get_children():
  grid.remove_child(child)
  child.queue_free()

func _resize_grid() -> void:
 grid.columns = clampi(int((scroll.size.x - 16.0) / 160.0),1,4)

func _render_gallery() -> void:
 if not gallery.visible:return
 for child in grid.get_children():
  grid.remove_child(child)
  child.queue_free()
 for id in ART:
  # Default and owned Ravienna use the exact same artwork; show one card.
  if id == "ravienna":continue
  var tile: Button = TILE.instantiate()
  tile.name = id
  grid.add_child(tile)
  var unlocked := _choices.has(id)
  var equipped: bool = id == _saved or (id == "default" and _saved == "ravienna")
  tile.text = ""
  tile.tooltip_text = "Win the Companion friendly spar to unlock" if id=="elathra" and not unlocked else ("Obtain this character to unlock" if not unlocked else _label_for(str(id)))
  tile.disabled = not unlocked or not _pending.is_empty() or equipped
  if equipped:tile.add_theme_stylebox_override("disabled",tile.get_theme_stylebox("hover"))
  tile.get_node("Preview").texture = load(_derivative_path(str(id),"thumbs")) as Texture2D
  tile.get_node("Preview").modulate = Color.WHITE if unlocked else Color(0.45,0.45,0.45,0.8)
  tile.get_node("Caption").text = ("Ravienna" if id=="default" else _label_for(str(id))) + ("\nEquipped" if equipped else (("\nWin friendly spar" if id=="elathra" else "\nLocked") if not unlocked else "\nSelect"))
  tile.get_node("Caption").modulate = Color("#e8c883") if equipped else Color.WHITE
  tile.pressed.connect(_choose.bind(str(id)))
 status.text = "Saving..." if not _pending.is_empty() else "Choose an unlocked character or pose."

func _choose(id: String) -> void:
 if not _loaded or not _pending.is_empty() or not _choices.has(id) or id == _saved:return
 if _send(id):
  for child in grid.get_children():
   child.disabled = true
  status.text = "Saving..."

func _send(operation: String) -> bool:
 if _owner.is_empty() or not _pending.is_empty() or not AuthGateway.access_token_ready_for_connection():return false
 _pending = operation
 disabled = true
 var loading := operation == "load"
 var error := _request.request(AuthGateway.api_base_url+"/v1/social/menu-character",PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"]),HTTPClient.METHOD_GET if loading else HTTPClient.METHOD_POST,"" if loading else JSON.stringify({"character":operation}))
 if error != OK:
  _pending = ""
  _retry_at = Time.get_ticks_msec()+3000
  disabled = not _loaded
  return false
 return true

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
 var operation := _pending
 _pending = ""
 if _owner.is_empty() or _owner != str(AuthGateway.current_player().get("id","")):return
 var data: Variant = JSON.parse_string(body.get_string_from_utf8())
 if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or str(data.get("playerId","")) != _owner:
  _retry_at = Time.get_ticks_msec()+3000
  disabled = not _loaded
  _render_gallery()
  if operation == "load":_refresh_requested = true
  if operation != "load":
   status.text = "Could not save. Please try again."
   EventBus.toast_requested.emit("Menu character could not be saved. Try again.")
  return
 _companion_name = str(data.get("companionName",""))
 _saved = str(data.get("character","default"))
 _choices = data.get("choices",[]).duplicate()
 _apply_art(_saved,operation != "load")
 _loaded = true
 disabled = false
 tooltip_text = "Change your main menu character"
 if operation != "load":
  _close_gallery()
  EventBus.toast_requested.emit("Main menu character saved.")
 else:_render_gallery()

func _label_for(id: String) -> String:
 if id=="elathra" and not _companion_name.is_empty():return _companion_name
 return str(LABELS.get(id,"Change character"))

func _derivative_path(id: String, variant: String) -> String:
 var source := str(ART.get(id,ART["default"]))
 var filename := "ravienna.png" if id in ["default","ravienna"] else source.get_file()
 return "res://assets/ui/menu_characters/%s/%s" % [variant,filename]

func _art_path(id: String) -> String:
 return _derivative_path(id,"battery") if GraphicsSettings.quality == 0 else str(ART.get(id,ART["default"]))

func _on_quality_changed() -> void:
 if not _displayed.is_empty():_apply_art(_displayed,false)

func _apply_art(id: String, animate: bool = false) -> void:
 var path := _art_path(id)
 var texture := load(path) as Texture2D
 if texture == null:return
 if _fade != null and _fade.is_valid():_fade.kill()
 var frame: Rect2 = FRAMES.get(id,FRAMES["default"])
 artwork.anchor_left = frame.position.x
 artwork.anchor_top = frame.position.y
 artwork.anchor_right = frame.end.x
 artwork.anchor_bottom = frame.end.y
 artwork.texture = texture
 if animate and id != _displayed and GraphicsSettings.quality != 0:
  artwork.modulate.a = 0.0
  _fade = create_tween()
  _fade.tween_property(artwork,"modulate:a",1.0,0.24)
 else:artwork.modulate.a = 1.0
 var changed := _displayed != id
 _displayed = id
 text = _label_for(id) if not _owner.is_empty() else "Change character"
 if changed:character_changed.emit(id)