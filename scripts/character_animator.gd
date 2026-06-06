class_name CharacterAnimator
extends Node

enum State { IDLE, WALK, TALK }

## Mixamo locomotion + talk clips retargeted onto the Kenney rig in Mixamo,
## so each FBX shares the Kenney skeleton and a single clip named "mixamo_com".
const MIXAMO_CLIP := "mixamo_com"
const ANIM_SOURCES := {
	"idle": {
		"path": "res://assets/characters/mixamo/animations/idle.fbx",
		"clip": MIXAMO_CLIP,
		"loop": true,
	},
	"walk": {
		"path": "res://assets/characters/mixamo/animations/walking.fbx",
		"clip": MIXAMO_CLIP,
		"loop": true,
	},
	"talk": {
		"path": "res://assets/characters/mixamo/animations/talking.fbx",
		"clip": MIXAMO_CLIP,
		"loop": true,
	},
}

const SKIN_TEXTURE := preload("res://assets/characters/kenney/skins/business_male_a.png")
const MESH_NODE_NAME := "characterLargeMale"
const ANIM_TRACK_PREFIX := "Root/Skeleton3D"
const ANIM_TRACK_REMAP := "Root/Root/Skeleton3D"

const MOVE_THRESHOLD := 0.25

## Body speed (m/s) where the walk clip plays at 1×. Match to player WALK_SPEED for a
## 1:1 start, then nudge in the editor. No speed cap — values above ~7 used to look
## identical because of a removed 1.1 clamp, not because tuning stopped working.
@export var walk_anim_match_speed := 5.0
## Crossfade duration (seconds) when switching idle ↔ walk.
@export var idle_walk_blend_time := 0.25

## Kenney FBX import scales an inner Root by 100 (~2.5 m). Scale outer Root to fit the 1.6 m capsule.
@export var model_scale := Vector3(0.64, 0.64, 0.64)

@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _model_root: Node3D = $Root

var _current_state: State = State.IDLE
var _talking: bool = false
var _libraries_ready: bool = false
var _last_horizontal_speed: float = 0.0


func _enter_tree() -> void:
	_apply_model_scale()


func _ready() -> void:
	_apply_model_scale()
	_apply_skin()
	if Engine.is_editor_hint():
		return
	_build_animation_library()
	_play_state(State.IDLE)


func _apply_model_scale() -> void:
	var root := get_node_or_null("Root") as Node3D
	if root:
		root.scale = model_scale


func set_talking(talking: bool) -> void:
	if _talking == talking:
		return
	_talking = talking
	_refresh_state(0.0, true)


func update_locomotion(horizontal_speed: float, is_on_floor: bool) -> void:
	_last_horizontal_speed = horizontal_speed
	_refresh_state(horizontal_speed, is_on_floor)


func _apply_skin() -> void:
	var mesh := _model_root.find_child(MESH_NODE_NAME, true, false) as MeshInstance3D
	if mesh == null:
		var meshes := _model_root.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			return
		mesh = meshes[0] as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.albedo_texture = SKIN_TEXTURE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mesh.material_override = material


func _build_animation_library() -> void:
	if _libraries_ready:
		return

	var library := AnimationLibrary.new()
	_animation_player.add_animation_library("", library)

	for anim_name: String in ANIM_SOURCES.keys():
		var source: Dictionary = ANIM_SOURCES[anim_name]
		var scene: PackedScene = load(source["path"] as String)
		var instance := scene.instantiate()
		var source_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clip_name: String = source["clip"] as String
		var animation := source_player.get_animation(clip_name).duplicate()
		animation.loop_mode = Animation.LOOP_LINEAR if source["loop"] else Animation.LOOP_NONE
		_remap_animation_paths(animation)
		_remove_root_motion(animation)
		library.add_animation(anim_name, animation)
		instance.free()

	_libraries_ready = true


func _remap_animation_paths(animation: Animation) -> void:
	for track_idx: int in animation.get_track_count():
		var path := str(animation.track_get_path(track_idx))
		if path.begins_with(ANIM_TRACK_PREFIX):
			animation.track_set_path(
				track_idx,
				NodePath(path.replace(ANIM_TRACK_PREFIX, ANIM_TRACK_REMAP)),
			)


## Mixamo clips retargeted onto Kenney still key HipsCtrl translation. Under the
## inner 100× Root that reads as world-space drift and a loop snap — strip it so
## movement comes only from CharacterBody3D velocity (in-place locomotion).
func _remove_root_motion(animation: Animation) -> void:
	for track_idx: int in range(animation.get_track_count() - 1, -1, -1):
		if animation.track_get_type(track_idx) == Animation.TYPE_POSITION_3D:
			animation.remove_track(track_idx)


func _refresh_state(horizontal_speed: float, is_on_floor: bool) -> void:
	var next_state := _pick_state(horizontal_speed, is_on_floor)
	if next_state != _current_state:
		_play_state(next_state)
	elif next_state == State.WALK:
		_apply_walk_speed_scale()


func _pick_state(horizontal_speed: float, _is_on_floor: bool) -> State:
	if _talking:
		return State.TALK
	if horizontal_speed > MOVE_THRESHOLD:
		return State.WALK
	return State.IDLE


func _play_state(state: State) -> void:
	var prev_anim := _animation_player.current_animation
	_current_state = state
	var anim_name := _state_to_animation(state)
	if prev_anim != anim_name:
		_animation_player.play(anim_name, _locomotion_blend_time(prev_anim, anim_name))
	if state == State.WALK:
		_apply_walk_speed_scale()
	else:
		_animation_player.speed_scale = 1.0


func _apply_walk_speed_scale() -> void:
	var move_speed := maxf(_last_horizontal_speed, MOVE_THRESHOLD)
	_animation_player.speed_scale = walk_anim_match_speed / move_speed


func _locomotion_blend_time(from_anim: String, to_anim: String) -> float:
	var locomotion := ["idle", "walk"]
	if from_anim in locomotion and to_anim in locomotion:
		return idle_walk_blend_time
	return 0.0


func _state_to_animation(state: State) -> String:
	match state:
		State.WALK:
			return "walk"
		State.TALK:
			return "talk"
		_:
			return "idle"
