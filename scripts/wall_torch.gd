@tool
class_name WallTorch
extends Node3D

## Wall-mounted sci-fi light (plasma sconce / holo-flame / light bar).
##
## All animation is TIME-driven inside the wall_torch_*.gdshader materials, so a
## placed torch costs zero per-frame script time — this script only pushes the
## exported config into the materials and the OmniLight when a value changes.
##
## Mount on a wall with the prop's -Z against the wall surface (+Z faces the room).
## On web/mobile (GL Compatibility) at most 8 lights can touch one mesh — for dense
## runs of torches, leave some with light_enabled off; the emissive + halo still sell it.

@export var accent_color: Color = Color(0.247, 0.839, 1.0):
	set(value):
		accent_color = value
		_apply()

@export_group("Light")
@export var light_enabled: bool = true:
	set(value):
		light_enabled = value
		_apply()
@export_range(0.0, 8.0, 0.05) var light_energy: float = 1.3:
	set(value):
		light_energy = value
		_apply()
@export_range(0.5, 12.0, 0.1) var light_range: float = 4.5:
	set(value):
		light_range = value
		_apply()

@export_group("Flicker")
## 0 = steady. Drives the shaders only; the light stays at constant energy.
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.2:
	set(value):
		flicker_amount = value
		_apply()
@export_range(0.0, 20.0, 0.1) var flicker_speed: float = 6.0:
	set(value):
		flicker_speed = value
		_apply()


func _ready() -> void:
	set_process(false)
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var light := get_node_or_null(^"Light") as OmniLight3D
	if light:
		light.visible = light_enabled
		light.light_color = accent_color
		light.light_energy = light_energy
		light.omni_range = light_range
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"accent_color", accent_color)
		mat.set_shader_parameter(&"flicker_amount", flicker_amount)
		mat.set_shader_parameter(&"flicker_speed", flicker_speed)
	for particles: CPUParticles3D in find_children("*", "CPUParticles3D", true, false):
		particles.color = accent_color
