extends Node2D
## Authored bridge deck profile. Ground-plane coordinates remain authoritative.
## Only the actor presentation rises, so save positions, networking and collision stay planar.
@onready var start: Marker2D = $DeckStart
@onready var finish: Marker2D = $DeckEnd
const PROFILE := [Vector2(0.0, 0.0), Vector2(0.12, 25.0), Vector2(0.26, 42.0), Vector2(0.42, 51.0), Vector2(0.56, 49.0), Vector2(0.72, 35.0), Vector2(0.86, 18.0), Vector2(1.0, 0.0)]
var _active: Dictionary = {}
func _ready() -> void:
 process_physics_priority = 20
 add_to_group("willow_bridge_surface")
func is_on_deck(point: Vector2) -> bool:
 var p := to_local(point)
 var t := (p.x - start.position.x) / (finish.position.x - start.position.x)
 return t >= 0.0 and t <= 1.0 and absf(p.y - lerpf(start.position.y, finish.position.y, t)) <= 41.0
func elevation_at(point: Vector2) -> float:
 if not is_on_deck(point): return 0.0
 var t := (to_local(point).x - start.position.x) / (finish.position.x - start.position.x)
 for i in range(PROFILE.size()-1):
  var a: Vector2 = PROFILE[i]
  var b: Vector2 = PROFILE[i+1]
  if t <= b.x:
   return lerpf(a.y, b.y, (t-a.x)/(b.x-a.x))
 return 0.0
func _physics_process(_delta: float) -> void:
 var player := get_tree().get_first_node_in_group("player") as Node2D
 if is_instance_valid(player): _apply(player)
func _process(_delta: float) -> void:
 for id in _active.keys():
  if not is_instance_id_valid(id): _active.erase(id)
 for actor in get_tree().get_nodes_in_group("bridge_remote_avatar"):
  if actor is Node2D: _apply(actor)
func _apply(actor: Node2D) -> void:
 var id := actor.get_instance_id()
 var on_deck := is_on_deck(actor.global_position)
 if not on_deck and not _active.has(id): return
 var lift := elevation_at(actor.global_position)
 if on_deck and not _active.has(id):
  var originals: Dictionary = {}
  for key in ["ActorVisual", "NameLabel", "TitleLabel", "PersonalGlow", "StatusAnchor", "HealthDisplayAnchor"]:
   var n := actor.get_node_or_null(key) as CanvasItem
   if n is Node2D or n is Control: originals[key] = n.position
  _active[id] = originals
 var bases: Dictionary = _active[id]
 for key in bases:
  var n := actor.get_node_or_null(key) as CanvasItem
  if n is Node2D or n is Control: n.position = bases[key] - Vector2(0, lift)
 actor.set_meta("bridge_elevation", lift)
 if not on_deck:
  _active.erase(id)
  actor.remove_meta("bridge_elevation")
