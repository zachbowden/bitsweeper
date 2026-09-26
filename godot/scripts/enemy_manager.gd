class_name EnemyManager
extends Node

## Spawns enemies on freshly revealed clusters and tells every enemy which
## tile to step to next. Instead of each enemy running its own A*, one
## breadth-first search spreads out from the player over revealed tiles and
## records each tile's distance to the player (a "flow field"). Any number of
## enemies can then find their next step with a few dictionary lookups.

const ENEMY_SCENE:PackedScene = preload("res://scenes/enemy.tscn")
## Straight neighbours first, then diagonals.
const NEIGHBOURS:Array[Vector2i] = [
	Vector2i(0,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,1),
	Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1),
]

## A single reveal must open at least this many tiles to spawn enemies.
@export var min_cluster_size:int = 6
## Chance per revealed tile to spawn an enemy, multiplied by GLOBAL.difficulty.
@export_range(0.0, 1.0, 0.01) var spawn_chance_per_difficulty:float = 0.04
## Upper limit on the per-tile spawn chance, however high difficulty gets.
@export_range(0.0, 1.0, 0.01) var max_spawn_chance:float = 0.5
## Enemies never spawn closer than this many tiles to the player.
@export var min_spawn_distance:int = 3
## Enemies further than this many steps from the player don't chase.
@export var chase_range:int = 20

var tiles:TileMapLayer
var player:Node2D
## Steps from each reachable revealed tile to the player's tile. Tiles that
## are missing have no path to the player (or are out of chase range).
var distance_to_player:Dictionary[Vector2i, int] = {}
var _player_cell:Vector2i
var _needs_update:bool = true

func _enter_tree() -> void:
	add_to_group("enemy_manager")

func _ready() -> void:
	# Deferred until after every node's _ready, so the spawn area that
	# tile_gen reveals on load doesn't spawn enemies around the player.
	_setup.call_deferred()

func _setup() -> void:
	tiles = get_tree().get_first_node_in_group("tile_gen")
	player = get_tree().get_first_node_in_group("player")
	if tiles == null or player == null:
		push_error("EnemyManager needs a tile_gen and a player in the scene.")
		return
	tiles.tiles_revealed.connect(_on_tiles_revealed)

func _physics_process(_delta:float) -> void:
	if tiles == null or player == null:
		return
	var player_cell:Vector2i = to_cell(player.global_position)
	if player_cell != _player_cell:
		_player_cell = player_cell
		_needs_update = true
	if _needs_update:
		_needs_update = false
		_update_flow_field()

func to_cell(world_position:Vector2) -> Vector2i:
	return tiles.local_to_map(tiles.to_local(world_position))

func cell_to_world(cell:Vector2i) -> Vector2:
	return tiles.to_global(tiles.map_to_local(cell))

## Returns the neighbouring tile that gets closest to the player, or `cell`
## itself when there's no path (or the enemy is already on the player's tile).
func next_step(cell:Vector2i) -> Vector2i:
	if not distance_to_player.has(cell):
		return cell
	var best:Vector2i = cell
	var best_distance:int = distance_to_player[cell]
	for offset in NEIGHBOURS:
		var next:Vector2i = cell + offset
		if not distance_to_player.has(next) or not _can_step(cell, next):
			continue
		var distance:int = distance_to_player[next]
		# On ties, head for the tile that's more directly toward the player.
		if distance < best_distance or (distance == best_distance and best != cell \
				and (next - _player_cell).length_squared() < (best - _player_cell).length_squared()):
			best = next
			best_distance = distance
	return best

## Diagonal steps are only allowed when neither side tile is a wall, so
## enemies can't squeeze between two corners.
func _can_step(from:Vector2i, to:Vector2i) -> bool:
	if from.x == to.x or from.y == to.y:
		return true
	return tiles.revealed.has(Vector2i(to.x, from.y)) and tiles.revealed.has(Vector2i(from.x, to.y))

func _update_flow_field() -> void:
	distance_to_player.clear()
	distance_to_player[_player_cell] = 0
	var frontier:Array[Vector2i] = [_player_cell]
	var index:int = 0
	while index < frontier.size():
		var cell:Vector2i = frontier[index]
		index += 1
		var distance:int = distance_to_player[cell]
		if distance >= chase_range:
			continue
		for offset in NEIGHBOURS:
			var next:Vector2i = cell + offset
			if distance_to_player.has(next) or not tiles.revealed.has(next) or not _can_step(cell, next):
				continue
			distance_to_player[next] = distance + 1
			frontier.append(next)

func _on_tiles_revealed(cells:Array[Vector2i]) -> void:
	# New tiles can open a path that didn't exist before.
	_needs_update = true
	if cells.size() >= min_cluster_size:
		_spawn_enemies(cells)

func _spawn_enemies(cells:Array[Vector2i]) -> void:
	var chance:float = minf(spawn_chance_per_difficulty * GLOBAL.difficulty, max_spawn_chance)
	var player_cell:Vector2i = to_cell(player.global_position)
	for cell in cells:
		var offset:Vector2i = cell - player_cell
		if maxi(absi(offset.x), absi(offset.y)) < min_spawn_distance:
			continue
		if randf() < chance:
			var enemy:Node2D = ENEMY_SCENE.instantiate()
			add_child(enemy)
			enemy.global_position = cell_to_world(cell)
