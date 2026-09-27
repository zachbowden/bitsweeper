class_name EnemyManager
extends Node

## Spawns enemies on freshly revealed clusters and tells every enemy where to
## step next. Instead of each enemy running its own A*, one breadth-first
## search spreads out from the player over revealed tiles and records each
## tile's distance to the player (a "flow field"). Any number of enemies can
## then find their next step with a few dictionary lookups.
##
## Enemies move on a finer grid than the map: every tile is split into
## SUBDIVISIONS x SUBDIVISIONS "sub-cells", and each sub-cell holds at most
## one enemy. Routing still uses the per-tile flow field (so it costs the
## same), and the sub-cells only decide where inside a tile an enemy stands.

const ENEMY_SCENE:PackedScene = preload("res://scenes/enemy.tscn")
## Sub-cells per tile along each axis (4 -> sub-cells are 0.25 of a tile).
const SUBDIVISIONS:int = 4
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
## Enemies further than this many steps (tiles) from the player don't chase.
@export var chase_range:int = 20
## Enemies won't step onto a sub-cell whose centre is closer than this many
## tiles to the player, so they ring the player instead of piling onto them.
## Keep it below the enemies' attack range so they can reach attacking distance.
@export var player_clearance:float = 0.5

var tiles:TileMapLayer
var player:Node2D
## Steps from each reachable revealed tile to the player's tile. Tiles that
## are missing have no path to the player (or are out of chase range).
var distance_to_player:Dictionary[Vector2i, int] = {}
## Sub-cell -> the enemy standing on it or walking into it, so no two enemies
## ever share a sub-cell. A moving enemy holds both its old and new sub-cell
## until it arrives.
var occupied:Dictionary[Vector2i, Node] = {}
var _player_cell:Vector2i
## Player position measured in sub-cells (fractional).
var _player_sub_position:Vector2
var _sub_size:Vector2
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
	_sub_size = Vector2(tiles.tile_set.tile_size) / SUBDIVISIONS
	tiles.tiles_revealed.connect(_on_tiles_revealed)

func _physics_process(_delta:float) -> void:
	if tiles == null or player == null:
		return
	_player_sub_position = tiles.to_local(player.global_position) / _sub_size
	var player_cell:Vector2i = to_cell(player.global_position)
	if player_cell != _player_cell:
		_player_cell = player_cell
		_needs_update = true
	if _needs_update:
		_needs_update = false
		_update_flow_field()

func to_cell(world_position:Vector2) -> Vector2i:
	return tiles.local_to_map(tiles.to_local(world_position))

func to_sub_cell(world_position:Vector2) -> Vector2i:
	return Vector2i((tiles.to_local(world_position) / _sub_size).floor())

func sub_cell_to_world(sub:Vector2i) -> Vector2:
	return tiles.to_global((Vector2(sub) + Vector2(0.5, 0.5)) * _sub_size)

func sub_cell_to_cell(sub:Vector2i) -> Vector2i:
	return Vector2i(floori(float(sub.x) / SUBDIVISIONS), floori(float(sub.y) / SUBDIVISIONS))

func is_free(sub:Vector2i, enemy:Node = null) -> bool:
	var holder:Node = occupied.get(sub)
	return holder == null or holder == enemy or not is_instance_valid(holder)

func claim(sub:Vector2i, enemy:Node) -> void:
	occupied[sub] = enemy

func release(sub:Vector2i, enemy:Node) -> void:
	if occupied.get(sub) == enemy:
		occupied.erase(sub)

## Returns the free neighbouring sub-cell `enemy` should step to, or `sub`
## itself when there's no path or every useful sub-cell is taken.
## Candidates are ranked by their tile's path distance first, so enemies
## always prefer entering a tile closer to the player. Ties are broken by how
## close they get to this tile's goal (the centre of the next tile on the
## path, or the player within their own tile), and a move must get strictly
## closer to it. That lets enemies sidestep around each other without
## shuffling back and forth.
func next_step(sub:Vector2i, enemy:Node) -> Vector2i:
	var cell:Vector2i = sub_cell_to_cell(sub)
	if not distance_to_player.has(cell):
		return sub
	var goal:Vector2 = _goal_for(cell)
	var best:Vector2i = sub
	var best_distance:int = distance_to_player[cell]
	var best_closeness:float = (Vector2(sub) + Vector2(0.5, 0.5) - goal).length_squared()
	for offset in NEIGHBOURS:
		var next:Vector2i = sub + offset
		var next_cell:Vector2i = sub_cell_to_cell(next)
		if not distance_to_player.has(next_cell) or not _can_step_sub(sub, next):
			continue
		if _within_clearance(next):
			continue
		if not is_free(next, enemy):
			continue
		var distance:int = distance_to_player[next_cell]
		var closeness:float = (Vector2(next) + Vector2(0.5, 0.5) - goal).length_squared()
		if distance < best_distance or (distance == best_distance and closeness < best_closeness):
			best = next
			best_distance = distance
			best_closeness = closeness
	return best

func _within_clearance(sub:Vector2i) -> bool:
	var clearance:float = player_clearance * SUBDIVISIONS
	return (Vector2(sub) + Vector2(0.5, 0.5) - _player_sub_position).length_squared() < clearance * clearance

## Where an enemy inside `cell` is heading, in sub-cell units: the centre of
## the best neighbouring tile on the path, or the player's exact position
## once the next tile is the player's own (or this is the player's tile).
## Aiming at the player rather than their tile's centre keeps enemies
## tracking them as they move around inside a tile.
func _goal_for(cell:Vector2i) -> Vector2:
	if cell == _player_cell:
		return _player_sub_position
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
	if best == _player_cell:
		return _player_sub_position
	return (Vector2(best) + Vector2(0.5, 0.5)) * SUBDIVISIONS

## Diagonal steps are only allowed when neither side tile is a wall, so
## enemies can't squeeze between two corners.
func _can_step(from:Vector2i, to:Vector2i) -> bool:
	if from.x == to.x or from.y == to.y:
		return true
	return tiles.revealed.has(Vector2i(to.x, from.y)) and tiles.revealed.has(Vector2i(from.x, to.y))

## Same corner rule as _can_step, applied to sub-cells.
func _can_step_sub(from:Vector2i, to:Vector2i) -> bool:
	if from.x == to.x or from.y == to.y:
		return true
	return tiles.revealed.has(sub_cell_to_cell(Vector2i(to.x, from.y))) \
		and tiles.revealed.has(sub_cell_to_cell(Vector2i(from.x, to.y)))

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
		if randf() >= chance:
			continue
		var sub:Vector2i = _random_free_sub_cell(cell)
		if sub == Vector2i.MAX:
			continue
		var enemy:Node2D = ENEMY_SCENE.instantiate()
		add_child(enemy)
		enemy.global_position = sub_cell_to_world(sub)
		claim(sub, enemy)

## A random unoccupied sub-cell inside `cell`, or Vector2i.MAX if it's full.
func _random_free_sub_cell(cell:Vector2i) -> Vector2i:
	var subs:Array[Vector2i] = []
	for x in SUBDIVISIONS:
		for y in SUBDIVISIONS:
			subs.append(cell * SUBDIVISIONS + Vector2i(x, y))
	subs.shuffle()
	for sub in subs:
		if is_free(sub):
			return sub
	return Vector2i.MAX
