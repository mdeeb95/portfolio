extends Node

const INTERACT_RANGE := 5.5

var movement_locked: bool = false

var _player: CharacterBody3D
var _camera: Camera3D
var _focused: Interactable = null
var _interactables: Array[Interactable] = []


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	await get_tree().process_frame
	_camera = _find_camera()
	_gather_interactables()
	Dialogue.dialogue_started.connect(_on_dialogue_started)
	Dialogue.dialogue_ended.connect(_on_dialogue_ended)


func _physics_process(_delta: float) -> void:
	if Dialogue.is_active:
		return
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if Dialogue.is_active:
		if _is_continue_event(event):
			Dialogue.try_advance()
			get_viewport().set_input_as_handled()
		return

	if _is_interact_event(event):
		var target := _interactable_from_ray(event)
		if target == null:
			target = _focused
		if target != null and _can_interact_with(target):
			_start_interaction(target)
			get_viewport().set_input_as_handled()
		else:
			_try_tap_move(event)
			get_viewport().set_input_as_handled()


func _on_dialogue_started() -> void:
	movement_locked = true


func _on_dialogue_ended() -> void:
	movement_locked = false


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
	GameUI.set_interact_target(_focused)


func _can_interact_with(target: Interactable) -> bool:
	return target.is_player_in_range(_player.global_position)


func _start_interaction(target: Interactable) -> void:
	var pages := ResumeData.get_dialogue_pages(target.zone_key)
	Dialogue.start_dialogue(pages)


func _interactable_from_ray(event: InputEvent) -> Interactable:
	if _camera == null:
		return null
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	else:
		return null
	var origin := _camera.project_ray_origin(pos)
	var direction := _camera.project_ray_normal(pos)
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 80.0)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 8
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.collider
	if collider is Interactable:
		return collider as Interactable
	if collider is Node:
		var parent := (collider as Node).get_parent()
		if parent is Interactable:
			return parent as Interactable
	return null


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _is_continue_event(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


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
