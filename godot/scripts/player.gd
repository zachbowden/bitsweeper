extends CharacterBody2D

const WEAPON_TILESET:TileSet = preload("res://assets/tileset/weapons.tres")
const ARROW_SCRIPT:GDScript = preload("res://scripts/arrow.gd")
const ARROW_TEXTURE:Texture2D = preload("res://icon.svg")
## Slot 3 is never stored in GLOBAL.inventory; it's always an unbreakable dagger.
const DAGGER_SLOT:int = 3
## Weapon sprites point to the top right of their tile, i.e. at -45 degrees.
const SPRITE_ANGLE:float = -PI / 4
## Per-weapon stats. Ranges are in pixels, arcs in degrees, cooldowns in seconds.
## "mirror_left" flips the held sprite while it's on the player's left side.
const WEAPONS:Dictionary = {
	"axe":      {"coords": Vector2i(3,0), "range": 30.0, "arc": 100.0, "cooldown": 0.5, "mirror_left": true},
	"mace":     {"coords": Vector2i(4,0), "range": 30.0, "arc": 140.0, "cooldown": 0.6},
	"dagger":   {"coords": Vector2i(5,0), "range": 20.0, "arc": 70.0,  "cooldown": 0.25},
	"crossbow": {"coords": Vector2i(6,0), "range": 200.0, "cooldown": 0.6, "ranged": true},
}

## Movement speed in pixels per second.
@export var speed:float = 75.0
## Held weapon size relative to the player sprite's pixel scale.
@export var held_weapon_scale:float = 1.0
## How far from the player's centre the held weapon sits, in pixels.
@export var hold_distance:float = 8.0
## How much bigger the selected slot's sprite is drawn.
@export var selected_slot_scale:float = 1.25
@export var arrow_speed:float = 250.0

var sprite:AnimatedSprite2D
var selected_slot:int = DAGGER_SLOT
var _attack_cooldown:float = 0.0
## Extra rotation added to the held weapon while swinging.
var _swing_offset:float = 0.0
var _swing_tween:Tween
## On-screen size of each slot/EQUIPT sprite, taken from the placeholder
## texture in the scene, so any weapon texture is drawn at that same size.
var _display_sizes:Dictionary[Sprite2D, Vector2] = {}
var _weapon_textures:Dictionary[String, AtlasTexture] = {}

@onready var slot_sprites:Dictionary[int, Sprite2D] = {1: %SLOT_1, 2: %SLOT_2, 3: %SLOT_3}

func _enter_tree() -> void:
	%PLAYER.add_to_group("player")

func _ready() -> void:
	# Draw above enemies (and tiles), which stay at the default z_index of 0.
	z_index = 1
	sprite = find_children("*", "AnimatedSprite2D", false)[0]
	for display:Sprite2D in [%SLOT_1, %SLOT_2, %SLOT_3, %EQUIPT]:
		var size:Vector2 = display.texture.get_size() if display.texture else Vector2(16, 16)
		_display_sizes[display] = size * display.scale
	selected_slot = 1 if GLOBAL.inventory.has(1) else DAGGER_SLOT
	_update_inventory_display()

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _select_slot(1)
			KEY_2: _select_slot(2)
			KEY_3: _select_slot(3)

func _physics_process(delta:float) -> void:
	var direction:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var motion:Vector2 = direction * speed * delta
	# Moving each axis separately lets the player slide along walls.
	_move_along_axis(Vector2(motion.x, 0.0))
	_move_along_axis(Vector2(0.0, motion.y))
	_animate(direction)

	_attack_cooldown -= delta
	if Input.is_physical_key_pressed(KEY_SPACE) and _attack_cooldown <= 0.0:
		_attack()
	_update_held_weapon()

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

# --- Inventory ---------------------------------------------------------------

## The item in `slot` as {"name", "durability"}, or an empty dictionary.
## Slots 1-2 return the dictionary stored in GLOBAL.inventory itself, so
## changing its durability changes the inventory.
func _get_item(slot:int) -> Dictionary:
	if slot == DAGGER_SLOT:
		return {"name": "dagger"}
	return GLOBAL.inventory.get(slot, {})

func _select_slot(slot:int) -> void:
	selected_slot = slot
	_update_inventory_display()

func _update_inventory_display() -> void:
	for slot in slot_sprites:
		var display:Sprite2D = slot_sprites[slot]
		var grow:float = selected_slot_scale if slot == selected_slot else 1.0
		_show_weapon(display, _get_item(slot).get("name", ""), grow)

	var item:Dictionary = _get_item(selected_slot)
	_show_weapon(%EQUIPT, item.get("name", ""))
	# The dagger never breaks, so it shows no count.
	%DURABILITY.text = ("x%d" % item["durability"]) if item.has("durability") else ""
	%WEAPON.texture = _weapon_texture(item.get("name", ""))

