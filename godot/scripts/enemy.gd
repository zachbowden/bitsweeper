extends Node2D

## Movement speed in pixels per second.
@export var speed:float = 60.0

## The EnemyManager. Left untyped on purpose: the manager preloads this
## enemy's scene, so naming its class here would be a cyclic reference.
var manager
var _target:Vector2
var _moving:bool = false

func _physics_process(delta:float) -> void:
	if manager == null:
		manager = get_tree().get_first_node_in_group("enemy_manager")
		if manager == null or manager.tiles == null:
			return
	# Walk tile centre to tile centre. The next tile is only chosen on arrival,
	# so the enemy always finishes its current step before changing course.
	var step:float = speed * delta
	while step > 0.0:
		if not _moving:
			var cell:Vector2i = manager.to_cell(global_position)
			var next:Vector2i = manager.next_step(cell)
			if next == cell:
				return # No path to the player, or already on their tile.
			_target = manager.cell_to_world(next)
			_moving = true
		var distance:float = global_position.distance_to(_target)
		if distance <= step:
			global_position = _target
			step -= distance
			_moving = false
		else:
			global_position = global_position.move_toward(_target, step)
			step = 0.0
