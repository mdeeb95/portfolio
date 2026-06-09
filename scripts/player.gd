extends CharacterBody3D

const _CharacterStep = preload("res://scripts/character_step.gd")

# Movement speeds (walk_speed / run_speed, m/s) live on the KenneyCharacter (CharacterAnimator) so
# the blend poses line up with movement; read them via _animator. Tune them there in the inspector.
const TURN_SPEED := 14.0
const GRAVITY := 14.0
const TAP_MOVE_STOP_DIST := 0.35
## Impulse-per-second applied to RigidBody3D props per m/s of approach speed (N·s/m).
const PROP_PUSH_STRENGTH := 10.0

const STEP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/impactMetal_light_000.ogg"),
	preload("res://assets/audio/impactMetal_light_001.ogg"),
	preload("res://assets/audio/impactMetal_light_002.ogg"),
	preload("res://assets/audio/impactMetal_light_003.ogg"),
	preload("res://assets/audio/impactMetal_light_004.ogg"),
]

@onready var model: Node3D = $Model
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var _animator: CharacterAnimator = $Model/KenneyCharacter
@onready var _footsteps: AudioStreamPlayer = $FootstepPlayer

var _tap_target: Vector3 = Vector3.ZERO
var _has_tap_target: bool = false
var _was_on_floor: bool = true


func _ready() -> void:
	# Hear from the character, not the camera 11 m up the spring arm. The
	# listener sits outside the rotating Model so its yaw stays camera-aligned
	# and stereo panning keeps matching the screen.
	var listener := get_node_or_null("AudioListener3D") as AudioListener3D
	if listener:
		listener.make_current()
	# Footsteps fire when the animation actually plants a foot (support-foot
	# switch detection in CharacterAnimator), not on a distance estimate.
	if _animator:
		_animator.foot_planted.connect(_play_step)


func _physics_process(delta: float) -> void:
	if _is_movement_locked():
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		_update_animation()
		return

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var touch_dir := GameUI.get_move_vector()
	var analog := false
	if touch_dir.length_squared() > 0.01:
		input_dir = touch_dir
		analog = true
		_has_tap_target = false
	var cam_basis := spring_arm.global_transform.basis
	var cam_forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var cam_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var direction := (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()

	# Speeds come from the animator (tunable in the inspector); fall back to literals if absent.
	var walk_v: float = _animator.walk_speed if _animator else 5.0
	var run_v: float = _animator.run_speed if _animator else 8.0

	if direction != Vector3.ZERO:
		_has_tap_target = false
		# Joystick push distance (0..1) scales speed from a slow walk up to run_speed. Keyboard is
		# digital (magnitude ~1), so it moves at the steady walk_speed.
		var move_speed := walk_v
		if analog:
			move_speed = minf(input_dir.length(), 1.0) * run_v
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), TURN_SPEED * delta)
	elif _has_tap_target:
		var to_target := _tap_target - global_position
		to_target.y = 0.0
		if to_target.length() <= TAP_MOVE_STOP_DIST:
			_has_tap_target = false
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			direction = to_target.normalized()
			velocity.x = direction.x * walk_v
			velocity.z = direction.z * walk_v
			model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), TURN_SPEED * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if is_on_floor():
		_CharacterStep.try_step_up(self)
	# move_and_slide() slides velocity along contacts, zeroing the into-contact
	# component — capture it first so _push_props sees the real approach speed.
	var pre_slide_velocity := velocity
	move_and_slide()
	_push_props(pre_slide_velocity, delta)
	if not is_on_floor() and velocity.y <= 0.0:
		apply_floor_snap()
	_update_footsteps()
	_update_animation()


## Walking steps arrive via CharacterAnimator.foot_planted; this only adds the
## landing thud when the body comes back down onto the floor.
func _update_footsteps() -> void:
	if _footsteps == null:
		return
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_play_step()
	_was_on_floor = on_floor


func _play_step() -> void:
	_footsteps.stream = STEP_SOUNDS[randi() % STEP_SOUNDS.size()]
	_footsteps.pitch_scale = randf_range(0.92, 1.1)
	_footsteps.play()


func set_tap_target(world_pos: Vector3) -> void:
	_tap_target = world_pos
	_tap_target.y = global_position.y
	_has_tap_target = true


func _update_animation() -> void:
	if _animator == null:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_animator.update_locomotion(horizontal_speed, is_on_floor())


func _push_props(pre_slide_velocity: Vector3, delta: float) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider() as RigidBody3D
		if body == null:
			continue
		if body.linear_velocity.length_squared() > 36.0:
			continue # already flying (>6 m/s); don't keep pumping energy in
		var push_dir := -col.get_normal()
		push_dir.y = maxf(push_dir.y, 0.0)
		if push_dir.length_squared() < 0.001:
			continue
		push_dir = push_dir.normalized()
		var approach := clampf(pre_slide_velocity.dot(push_dir), 0.0, 9.0)
		if approach < 0.1:
			continue
		# Impulse at the contact point (offset from the body origin) so the hit
		# lands above the prop's center of mass and it tumbles instead of sliding.
		body.apply_impulse(push_dir * approach * PROP_PUSH_STRENGTH * delta, col.get_position() - body.global_position)


func _is_movement_locked() -> bool:
	var mgr := get_node_or_null("InteractionManager")
	return mgr != null and mgr.movement_locked
