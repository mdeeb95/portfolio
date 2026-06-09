class_name BabblePlayer
extends Node

## Soft typing babble for dialogue text. Replaces the old WarGames-style
## blips, whose buzzy harmonic stack, grit noise, 8-bit crush, and ascending
## pitch ladder (a periodic sweep) read as drilling. This is a rounded little
## "dook": a warm sine with two quiet harmonics, gentle attack, smooth decay,
## clean 16-bit — fired every other character with randomized (never cycling)
## pitch so no rhythm or sweep can form.

const BASE_HZ := 185.0
const BLIP_DURATION := 0.075
const BLIP_AMPLITUDE := 0.22
const MIX_RATE := 22050
## Blip every Nth visible character — per-character clicking is fatiguing no
## matter how soft the sample is.
const BLIP_EVERY := 2
const PITCH_MIN := 0.92
const PITCH_MAX := 1.08

var _player: AudioStreamPlayer
var _stream: AudioStreamWAV
var _call_count: int = 0
var _last_pitch: float = 1.0


func _ready() -> void:
	_stream = _make_blip_stream()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	_player.volume_db = -4.0
	_player.stream = _stream
	add_child(_player)


func play_blip() -> void:
	_call_count += 1
	if _call_count % BLIP_EVERY != 0:
		return
	if _player.playing:
		_player.stop()
	var pitch := randf_range(PITCH_MIN, PITCH_MAX)
	# Re-roll once when it lands on the previous pitch — identical blips in a
	# row read robotic, but a deterministic ladder reads like a siren. Random
	# with a nudge keeps it organic.
	if absf(pitch - _last_pitch) < 0.02:
		pitch = randf_range(PITCH_MIN, PITCH_MAX)
	_last_pitch = pitch
	_player.pitch_scale = pitch
	_player.play()


func _make_blip_stream() -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * BLIP_DURATION)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)

	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var norm := float(i) / float(sample_count)
		var env := smoothstep(0.0, 0.12, norm) * pow(1.0 - norm, 2.8)
		var wave := sin(TAU * BASE_HZ * t)
		wave += sin(TAU * BASE_HZ * 2.0 * t) * 0.25
		wave += sin(TAU * BASE_HZ * 3.0 * t) * 0.08
		var sample := int(clampf(wave * env * BLIP_AMPLITUDE, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
