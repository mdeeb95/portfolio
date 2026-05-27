extends Control

## Run with F6 (Run Current Scene). Uses the Dialogue autoload so there is only one UI instance.
## Open scenes/ui/dialogue_ui.tscn to edit layout exports in the inspector.


func _ready() -> void:
	var dlg: Node = get_node_or_null("/root/Dialogue")
	if dlg == null:
		push_warning("DialogueUIPreview: Dialogue autoload not found.")
		return
	if dlg.has_method("run_preview"):
		dlg.call_deferred("run_preview")
