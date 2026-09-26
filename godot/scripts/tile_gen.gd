extends TileMapLayer

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
	0xA:Vector2i(1,0),
}

func _ready() -> void:
	self.set_cell(Vector2i(0,0),0,Vector2i(2,1))
