extends Node

var music: AudioStreamPlayer

func _ready() -> void:
	music = AudioStreamPlayer.new()
	add_child(music)
	music.stream = load("res://assets/Audio/653527__mrthenoronha__8-bit-game-invencibility-loop.wav")
	music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.play()
