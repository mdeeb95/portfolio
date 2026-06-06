extends Node

const INTERACT_RANGE := 5.5

var movement_locked: bool = false

var _player: CharacterBody3D
var _camera: Camera3D
var _focused: Interactable = null
var _dialogue_target: Interactable = null
var _interactables: Array[Interactable] = []
var _interact_cooldown: float = 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	await get_tree().process_frame
	_camera = _find_camera()
	_gather_interactables()
	Dialogue.dialogue_started.connect(_on_dialogue_started)
	Dialogue.dialogue_ended.connect(_on_dialogue_ended)
	Dialogue.dialogue_completed_fully.connect(_on_dialogue_completed_fully)


func _physics_process(delta: float) -> void:
	if _interact_cooldown > 0.0:
		_interact_cooldown = maxf(0.0, _interact_cooldown - delta)
	if Dialogue.is_active:
		return
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if Dialogue.is_active:
		if _is_cancel_event(event):
			Dialogue.cancel_dialogue()
			get_viewport().set_input_as_handled()
			return
		if _is_continue_event(event):
			Dialogue.try_advance()
			get_viewport().set_input_as_handled()
		return

	if _is_interact_event(event):
		var target := _interactable_from_ray(event)
		if target == null and not GameUI.is_mobile_controls():
			target = _focused
		if target != null and _can_interact_with(target) and target.can_start_dialogue():
			_start_interaction(target)
			get_viewport().set_input_as_handled()
		elif not GameUI.is_mobile_controls():
			_try_tap_move(event)
			get_viewport().set_input_as_handled()


func _on_dialogue_started() -> void:
	movement_locked = true


func _on_dialogue_ended() -> void:
	movement_locked = false
	_interact_cooldown = 0.4
	if _dialogue_target:
		_dialogue_target.set_dialogue_active(false)
		_dialogue_target = null
	_update_focus()


func _on_dialogue_completed_fully() -> void:
	if _dialogue_target:
		_dialogue_target.mark_dialogue_completed()


func _update_focus() -> void:
	if _player == null:
		return
	var best: Interactable = null
	var best_dist := INF
	for node: Interactable in _interactables:
		if not is_instance_valid(node):
			continue
		var dist := _player.global_position.distance_to(node.get_interact_point())
		if dist <= node.interact_range and dist < best_dist:
			best_dist = dist
			best = node
	if _focused != best:
		if _focused:
			_focused.set_focused(false)
		_focused = best
		if _focused:
			_focused.set_focused(true)


func _can_interact_with(target: Interactable) -> bool:
	return target.is_player_in_range(_player.global_position)


func _start_interaction(target: Interactable) -> void:
	if _interact_cooldown > 0.0 or not target.can_start_dialogue():
		return
	_dialogue_target = target
	target.set_dialogue_active(true)
	var pages := ResumeData.get_dialogue_pages(target.zone_key)
	Dialogue.start_dialogue(pages)


func is_interactable_at_screen(screen_pos: Vector2) -> bool:
	var target := _interactable_at_screen(screen_pos)
	return target != null and _can_interact_with(target) and target.can_start_dialogue()


## Called by the touch joystick on tap-release (a touch that did not drag).
## Interacts only if the tap landed on an in-range interactable.
func try_touch_interact(screen_pos: Vector2) -> bool:
	if Dialogue.is_active or _interact_cooldown > 0.0:
		return false
	var target := _interactable_at_screen(screen_pos)
	if target != null and _can_interact_with(target) and target.can_start_dialogue():
		_start_interaction(target)
		return true
	return false


func _interactable_from_ray(event: InputEvent) -> Interactable:
	var pos := _screen_pos_from_event(event)
	if pos.x < 0.0:
		return null
	return _interactable_at_screen(pos)


func _interactable_at_screen(screen_pos: Vector2) -> Interactable:
	if _camera == null:
		return null
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	var end := origin + direction * 80.0
	var space := _player.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var blocked: Interactable = null
	while true:
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.collision_mask = 8
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		exclude.append(hit.rid)
		var target := _interactable_from_collider(hit.collider)
		if target == null:
			continue
		if not target.click_to_interact:
			continue
		if _can_interact_with(target) and target.can_start_dialogue():
			return target
		if blocked == null and _can_interact_with(target):
			blocked = target
	return blocked


func _interactable_from_collider(collider: Object) -> Interactable:
	if collider is Interactable:
		return collider as Interactable
	if collider is Node:
		var parent := (collider as Node).get_parent()
		if parent is Interactable:
			return parent as Interactable
	return null


func _screen_pos_from_event(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	return Vector2(-1.0, -1.0)


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		return true
	var screen_pos := _screen_pos_from_event(event)
	if screen_pos.x < 0.0:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if GameUI.is_mobile_controls():
			return is_interactable_at_screen(screen_pos)
		return true
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return false
		return is_interactable_at_screen(screen_pos)
	return false


func _is_continue_event(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _is_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE


func _find_camera() -> Camera3D:
	var arms: Array[Node] = _player.find_children("*", "Camera3D", true, false)
	if arms.size() > 0:
		return arms[0] as Camera3D
	return get_viewport().get_camera_3d()


func _gather_interactables() -> void:
	_interactables.clear()
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node is Interactable:
			_interactables.append(node)


func _try_tap_move(event: InputEvent) -> void:
	if _camera == null or _player == null:
		return
	if GameUI.is_mobile_controls():
		return
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	else:
		return
	var origin := _camera.project_ray_origin(pos)
	var direction := _camera.project_ray_normal(pos)
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 80.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	_player.set_tap_target(hit.position)
