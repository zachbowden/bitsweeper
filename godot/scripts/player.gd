extends CharacterBody2D

## Movement speed in pixels per second.
@export var speed:float = 75.0

func _enter_tree() -> void:
	add_to_group("player")

func _physics_process(delta:float) -> void:
	var direction:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var motion:Vector2 = direction * speed * delta
	# Moving each axis separately lets the player slide along walls.
	_move_along_axis(Vector2(motion.x, 0.0))
	_move_along_axis(Vector2(0.0, motion.y))

## Moves as far as possible along `motion` without touching a wall.
## move_and_slide() pushes the body out of walls every frame, which nudges it
## back and forth by fractions of a pixel (visible as jitter since the camera
## follows the player). Here the body only ever moves forward along the axis,
## so it settles against a wall and stays perfectly still.
func _move_along_axis(motion:Vector2) -> void:
	if motion.is_zero_approx():
		return
	var collision:KinematicCollision2D = move_and_collide(motion, true)
	if collision == null:
		global_position += motion
		return
	var travel:float = minf(collision.get_travel().dot(motion.normalized()), motion.length())
	if travel > 0.0:
		global_position += motion.normalized() * travel
