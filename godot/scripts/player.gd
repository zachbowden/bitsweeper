extends CharacterBody2D

## Movement speed in pixels per second.
@export var speed:float = 75.0

var sprite:AnimatedSprite2D

func _enter_tree() -> void:
	%PLAYER.add_to_group("player")

func _ready() -> void:
	# Draw above enemies (and tiles), which stay at the default z_index of 0.
	z_index = 1
	sprite = find_children("*", "AnimatedSprite2D", false)[0]
	update_coins()

func _physics_process(delta:float) -> void:
	var direction:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var motion:Vector2 = direction * speed * delta
	# Moving each axis separately lets the player slide along walls.
	_move_along_axis(Vector2(motion.x, 0.0))
	_move_along_axis(Vector2(0.0, motion.y))
	_animate(direction)

## Picks the animation from the input direction. Diagonals use the side
## animation. walk_right faces right, so it's mirrored for moving left.
func _animate(direction:Vector2) -> void:
	if direction.is_zero_approx():
		sprite.play("idle")
	elif absf(direction.x) >= absf(direction.y):
		sprite.play("walk_right")
		sprite.flip_h = direction.x < 0.0
	else:
		sprite.play("walk_down" if direction.y > 0.0 else "walk_up")
		sprite.flip_h = false

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

func update_coins() -> void:
	$coinCount.text=str(GLOBAL.coins_gathered)