## Shows `weapon_name` in a HUD sprite at its placeholder's size times `grow`
## (an empty name hides it).
func _show_weapon(display:Sprite2D, weapon_name:String, grow:float = 1.0) -> void:
	var texture:AtlasTexture = _weapon_texture(weapon_name)
	display.texture = texture
	if texture != null:
		display.scale = _display_sizes[display] / texture.get_size() * grow

func _weapon_texture(weapon_name:String) -> AtlasTexture:
	if not WEAPONS.has(weapon_name):
		return null
	if not _weapon_textures.has(weapon_name):
		var source:TileSetAtlasSource = WEAPON_TILESET.get_source(WEAPON_TILESET.get_source_id(0))
		var texture:AtlasTexture = AtlasTexture.new()
		texture.atlas = source.texture
		texture.region = source.get_tile_texture_region(WEAPONS[weapon_name]["coords"])
		_weapon_textures[weapon_name] = texture
	return _weapon_textures[weapon_name]

## Uses up one durability; the item is destroyed when it reaches zero and
## the player falls back to the dagger.
func _use_durability() -> void:
	var item:Dictionary = _get_item(selected_slot)
	if not item.has("durability"):
		return
	item["durability"] -= 1
	if item["durability"] <= 0:
		GLOBAL.inventory.erase(selected_slot)
		selected_slot = DAGGER_SLOT
	_update_inventory_display()

# --- Combat ------------------------------------------------------------------

func _aim_direction() -> Vector2:
	var aim:Vector2 = get_global_mouse_position() - %PLAYER.global_position
	return aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT

## Keeps the held weapon beside the player, pointing at the mouse.
func _update_held_weapon() -> void:
	var weapon:Sprite2D = %WEAPON
	if weapon.texture == null:
		return
	var aim:Vector2 = _aim_direction()
	var weapon_name:String = _get_item(selected_slot).get("name", "")
	var mirrored:bool = aim.x < 0.0 and WEAPONS[weapon_name].get("mirror_left", false)
	weapon.flip_h = mirrored
	# Flipping makes the sprite point top-left instead of top-right, and the
	# swing runs the other way so it still mirrors the right-hand side.
	var sprite_angle:float = PI - SPRITE_ANGLE if mirrored else SPRITE_ANGLE
	var swing:float = -_swing_offset if mirrored else _swing_offset
	weapon.global_position = %PLAYER.global_position + aim * hold_distance
	weapon.global_rotation = aim.angle() - sprite_angle + swing
	weapon.global_scale = %PLAYER.global_scale * held_weapon_scale
	# Walking up shows the cat's back, so the weapon goes behind it.
	weapon.show_behind_parent = sprite.animation == &"walk_up"

func _attack() -> void:
	var weapon_name:String = _get_item(selected_slot).get("name", "")
	if not WEAPONS.has(weapon_name):
		return
	var stats:Dictionary = WEAPONS[weapon_name]
	_attack_cooldown = stats["cooldown"]
	if stats.get("ranged", false):
		_fire_arrow(stats["range"])
	else:
		_melee(stats["range"], deg_to_rad(stats["arc"]))
	_use_durability()

## Kills every enemy within `reach` pixels and inside the `arc` toward the mouse.
func _melee(reach:float, arc:float) -> void:
	var origin:Vector2 = %PLAYER.global_position
	var aim_angle:float = _aim_direction().angle()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy:Vector2 = enemy.global_position - origin
		if to_enemy.length() <= reach and absf(angle_difference(aim_angle, to_enemy.angle())) <= arc / 2:
			enemy.die()

	# Swing the held weapon across the arc and back to rest.
	if _swing_tween:
		_swing_tween.kill()
	_swing_offset = -arc / 2
	_swing_tween = create_tween()
	_swing_tween.tween_property(self, "_swing_offset", arc / 2, 0.1)
	_swing_tween.tween_property(self, "_swing_offset", 0.0, 0.08)

func _fire_arrow(max_distance:float) -> void:
	var aim:Vector2 = _aim_direction()
	var arrow = ARROW_SCRIPT.new()
	arrow.texture = ARROW_TEXTURE # Placeholder until there's an arrow sprite.
	arrow.z_index = 1
	arrow.velocity = aim * arrow_speed
	arrow.max_distance = max_distance
	# Added to the level, not the player, so it doesn't move with the player.
	get_parent().add_child(arrow)
	arrow.global_position = %PLAYER.global_position
	arrow.global_rotation = aim.angle()
	arrow.global_scale = Vector2(0.06, 0.06)
