extends RefCounted

const SCENES = {
    "StandaloneVillage": "res://scenes/world/village/imported_village/village_playable.tscn",
    "StandaloneZone01": "res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn",
    "StandaloneZone02": "res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn",
    "StandaloneZone03": "res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn",
    "StandaloneZone04": "res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn",
    "StandaloneZone05": "res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn",
    "StandaloneZone06": "res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn",
}

static func resume_scene() -> String:
    var checkpoint: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
    return str(SCENES.get(str(checkpoint.get("zone", "")), SCENES["StandaloneZone01"]))

static func safe_position(zone: Node2D, point: Vector2) -> bool:
    if not point.is_finite():
        return false
    var outline := zone.get_node_or_null("TerrainPerimeter/TerrainOutline") as CollisionPolygon2D
    if outline != null and not Geometry2D.is_point_in_polygon(outline.to_local(zone.to_global(point)), outline.polygon):
        return false
    if outline == null:
        var village_bounds := zone.get_node_or_null("Perimeter/Bounds") as CollisionPolygon2D
        if village_bounds != null and not Geometry2D.is_point_in_polygon(village_bounds.to_local(zone.to_global(point)), village_bounds.polygon):
            return false
        var garden_bounds := zone.get_node_or_null("GroundPerimeter") as StaticBody2D
        if garden_bounds != null and zone.name == &"StandaloneZone01":
            var points := PackedVector2Array()
            for edge in garden_bounds.get_children():
                if edge is CollisionShape2D and edge.shape is SegmentShape2D:
                    points.append(zone.to_local(edge.to_global(edge.shape.a)))
                    points.append(zone.to_local(edge.to_global(edge.shape.b)))
            if points.size() >= 3 and not Geometry2D.is_point_in_polygon(point, Geometry2D.convex_hull(points)):
                return false
    var transfers := zone.get_node_or_null("TransferPoints")
    if transfers != null:
        for marker in transfers.get_children():
            for child in marker.get_children():
                if child is Area2D and point.distance_to(zone.to_local(child.global_position)) < 150.0:
                    return false
    # These two diamond maps have an authored connector outside their main
    # tilemap. A checkpoint must be on terrain, including the connector tiles.
    if zone.name in [&"StandaloneZone04", &"StandaloneZone05"]:
        var ground := zone.get_node_or_null("Zone/GroundTiles/EditableTileMap") as TileMapLayer
        if ground != null:
            var world_point := zone.to_global(point)
            if ground.get_cell_source_id(ground.local_to_map(ground.to_local(world_point))) >= 0:
                return true
            for road in zone.get_children():
                if str(road.name).begins_with("EntryRoad") or str(road.name).begins_with("ExitRoad"):
                    var tiles := road.get_node_or_null("RoadTiles/EditableTileMap") as TileMapLayer
                    if tiles != null and tiles.get_cell_source_id(tiles.local_to_map(tiles.to_local(world_point))) >= 0:
                        return true
            return false
    return true

static func restore(zone: Node2D, fallback: Vector2, arrival: StringName) -> Vector2:
    if arrival != &"":
        return fallback
    var data: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
    if str(data.get("zone", "")) != str(zone.name):
        return fallback
    var point := Vector2(float(data.get("x", INF)), float(data.get("y", INF)))
    return point if safe_position(zone, point) else fallback

static func capture(zone: Node2D, player: CharacterBody2D, immediate: bool = false) -> void:
    if not is_instance_valid(player) or not SCENES.has(str(zone.name)):
        return
    if not bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
        return
    var point := player.position
    if not safe_position(zone, point):
        return
    var previous: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
    var changed := str(previous.get("zone", "")) != str(zone.name) or Vector2(float(previous.get("x", INF)), float(previous.get("y", INF))).distance_to(point) > 0.5
    if changed:
        GameState.quest_domain.flags["six_zone_checkpoint"] = {"zone": str(zone.name), "x": point.x, "y": point.y}
        GameState.session_domain.set_player_position(point)
    if changed or immediate:
        GameState.save_now()
