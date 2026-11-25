class_name ForestWindController
extends Node
## Shared, low-cost wind field for every foliage sprite in one forest scene.

@export_range(0.0, 8.0, 0.1) var base_strength: float = 2.4
@export_range(0.0, 4.0, 0.05) var base_speed: float = 1.15
var wind_material: ShaderMaterial
@export_range(0.0, 2.0, 0.01) var wind_intensity: float = 1.0:
	set(value):
		wind_intensity = clampf(value, 0.0, 2.0)
		_apply_wind()


func _ready() -> void:
	wind_material = ShaderMaterial.new()
	wind_material.shader = load("res://resources/shaders/wind_sway.gdshader") as Shader
	_apply_wind()


func set_wind_intensity(value: float) -> void:
	wind_intensity = value


func _apply_wind() -> void:
	if wind_material == null:
		return
	wind_material.set_shader_parameter("sway_strength", base_strength * wind_intensity)
	wind_material.set_shader_parameter("sway_speed", base_speed * lerpf(0.55, 1.0, wind_intensity))
