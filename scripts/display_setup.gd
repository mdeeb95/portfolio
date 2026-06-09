extends Node
## Ensures the game viewport fills the browser window on web and resizes with the display.
## On mobile browsers it also drops to a cheaper quality tier: the milky-way sky shader is
## fillrate-heavy at retina resolution, and directional shadows re-render the scene's
## draw calls a second time.

## 3D render scale on mobile browsers (UI stays at native resolution).
const MOBILE_3D_SCALE := 0.7


func _ready() -> void:
	var window := get_window()
	if window == null:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if _is_mobile_web():
		window.scaling_3d_scale = MOBILE_3D_SCALE
		# Scenes load after autoloads; catch their lights as they enter the tree.
		get_tree().node_added.connect(_on_node_added)


func _is_mobile_web() -> bool:
	return OS.has_feature("web_ios") or OS.has_feature("web_android")


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).shadow_enabled = false
