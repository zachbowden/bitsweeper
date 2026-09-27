extends Node

var coins_gathered:int = 0
var monsters_slain:int = 0
var items_used:int = 0
var difficulty:int = 1
var level:int = 1
var inventory:Dictionary = {1:{"name":"mace","durability":10}}

func reset_run() -> void:
	coins_gathered = 0
	monsters_slain = 0
	items_used = 0
	inventory = {
		1:{"name":"crossbow","durability":100}
	}

## Plays a one-off sound. The player lives on this autoload, so the sound
## keeps playing even if the node that triggered it is freed or the scene
## changes (e.g. an enemy dying, or the player dying).
func play_sound(stream:AudioStream) -> void:
	var sound_player:AudioStreamPlayer = AudioStreamPlayer.new()
	sound_player.stream = stream
	sound_player.finished.connect(sound_player.queue_free)
	add_child(sound_player)
	sound_player.play()
