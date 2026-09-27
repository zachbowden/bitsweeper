extends Sprite2D

## Fired by the crossbow. Flies straight until it hits an enemy, an
## undiscovered tile, or runs out of range.

const HIT_RADIUS:float = 6.0

var velocity:Vector2
var max_distance:float = 200.0
var _travelled:float = 0.0

func _physics_process(delta:float) -> void:
	var step:Vector2 = velocity * delta
	global_position += step
	_travelled += step.length()

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) < HIT_RADIUS:
			enemy.hit()
			queue_free()
			return

	var tiles:TileMapLayer = get_tree().get_first_node_in_group("tile_gen")
	if tiles != null and not tiles.revealed.has(tiles.local_to_map(tiles.to_local(global_position))):
		queue_free()
	elif _travelled >= max_distance:
		queue_free()
