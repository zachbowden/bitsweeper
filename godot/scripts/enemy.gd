extends Node2D

## Movement speed in pixels per second.
@export var speed:float = 60.0

## The EnemyManager. Left untyped on purpose: the manager preloads this
## enemy's scene, so naming its class here would be a cyclic reference.
var manager
## Sub-cell the enemy is standing on (or leaving, while moving).
var _cell:Vector2i
## Sub-cell the enemy is walking into, while moving.
var _next_cell:Vector2i
var _target:Vector2
var _moving:bool = false
var _registered:bool = false
@onready var sprite:AnimatedSprite2D = find_children("*", "AnimatedSprite2D", false)[0]

func _enter_tree() -> void:
	add_to_group("enemies")

func die() -> void:
	if is_queued_for_deletion():
		return # Already killed this frame (e.g. by two hits at once).
	GLOBAL.monsters_slain += 1
	queue_free()

func _physics_process(delta:float) -> void:
	if manager == null:
		manager = get_tree().get_first_node_in_group("enemy_manager")
	if manager == null or manager.tiles == null:
		return
	if not _registered:
		_cell = manager.to_sub_cell(global_position)
		manager.claim(_cell, self)
		_registered = true
	# Walk sub-cell centre to sub-cell centre. The next sub-cell is only chosen
	# on arrival, so the enemy always finishes its current step before turning.
	var step:float = speed * delta
	while step > 0.0:
		if not _moving:
			var next:Vector2i = manager.next_step(_cell, self)
			if next == _cell:
				# No path, already there, or every useful sub-cell is taken.
				sprite.play("idle")
				return
			# Hold both sub-cells until arrival so nobody walks into the one we're leaving.
			manager.claim(next, self)
			_next_cell = next
			_target = manager.sub_cell_to_world(next)
			_moving = true
			_animate(_target - global_position)
		var distance:float = global_position.distance_to(_target)
		if distance <= step:
			global_position = _target
			step -= distance
			manager.release(_cell, self)
			_cell = _next_cell
			_moving = false
		else:
			global_position = global_position.move_toward(_target, step)
			step = 0.0

## Same animations as the player: walk_right faces right, so it's mirrored for
## moving left. Diagonal steps keep the current walk if it matches either
## direction, so zig-zagging along the sub-cell grid doesn't flicker between
## animations.
func _animate(direction:Vector2) -> void:
	var diagonal:bool = not is_zero_approx(direction.x) and not is_zero_approx(direction.y)
	if diagonal:
		match sprite.animation:
			&"walk_down":
				if direction.y > 0.0:
					return
			&"walk_up":
				if direction.y < 0.0:
					return
			&"walk_right":
				if (direction.x < 0.0) == sprite.flip_h:
					return
	if absf(direction.x) >= absf(direction.y):
		sprite.play("walk_right")
		sprite.flip_h = direction.x < 0.0
	else:
		sprite.play("walk_down" if direction.y > 0.0 else "walk_up")
		sprite.flip_h = false

func _exit_tree() -> void:
	if _registered and is_instance_valid(manager):
		manager.release(_cell, self)
		if _moving:
			manager.release(_next_cell, self)
