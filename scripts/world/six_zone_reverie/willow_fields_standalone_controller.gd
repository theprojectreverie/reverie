extends Node2D

## Standalone six-zone preview controller: supplies a player and places it at the
## destination road's safe approach, rather than on top of its transfer trigger.
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
const TRANSFER_SCRIPT = preload("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")

const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
var checkpoint_player: CharacterBody2D
var checkpoint_elapsed := 0.0

func _ready() -> void:
    AudioDirector.sync_region_ambience("willow_fields")
    var player: CharacterBody2D = PLAYER_SCENE.instantiate()
    var arrival: StringName = TRANSFER_SCRIPT.pending_arrival
    TRANSFER_SCRIPT.pending_arrival = &""
    var marker: Marker2D = null
    # Only use a transfer marker when a real incoming zone was supplied.
    # A fresh standalone launch must begin at the authored central spawn.
    if arrival != &"":
        marker = get_node_or_null("TransferPoints/" + String(arrival)) as Marker2D
        if marker == null:
            marker = get_node_or_null("TransferPoints/ToPreviousZone") as Marker2D
        if marker == null:
            marker = get_node_or_null("TransferPoints/ToNextZone") as Marker2D
    var spawn_at := Vector2(0, 1804)

    if marker != null:
        # Place the arriving player away from the trigger to prevent bounce-back.
        spawn_at = marker.position + (Vector2(180, 80) if arrival == &"ToPreviousZone" else Vector2(-180, -80))
    player.position = CHECKPOINT.restore(self, spawn_at, arrival)
    add_child(player)
    checkpoint_player = player
    CHECKPOINT.capture(self, player, true)
    # Start at normal exploration scale, not the whole-map overview.
    # Leave Kael's visual size, collision, and movement completely unchanged.
    # The player camera follows his position and retains ordinary zoom controls.
    var player_camera := player.get_node_or_null("Camera2D") as Camera2D
    if player_camera != null:
        player_camera.call("set_base_zoom", 1.0)
        player_camera.make_current()



func _process(delta: float) -> void:
    checkpoint_elapsed += delta
    if checkpoint_elapsed >= 2.0:
        checkpoint_elapsed = 0.0
        CHECKPOINT.capture(self, checkpoint_player)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        CHECKPOINT.capture(self, checkpoint_player, true)
