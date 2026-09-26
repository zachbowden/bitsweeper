extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	%COINS_GATHERED.text = \
		"Coins gathered: %d" % GLOBAL.coins_gathered

	%MONSTERS_KILLED.text = \
		"Monsters slain: %d" % GLOBAL.monsters_slain
	
	%ITEMS_USED.text = \
		"Items used: %d" % GLOBAL.items_used

func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.scn")
