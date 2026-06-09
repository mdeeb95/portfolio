class_name AmbientHum
extends AudioStreamPlayer3D

## Looping machine hum for decorations. Each instance picks a random pitch and
## starts at a random offset so identical machines around the town don't sound
## phase-locked. Drop ambient_hum.tscn under any deco node; position is local
## to the deco, so it inherits placement for free.

@export_range(0.5, 2.0, 0.01) var pitch_min: float = 0.8
@export_range(0.5, 2.0, 0.01) var pitch_max: float = 1.2


func _ready() -> void:
	var ogg := stream as AudioStreamOggVorbis
	if ogg:
		ogg.loop = true
	pitch_scale = randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
	play(randf() * (ogg.get_length() if ogg else 0.0))
