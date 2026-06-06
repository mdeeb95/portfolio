class_name BabblePlayer
extends Node

## WarGames / vintage speech-synth style blips (WOPR-ish TTS texture).

const BASE_HZ := 158.0
const BLIP_DURATION := 0.055
const BLIP_VOLUME := 0.1

## Stepped pitch feels more like old phoneme synthesis than smooth vibrato.
const PITCH_STEPS: Array[float] = [0.88, 0.94, 1.0, 1.06, 1.12]

var _player: AudioStreamPlayer
var _stream: AudioStreamWAV
var _step_index: int = 0


func _ready() -> void:
	_stream = _make_blip_stream()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	_player.volume_db = -10.0
	_player.stream = _stream
	add_child(_player)


func play_blip() -> void:
	if _player.playing:
		_player.stop()
	_player.pitch_scale = PITCH_STEPS[_step_index]
	_step_index = (_step_index + 1) % PITCH_STEPS.size()
	_player.play()


func _make_blip_stream() -> AudioStreamWAV:
	var mix_rate := 11025
	var sample_count := int(mix_rate * BLIP_DURATION)
	var bytes := PackedByteArray()
	bytes.resize(sample_count)

	var hold_every := 3
	var held_sample := 0.0

	for i in sample_count:
		var t := float(i) / float(mix_rate)
		var norm := float(i) / float(sample_count)
		var attack := smoothstep(0.0, 0.06, norm)
		var release := pow(1.0 - norm, 2.2)
		var env := attack * release

		var buzz := _band_limited_pulse(t, BASE_HZ)
		var formant_a := sin(TAU * 580.0 * t) * 0.2
		var formant_b := sin(TAU * 1180.0 * t) * 0.12
		var grit := _deterministic_noise(t) * 0.16
		var raw := (buzz * 0.62 + formant_a + formant_b + grit) * env * BLIP_VOLUME

		raw = _bit_crush(raw, 9.0)

		if i % hold_every == 0:
			held_sample = raw
		var wave := held_sample

		bytes[i] = int(clamp(wave * 120.0 + 128.0, 0.0, 255.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _band_limited_pulse(t: float, fundamental: float) -> float:
	var sum := 0.0
	for harmonic: int in [1, 3, 5, 7, 9]:
		sum += sin(TAU * fundamental * float(harmonic) * t) / float(harmonic)
	return sum * 0.55


func _deterministic_noise(t: float) -> float:
	return sin(t * 127.1) * sin(t * 311.7) * sin(t * 74.3)


func _bit_crush(sample: float, levels: float) -> float:
	return round(sample * levels) / levels
