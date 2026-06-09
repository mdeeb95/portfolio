@tool
class_name TurretScanner
extends Node3D

## Decorative turret built around Kenney's turret_double.fbx: the head sweeps
## to random yaw targets with smooth ease-in/out, angling up into the sky as
## it goes, pauses as if studying something, then picks a new heading —
## scanning for enemy ships. Instances desync via random start yaw, target,
## dwell, and sway phase.

@export_group("Scan")
## Full sweep arc centered on the head's rest yaw (220 = +-110 deg).
@export_range(10.0, 360.0, 1.0) var yaw_range_deg: float = 220.0
## Top turn speed (deg/s).
@export_range(5.0, 180.0, 0.5) var turn_speed_deg: float = 45.0
## How quickly the head speeds up and brakes (deg/s^2).
@export_range(10.0, 720.0, 1.0) var turn_accel_deg: float = 140.0
## Pause at each heading before picking the next (random in [min, max]).
@export_range(0.1, 10.0, 0.05) var dwell_min: float = 0.7
@export_range(0.1, 10.0, 0.05) var dwell_max: float = 2.4
## Upward tilt at each heading (random in [min, max]; barrels never aim below
## level). Pitch animates together with the yaw sweep.
@export_range(0.0, 60.0, 0.5) var pitch_min_deg: float = 4.0
@export_range(0.0, 60.0, 0.5) var pitch_max_deg: float = 30.0

@export_group("Idle Sway")
## Subtle constant wobble layered on top of the scan (0 = off).
@export_range(0.0, 10.0, 0.05) var idle_sway_deg: float = 1.0
@export_range(0.0, 5.0, 0.01) var idle_sway_speed: float = 0.6

@export_group("Sound")
## Servo-motor whir loudness at full sweep speed (dB). The whir fades with
## head speed, so it spins up, sweeps, and winds down without clicks.
@export_range(-40.0, 6.0, 0.5) var servo_volume_db: float = -14.0

@export_group("Editor Preview")
## Animate the head while editing the scene.
@export var preview_in_editor: bool = true

var _head: Node3D
var _rest_rotation: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _yaw_start: float = 0.0
var _target_yaw: float = 0.0
var _pitch: float = 0.0
var _pitch_start: float = 0.0
var _target_pitch: float = 0.0
var _speed: float = 0.0
var _dwell: float = 0.0
var _time: float = 0.0
var _servo: AudioStreamPlayer3D


func _ready() -> void:
	_find_head()
	if _head == null:
		push_warning("TurretScanner: no 'turret' head node under %s" % name)
		set_process(false)
		return
	_time = randf() * 100.0
	_yaw = _random_target_yaw()
	_yaw_start = _yaw
	_target_yaw = _random_target_yaw()
	_pitch = _random_target_pitch()
	_pitch_start = _pitch
	_target_pitch = _random_target_pitch()
	_dwell = randf() * dwell_max
	if not Engine.is_editor_hint():
		_setup_servo_sound()


func _setup_servo_sound() -> void:
	var stream := load("res://assets/audio/engineCircular_000.ogg") as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = true
	_servo = AudioStreamPlayer3D.new()
	_servo.stream = stream
	_servo.unit_size = 2.5
	_servo.max_distance = 14.0
	_servo.volume_db = -60.0
	# Child of the head so the whir tracks the moving muzzle.
	_head.add_child(_servo)
	_servo.play(randf() * stream.get_length())


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	# Reset the preview pose so head rotation never serializes into the scene.
	if what == NOTIFICATION_EDITOR_PRE_SAVE and is_instance_valid(_head):
		_head.rotation = _rest_rotation


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if not preview_in_editor:
			return
		if not is_instance_valid(_head):
			_find_head()
			if _head == null:
				return
	_time += delta
	var accel := deg_to_rad(turn_accel_deg)
	if _dwell > 0.0:
		_dwell -= delta
		_speed = move_toward(_speed, 0.0, accel * delta)
		if _dwell <= 0.0:
			_yaw_start = _yaw
			_pitch_start = _pitch
			_target_yaw = _random_target_yaw()
			_target_pitch = _random_target_pitch()
	else:
		# Speed cap shrinks near the target (ease-out); _speed ramps toward the
		# cap at turn_accel (ease-in).
		var remaining := absf(angle_difference(_yaw, _target_yaw))
		var desired := minf(deg_to_rad(turn_speed_deg), remaining * 2.5 + 0.02)
		_speed = move_toward(_speed, desired, accel * delta)
		_yaw = rotate_toward(_yaw, _target_yaw, _speed * delta)
		# Pitch keyed to the yaw sweep's eased progress so both arrive together.
		var total := absf(angle_difference(_yaw_start, _target_yaw))
		if total > 0.001:
			var progress := 1.0 - absf(angle_difference(_yaw, _target_yaw)) / total
			_pitch = lerpf(_pitch_start, _target_pitch, progress)
		else:
			_pitch = move_toward(_pitch, _target_pitch, deg_to_rad(turn_speed_deg) * delta)
		if is_equal_approx(_yaw, _target_yaw):
			_pitch = _target_pitch
			_dwell = randf_range(dwell_min, dwell_max)
	var sway := 0.0
	if idle_sway_deg > 0.0:
		sway = deg_to_rad(idle_sway_deg) * (
			sin(_time * idle_sway_speed * TAU) * 0.6
			+ sin(_time * idle_sway_speed * 2.7 * TAU) * 0.4)
	# Negative local X tilts the barrels skyward on this asset; Euler order is
	# YXZ, so the pitch axis follows the yaw like a real turret mount.
	_head.rotation = _rest_rotation + Vector3(_pitch, _yaw + sway, 0.0)
	if _servo:
		var speed_ratio := clampf(_speed / maxf(deg_to_rad(turn_speed_deg), 0.01), 0.0, 1.0)
		_servo.volume_db = servo_volume_db + linear_to_db(maxf(speed_ratio, 0.001))
		_servo.pitch_scale = 0.75 + 0.45 * speed_ratio


func _random_target_yaw() -> float:
	var half := deg_to_rad(yaw_range_deg) * 0.5
	var target := randf_range(-half, half)
	# Re-roll once if the sweep would be tiny enough to read as a stutter.
	if absf(angle_difference(target, _yaw)) < deg_to_rad(15.0):
		target = randf_range(-half, half)
	return target


func _random_target_pitch() -> float:
	var lo := minf(pitch_min_deg, pitch_max_deg)
	var hi := maxf(pitch_min_deg, pitch_max_deg)
	return -deg_to_rad(randf_range(lo, hi))


func _find_head() -> void:
	# FBX subtree: turret_double (root) / turret_double (base) / turret (head).
	# find_child matches with String.match, so "turret" (no wildcard) can only
	# hit the head; owned=false because the FBX internals belong to the import.
	_head = find_child("turret", true, false) as Node3D
	if _head:
		_rest_rotation = _head.rotation
