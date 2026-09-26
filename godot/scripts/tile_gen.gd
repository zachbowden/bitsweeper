extends TileMapLayer

## Emitted when the player clicks a hidden tile that contains a mine.
signal mine_triggered(cell:Vector2i)

const TILE_SOURCE_ID:int = 0
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
@export_range(0.0, 1.0, 0.01) var mine_density:float = 0.16

var noise:FastNoiseLite = FastNoiseLite.new()
## Every tile the player has revealed, mapped to its adjacent mine count.
## Hidden tiles are never stored; they are derived from the noise on demand.
## Tiles are erased from the TileMapLayer when off screen, so this is what
## keeps explored areas revealed when the player comes back to them.
var revealed:Dictionary[Vector2i, int] = {}
var _drawn_rect:Rect2i = Rect2i()

func _ready() -> void:
	# Value noise sampled on integer lattice points at frequency 1 returns the
	# raw per-lattice hash, i.e. an uncorrelated, roughly uniform value in
	# [-1, 1] for every (x, y, level) - exactly what we want for mine placement.
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.seed = randi()

	clear()
	for x in range(-SPAWN_SAFE_RADIUS, SPAWN_SAFE_RADIUS + 1):
		for y in range(-SPAWN_SAFE_RADIUS, SPAWN_SAFE_RADIUS + 1):
			reveal(Vector2i(x, y))
	_update_visible_tiles()

func _process(_delta:float) -> void:
	_update_visible_tiles()

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell:Vector2i = local_to_map(get_local_mouse_position())
		if revealed.has(cell):
			return
		if is_mine(cell):
			mine_triggered.emit(cell)
		else:
			reveal(cell)
		get_viewport().set_input_as_handled()

func is_mine(cell:Vector2i) -> bool:
	if absi(cell.x) <= SPAWN_SAFE_RADIUS and absi(cell.y) <= SPAWN_SAFE_RADIUS:
		return false
	var value:float = noise.get_noise_3d(cell.x, cell.y, GLOBAL.level)
	# Map [-1, 1] to [0, 1] and compare against the density.
	return (value + 1.0) * 0.5 < mine_density

func count_adjacent_mines(cell:Vector2i) -> int:
	var count:int = 0
	for offset in NEIGHBOURS:
		if is_mine(cell + offset):
			count += 1
	return count

## Reveals a tile; if it has no adjacent mines, flood-reveals the connected
## empty area and its numbered border, like classic minesweeper.
func reveal(start:Vector2i) -> void:
	if revealed.has(start) or is_mine(start):
		return
	var stack:Array[Vector2i] = [start]
	var processed:int = 0
	while not stack.is_empty() and processed < MAX_FLOOD_TILES:
		var cell:Vector2i = stack.pop_back()
		if revealed.has(cell):
			continue
		var count:int = count_adjacent_mines(cell)
		revealed[cell] = count
		processed += 1
		if _drawn_rect.has_point(cell):
			set_cell(cell, TILE_SOURCE_ID, MINESWEEPER_TILE_ATLAS[count])
		if count == 0:
			for offset in NEIGHBOURS:
				var next:Vector2i = cell + offset
				if not revealed.has(next):
					stack.push_back(next)

func _draw_cell(cell:Vector2i) -> void:
	var key:int = revealed.get(cell, HIDDEN)
	set_cell(cell, TILE_SOURCE_ID, MINESWEEPER_TILE_ATLAS[key])

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
	for x in range(new_rect.position.x, new_rect.end.x):
		for y in range(new_rect.position.y, new_rect.end.y):
			var cell:Vector2i = Vector2i(x, y)
			if not _drawn_rect.has_point(cell):
				_draw_cell(cell)
	_drawn_rect = new_rect
