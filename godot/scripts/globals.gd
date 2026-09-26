extends Node

var coins_gathered:int = 0
var monsters_slain:int = 0
var items_used:int = 0
var difficulty:int = 1
var level:int = 1

func reset_run() -> void:
	coins_gathered = 0
	monsters_slain = 0
	items_used = 0
