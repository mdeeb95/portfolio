@tool
extends Node3D

## Anti-grav tractor beam VFX: additive beam cylinder + rising motes + ground glow,
## plus a real OmniLight3D so the beam lights nearby props and the player.
## The light energy and the shaders' intensity_mul are pulsed together so they stay in phase.
##
## In town_square: Scene → Instantiate Child Scene → tractor_beam.tscn, place at the
## platform top under the floating container, set beam_height to reach into it.

@export_group("Beam")
@export var beam_color: Color = Color(0.247, 0.839, 1.0): set = _set_beam_color
@export_range(0.5, 10.0, 0.05) var beam_height: float = 2.1: set = _set_beam_height
@export_range(0.05, 3.0, 0.01) var top_radius: float = 0.55: set = _set_top_radius
@export_range(0.05, 3.0, 0.01) var bottom_radius: float = 0.38: set = _set_bottom_radius
@export_range(0.0, 4.0, 0.05) var beam_brightness: float = 2.0: set = _set_beam_brightness

@export_group("Light")
@export_range(0.0, 16.0, 0.1) var light_energy: float = 1.6: set = _set_light_energy
@export_range(0.5, 20.0, 0.1) var light_range: float = 5.5: set = _set_light_range

@export_group("Pulse")
@export_range(0.0, 8.0, 0.05) var pulse_speed: float = 1.4
@export_range(0.0, 1.0, 0.01) var pulse_amount: float = 0.18
## Animate the pulse while editing the scene (no F5 required).
@export var preview_in_editor: bool = true

@onready var _beam_mesh: MeshInstance3D = $BeamMesh
@onready var _ground_glow: MeshInstance3D = $GroundGlow
@onready var _motes: CPUParticles3D = $Motes
@onready var _light: OmniLight3D = $BeamLight

var _time: float = 0.0
var _hold_mul: float = 1.0
var _hold_target: float = 1.0
var _burst: float = 0.0


func _ready() -> void:
	_apply_params()


## Dim the beam while it has nothing to hold (a FloatingProp got knocked off).
func set_held(held: bool) -> void:
	_hold_target = 1.0 if held else 0.45


## Brief brightness flash (e.g. when a FloatingProp snaps back into the beam).
func pulse_burst(strength: float = 1.8) -> void:
	_burst = strength


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	_time += delta
	var pulse: float = 1.0 + pulse_amount * (
		sin(_time * pulse_speed * TAU) * 0.7 + sin(_time * pulse_speed * 2.3 * TAU) * 0.3)
	_hold_mul = lerpf(_hold_mul, _hold_target, minf(1.0, 4.0 * delta))
	_burst = maxf(0.0, _burst - 4.0 * delta)
	var mul: float = pulse * _hold_mul * (1.0 + _burst)
	if _light:
		_light.light_energy = light_energy * mul
	_set_shader_param_both("intensity_mul", mul)


func _apply_params() -> void:
	if _beam_mesh == null:
		return
	var cylinder := _beam_mesh.mesh as CylinderMesh
	if cylinder:
		cylinder.height = beam_height
		cylinder.top_radius = top_radius
		cylinder.bottom_radius = bottom_radius
	_beam_mesh.position.y = beam_height * 0.5
	var beam_mat := _beam_mesh.material_override as ShaderMaterial
	if beam_mat:
		beam_mat.set_shader_parameter("beam_color", beam_color)
		beam_mat.set_shader_parameter("beam_height", beam_height)
		beam_mat.set_shader_parameter("brightness", beam_brightness)
	var glow_mat := _ground_glow.material_override as ShaderMaterial if _ground_glow else null
	if glow_mat:
		glow_mat.set_shader_parameter("beam_color", beam_color)
	if _motes:
		_motes.color = Color(beam_color, 1.0)
		_motes.emission_ring_height = 0.1
		var velocity_span: float = maxf(0.1, beam_height * 0.55)
		_motes.initial_velocity_min = velocity_span * 0.65
		_motes.initial_velocity_max = velocity_span
		_motes.lifetime = beam_height / maxf(0.2, velocity_span * 0.8)
	if _light:
		_light.position.y = beam_height * 0.45
		_light.light_color = beam_color
		_light.light_energy = light_energy
		_light.omni_range = light_range


func _set_shader_param_both(param: String, value: Variant) -> void:
	if _beam_mesh and _beam_mesh.material_override is ShaderMaterial:
		(_beam_mesh.material_override as ShaderMaterial).set_shader_parameter(param, value)
	if _ground_glow and _ground_glow.material_override is ShaderMaterial:
		(_ground_glow.material_override as ShaderMaterial).set_shader_parameter(param, value)


func _set_beam_color(value: Color) -> void:
	beam_color = value
	_apply_params()


func _set_beam_height(value: float) -> void:
	beam_height = value
	_apply_params()


func _set_top_radius(value: float) -> void:
	top_radius = value
	_apply_params()


func _set_bottom_radius(value: float) -> void:
	bottom_radius = value
	_apply_params()


func _set_beam_brightness(value: float) -> void:
	beam_brightness = value
	_apply_params()


func _set_light_energy(value: float) -> void:
	light_energy = value
	_apply_params()


func _set_light_range(value: float) -> void:
	light_range = value
	_apply_params()
