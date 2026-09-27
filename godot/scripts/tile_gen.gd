extends TileMapLayer

## Emitted when the player clicks a hidden tile that contains a mine.
signal mine_triggered(cell:Vector2i)
## Emitted after a single reveal() opens tiles, with every tile it opened.
signal tiles_revealed(cells:Array[Vector2i])

const TILE_SOURCE_ID:int = 0
const FLAG_SOURCE_ID:int = 1
const FLAG_ATLAS_COORDS:Vector2i = Vector2i(0,0)
const DOOR_SOURCE_ID:int = 2
const DOOR_ATLAS_COORDS:Vector2i = Vector2i(0,0)
const HIDDEN:int = 0xA
const MINESWEEPER_TILE_ATLAS:Dictionary = {
	0:Vector2i(4,0),
	1:Vector2i(0,1),
	2:Vector2i(1,1),
	3:Vector2i(2,1),
	4:Vector2i(3,1),
	5:Vector2i(4,1),
	6:Vector2i(5,1),
	7:Vector2i(6,1),
	8:Vector2i(0,0),
	HIDDEN:Vector2i(1,0),
}
const NEIGHBOURS:Array[Vector2i] = [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1, 0),                 Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
## Half-width of the guaranteed mine-free square around the spawn (2 -> 5x5).
const SPAWN_SAFE_RADIUS:int = 2
## Extra tiles drawn past the screen edge so scrolling never shows gaps.
const DRAW_MARGIN:int = 2
## Hard cap on a single flood fill, in case the density is set very low.
const MAX_FLOOD_TILES:int = 20000

## Fraction of tiles that are mines (0.0 - 1.0).
@export_range(0.0, 1.0, 0.01) var mine_density:float = 0.14
## Chance for any non-mine tile to be a door (0.002 -> about 1 in 500 tiles).
@export_range(0.0, 0.1, 0.0001) var door_chance:float = 0.0005
## Scene loaded when the player walks onto a revealed door.
@export_file("*.tscn", "*.scn") var door_scene:String

var noise:FastNoiseLite = FastNoiseLite.new()
## Separate noise for door placement, so doors don't correlate with mines.
var door_noise:FastNoiseLite = FastNoiseLite.new()
## Every tile the player has revealed, mapped to its adjacent mine count.
## Hidden tiles are never stored; they are derived from the noise on demand.
## Tiles are erased from the TileMapLayer when off screen, so this is what
## keeps explored areas revealed when the player comes back to them.
var revealed:Dictionary[Vector2i, int] = {}
## Hidden tiles the player has flagged. Flagged tiles can't be revealed until
## the flag is removed, and flood reveals stop at them.
var flagged:Dictionary[Vector2i, bool] = {}
var _drawn_rect:Rect2i = Rect2i()
## Child layer that draws flags and doors on top of the tiles beneath them.
var _overlay_layer:TileMapLayer
var _player:Node2D
var _leaving:bool = false

func _enter_tree() -> void:
	add_to_group("tile_gen")

func _ready() -> void:
	# Value noise sampled on integer lattice points at frequency 1 returns the
	# raw per-lattice hash, i.e. an uncorrelated, roughly uniform value in
	# [-1, 1] for every (x, y, level) - exactly what we want for mine placement.
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.seed = randi()
	for setting in ["noise_type", "frequency", "fractal_type"]:
		door_noise.set(setting, noise.get(setting))
	door_noise.seed = randi()

	# The overlay layer only draws; collision comes from the tile below it.
	_overlay_layer = TileMapLayer.new()
	_overlay_layer.tile_set = tile_set
	_overlay_layer.collision_enabled = false
	add_child(_overlay_layer)

	clear()
	for x in range(-SPAWN_SAFE_RADIUS, SPAWN_SAFE_RADIUS + 1):
		for y in range(-SPAWN_SAFE_RADIUS, SPAWN_SAFE_RADIUS + 1):
			reveal(Vector2i(x, y))
	_update_visible_tiles()

func _process(_delta:float) -> void:
	_update_visible_tiles()
	_check_door()

## Loads door_scene once the player stands on a revealed door.
func _check_door() -> void:
	if _leaving:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var cell:Vector2i = local_to_map(to_local(_player.global_position))
	if not (revealed.has(cell) and is_door(cell)):
		return
	if door_scene.is_empty():
		push_warning("Player reached a door, but door_scene isn't set.")
		return
	_leaving = true
	get_tree().change_scene_to_file.call_deferred(door_scene)

