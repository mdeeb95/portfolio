extends Node
## Ensures the game viewport fills the browser window on web and resizes with the display.

func _ready() -> void:
	var window := get_window()
	if window == null:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
