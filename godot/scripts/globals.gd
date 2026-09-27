extends Node

var coins_gathered:int = 0
var monsters_slain:int = 0
var items_used:int = 0
var difficulty:int = 1
var level:int = 1
var inventory:Dictionary = {1:{"name":"mace","durability":10}}
const MAX_HEALTH:int = 4
## Weapons that can be handed out for slots 1-2 (the dagger is always slot 3).
const LEVEL_WEAPONS:Array[String] = ["axe", "mace", "crossbow"]
const LEVEL_WEAPON_DURABILITY:int = 100
var health:int = MAX_HEALTH

func reset_run() -> void:
	coins_gathered = 0
	monsters_slain = 0
	items_used = 0
	health = MAX_HEALTH
	give_random_weapons()

func next_level() -> void:
	level += 1
	health = MAX_HEALTH
	give_random_weapons()

## Replaces slots 1-2 with two different random weapons at full durability.
func give_random_weapons() -> void:
	var weapons:Array[String] = LEVEL_WEAPONS.duplicate()
	weapons.shuffle()
	inventory = {
		1: {"name": weapons[0], "durability": LEVEL_WEAPON_DURABILITY},
		2: {"name": weapons[1], "durability": LEVEL_WEAPON_DURABILITY},
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