func _unhandled_input(event:InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var cell:Vector2i = local_to_map(get_local_mouse_position())
	if revealed.has(cell):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if flagged.has(cell):
				return
			if is_mine(cell):
				mine_triggered.emit(cell)
			else:
				reveal(cell)
		MOUSE_BUTTON_RIGHT:
			toggle_flag(cell)
		_:
			return
	get_viewport().set_input_as_handled()

func toggle_flag(cell:Vector2i) -> void:
	if revealed.has(cell):
		return
	if flagged.has(cell):
		flagged.erase(cell)
	else:
		flagged[cell] = true
	if _drawn_rect.has_point(cell):
		_draw_cell(cell)

func is_mine(cell:Vector2i) -> bool:
	if absi(cell.x) <= SPAWN_SAFE_RADIUS and absi(cell.y) <= SPAWN_SAFE_RADIUS:
		return false
	var value:float = noise.get_noise_3d(cell.x, cell.y, GLOBAL.level)
	# Map [-1, 1] to [0, 1] and compare against the density.
	return (value + 1.0) * 0.5 < mine_density

## Doors only appear on safe tiles outside the spawn area. Like mines, they
## come from noise, so the same tiles are doors every time they're drawn.
func is_door(cell:Vector2i) -> bool:
	if absi(cell.x) <= SPAWN_SAFE_RADIUS and absi(cell.y) <= SPAWN_SAFE_RADIUS:
		return false
	if is_mine(cell):
		return false
	var value:float = door_noise.get_noise_3d(cell.x, cell.y, GLOBAL.level)
	return (value + 1.0) * 0.5 < door_chance

func count_adjacent_mines(cell:Vector2i) -> int:
	var count:int = 0
	for offset in NEIGHBOURS:
		if is_mine(cell + offset):
			count += 1
	return count

## Reveals a tile; if it has no adjacent mines, flood-reveals the connected
## empty area and its numbered border, like classic minesweeper.
func reveal(start:Vector2i) -> void:
	if revealed.has(start) or flagged.has(start) or is_mine(start):
		return
	var stack:Array[Vector2i] = [start]
	var opened:Array[Vector2i] = []
	while not stack.is_empty() and opened.size() < MAX_FLOOD_TILES:
		var cell:Vector2i = stack.pop_back()
		if revealed.has(cell):
			continue
		var count:int = count_adjacent_mines(cell)
		revealed[cell] = count
		opened.append(cell)
		if _drawn_rect.has_point(cell):
			_draw_cell(cell)
		if count == 0:
			for offset in NEIGHBOURS:
				var next:Vector2i = cell + offset
				if not revealed.has(next) and not flagged.has(next):
					stack.push_back(next)
	tiles_revealed.emit(opened)

func _draw_cell(cell:Vector2i) -> void:
	var key:int = revealed.get(cell, HIDDEN)
	set_cell(cell, TILE_SOURCE_ID, MINESWEEPER_TILE_ATLAS[key])
	if flagged.has(cell):
		_overlay_layer.set_cell(cell, FLAG_SOURCE_ID, FLAG_ATLAS_COORDS)
	elif revealed.has(cell) and is_door(cell):
		_overlay_layer.set_cell(cell, DOOR_SOURCE_ID, DOOR_ATLAS_COORDS)
	else:
		_overlay_layer.erase_cell(cell)

## Only the tiles around the camera exist in the TileMapLayer; tiles that
## scroll off screen are erased and regenerated deterministically on return.
func _update_visible_tiles() -> void:
	var view_rect:Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	var top_left:Vector2i = local_to_map(to_local(view_rect.position))
	var bottom_right:Vector2i = local_to_map(to_local(view_rect.end))
	var new_rect:Rect2i = Rect2i(top_left, bottom_right - top_left + Vector2i.ONE).grow(DRAW_MARGIN)
	if new_rect == _drawn_rect:
		return

	for x in range(_drawn_rect.position.x, _drawn_rect.end.x):
		for y in range(_drawn_rect.position.y, _drawn_rect.end.y):
			var cell:Vector2i = Vector2i(x, y)
			if not new_rect.has_point(cell):
				erase_cell(cell)
				_overlay_layer.erase_cell(cell)
	for x in range(new_rect.position.x, new_rect.end.x):
		for y in range(new_rect.position.y, new_rect.end.y):
			var cell:Vector2i = Vector2i(x, y)
			if not _drawn_rect.has_point(cell):
				_draw_cell(cell)
	_drawn_rect = new_rect
