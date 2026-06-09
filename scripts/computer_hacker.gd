@tool
class_name ComputerHacker
extends Node3D

## Hacker terminal prop — the Kenney computer-wide console with a matrix-rain
## screen, an additive glow halo, orbiting glyph quads, and a green OmniLight.
##
## All animation is TIME-driven inside matrix_rain / hacker_glyph /
## wall_torch_halo shaders, so a placed terminal costs zero per-frame script
## time — this script only pushes the exported config into the materials and
## the OmniLight when a value changes. The light stays at constant energy
## (flicker lives in the shaders), matching the wall torch convention.

@export var accent_color: Color = Color(0.12, 1.0, 0.35):
	set(value):
		accent_color = value
		_apply()

@export_group("Light")
@export var light_enabled: bool = true:
	set(value):
		light_enabled = value
		_apply()
@export_range(0.0, 8.0, 0.05) var light_energy: float = 1.2:
	set(value):
		light_energy = value
		_apply()
@export_range(0.5, 12.0, 0.1) var light_range: float = 4.5:
	set(value):
		light_range = value
		_apply()

@export_group("Screen")
@export_range(0.0, 6.0, 0.05) var screen_energy: float = 2.2:
	set(value):
		screen_energy = value
		_apply()
@export_range(0.0, 4.0, 0.01) var fall_speed: float = 0.55:
	set(value):
		fall_speed = value
		_apply()
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.08:
	set(value):
		flicker_amount = value
		_apply()
@export_range(0.0, 20.0, 0.1) var flicker_speed: float = 6.0:
	set(value):
		flicker_speed = value
		_apply()

@export_group("Glyphs")
@export_range(0.0, 4.0, 0.05) var glyph_brightness: float = 1.6:
	set(value):
		glyph_brightness = value
		_apply()
@export_range(0.1, 3.0, 0.01) var orbit_radius: float = 0.9:
	set(value):
		orbit_radius = value
		_apply()
@export_range(-3.0, 3.0, 0.01) var orbit_speed: float = 0.5:
	set(value):
		orbit_speed = value
		_apply()

@export_group("Sound")
## Random data-crunch chatter from the terminal (runtime only).
@export var chatter_enabled: bool = true
@export_range(-40.0, 6.0, 0.5) var chatter_volume_db: float = -10.0
## Seconds between chatter bursts (random in [min, max]).
@export_range(0.5, 30.0, 0.5) var chatter_interval_min: float = 3.0
@export_range(0.5, 30.0, 0.5) var chatter_interval_max: float = 9.0

const _CHATTER_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/computerNoise_000.ogg"),
	preload("res://assets/audio/computerNoise_001.ogg"),
	preload("res://assets/audio/computerNoise_002.ogg"),
	preload("res://assets/audio/computerNoise_003.ogg"),
]

var _chatter_player: AudioStreamPlayer3D


func _ready() -> void:
	set_process(false)
	_apply()
	if not Engine.is_editor_hint() and chatter_enabled:
		_chatter_player = AudioStreamPlayer3D.new()
		_chatter_player.unit_size = 2.5
		_chatter_player.max_distance = 12.0
		_chatter_player.volume_db = chatter_volume_db
		add_child(_chatter_player)
		# Stagger the first burst so several terminals don't chirp in unison.
		_schedule_chatter(randf_range(0.5, chatter_interval_max))


func _schedule_chatter(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(_play_chatter)


func _play_chatter() -> void:
	if not is_inside_tree() or _chatter_player == null:
		return
	_chatter_player.stream = _CHATTER_SOUNDS[randi() % _CHATTER_SOUNDS.size()]
	_chatter_player.pitch_scale = randf_range(0.9, 1.15)
	_chatter_player.play()
	_schedule_chatter(randf_range(chatter_interval_min, chatter_interval_max))


func _apply() -> void:
	if not is_inside_tree():
		return
	var light := get_node_or_null(^"Light") as OmniLight3D
	if light:
		light.visible = light_enabled
		light.light_color = accent_color
		light.light_energy = light_energy
		light.omni_range = light_range
	var head := accent_color.lerp(Color.WHITE, 0.75)
	var screen := get_node_or_null(^"Screen") as MeshInstance3D
	if screen and screen.material_override is ShaderMaterial:
		var mat: ShaderMaterial = screen.material_override
		mat.set_shader_parameter(&"rain_color", Vector3(accent_color.r, accent_color.g, accent_color.b))
		mat.set_shader_parameter(&"head_color", Vector3(head.r, head.g, head.b))
		mat.set_shader_parameter(&"base_energy", screen_energy)
		mat.set_shader_parameter(&"fall_speed", fall_speed)
		mat.set_shader_parameter(&"flicker_amount", flicker_amount)
		mat.set_shader_parameter(&"flicker_speed", flicker_speed)
	var halo := get_node_or_null(^"Halo") as MeshInstance3D
	if halo and halo.material_override is ShaderMaterial:
		var mat: ShaderMaterial = halo.material_override
		mat.set_shader_parameter(&"accent_color", accent_color)
		mat.set_shader_parameter(&"flicker_amount", flicker_amount)
		mat.set_shader_parameter(&"flicker_speed", flicker_speed)
	var glyphs := get_node_or_null(^"Glyphs")
	if glyphs:
		var i := 0
		for child: Node in glyphs.get_children():
			var mi := child as MeshInstance3D
			if mi == null or not (mi.material_override is ShaderMaterial):
				continue
			var mat: ShaderMaterial = mi.material_override
			mat.set_shader_parameter(&"glyph_color", Vector3(accent_color.r, accent_color.g, accent_color.b))
			mat.set_shader_parameter(&"brightness", glyph_brightness)
			mat.set_shader_parameter(&"orbit_radius", orbit_radius)
			mat.set_shader_parameter(&"orbit_speed", orbit_speed)
			mat.set_shader_parameter(&"seed", float(i))
			i += 1
