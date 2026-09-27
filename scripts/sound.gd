class_name Sound
extends Node

const BGM: Dictionary = {
	"hub": "res://assets/audio/bgm_hub.wav",
	"battle": "res://assets/audio/bgm_battle.wav",
	"boss": "res://assets/audio/bgm_boss.wav",
}
const VOICES: int = 10

var music := AudioStreamPlayer.new()
var voices: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var current: String = ""
var muted: bool = false
var cache: Dictionary = {}

func _ready() -> void:
	music.volume_db = -9.0
	add_child(music)
	for i: int in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -4.0
		add_child(voice)
		voices.append(voice)

func _exit_tree() -> void:
	# Release active playbacks so quitting doesn't leak AudioStreamPlayback objects.
	music.stop()
	music.stream = null
	for voice: AudioStreamPlayer in voices:
		voice.stop()
		voice.stream = null

func stream(path: String) -> AudioStream:
	if not cache.has(path):
		cache[path] = load(path) if ResourceLoader.exists(path) else null
	return cache[path]

func play_bgm(track: String) -> void:
	if track == current:
		return
	current = track
	music.stop()
	if track.is_empty():
		return
	var wav := stream(BGM[track]) as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * wav.mix_rate)
	music.stream = wav
	music.play()

func play(effect: String, pitch_variance: float = 0.06, volume_db: float = -4.0) -> void:
	var sample := stream("res://assets/audio/se_%s.wav" % effect)
	if sample == null or voices.is_empty():
		return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = sample
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	voice.play()

func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted
