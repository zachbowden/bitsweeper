extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$ColorRect/CenterContainer/VBoxContainer/CoinsGathered.text = \
		"Coins gathered: %d" % GLOBAL.coins_gathered

	$ColorRect/CenterContainer/VBoxContainer/MonstersSlain.text = \
		"Monsters slain: %d" % GLOBAL.monsters_slain
	
	$ColorRect/CenterContainer/VBoxContainer/ItemsUsed.text = \
		"Items used: %d" % GLOBAL.items_used

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.scn")
