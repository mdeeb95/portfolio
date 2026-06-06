extends Node
## Hold-to-begin gate for the web build.
##
## The custom HTML shell (res://web/godot_shell.html) shows a boids loading
## screen, then a "tap and hold to enter" prompt. While the player has not yet
## entered, the SceneTree is paused so the iris transition reveals a still first
## frame that springs to life on entry. The shell signals entry by setting
## `window.__deebStarted = true`, which this autoload polls for.
##
## On non-web builds (editor/desktop) this is inert — the game runs normally.

signal started

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		set_process(false)
		return
	# Freeze gameplay until the player holds to enter.
	get_tree().paused = true

func _process(_delta: float) -> void:
	if JavaScriptBridge.eval("window.__deebStarted === true", true):
		get_tree().paused = false
		set_process(false)
		started.emit()
