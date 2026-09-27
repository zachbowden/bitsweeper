extends CanvasLayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_coins()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func update_coins() -> void:
	$CoinCount.text = \
		"Coins gathered: %d" % GLOBAL.coins_gathered
