extends GridMap
## Показывает дороги из GameState.grid. Форма и поворот куска — по маске соседей.

# Для каждой из 16 масок: номер куска и ориентация GridMap.
var _piece_for_mask: Array[int] = []
var _orientation_for_mask: Array[int] = []


func _ready() -> void:
	mesh_library = RoadMeshes.build_library()
	cell_size = Vector3(CityGrid.CELL_SIZE, 1.0, CityGrid.CELL_SIZE)
	cell_center_y = false
	_build_mask_table()
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


## Для каждой маски ищем кусок и поворот (шаги по 90° по часовой), который её даёт.
func _build_mask_table() -> void:
	_piece_for_mask.resize(16)
	_piece_for_mask.fill(-1)
	_orientation_for_mask.resize(16)
	for piece: int in RoadMeshes.BASE_MASKS.size():
		var mask: int = RoadMeshes.BASE_MASKS[piece]
		for turns: int in 4:
			if _piece_for_mask[mask] == -1:
				_piece_for_mask[mask] = piece
				# Поворот вокруг Y на −90° переводит N в E (по часовой при виде сверху).
				_orientation_for_mask[mask] = get_orthogonal_index_from_basis(Basis(Vector3.UP, -turns * PI * 0.5))
			mask = ((mask << 1) | (mask >> 3)) & 0xF
	# Одиночная клетка без соседей рисуется прямым куском.
	_piece_for_mask[0] = RoadMeshes.Piece.STRAIGHT
	_orientation_for_mask[0] = 0


func _rebuild() -> void:
	clear()
	for cell: Vector2i in GameState.grid.road_cells:
		_update_cell(cell)


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	# Форма зависит от соседей, поэтому обновляем и их.
	var to_update: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		to_update[cell] = true
		for offset: Vector2i in CityGrid.NEIGHBORS:
			to_update[cell + offset] = true
	for cell: Vector2i in to_update:
		_update_cell(cell)


func _update_cell(cell: Vector2i) -> void:
	var grid: CityGrid = GameState.grid
	if not grid.is_in_bounds(cell):
		return
	var map_cell := Vector3i(cell.x, 0, cell.y)
	if not grid.is_road(cell):
		# Пустые клетки (например, при покраске зон) не трогаем лишний раз.
		if get_cell_item(map_cell) != INVALID_CELL_ITEM:
			set_cell_item(map_cell, INVALID_CELL_ITEM)
		return
	var mask: int = grid.get_road_mask(cell)
	# Прямая дорога по воде — мост; поворот и перекрёсток на воде — обычный кусок.
	if grid.is_water(cell):
		var along_z: int = CityGrid.DIR_N | CityGrid.DIR_S
		if mask & ~along_z == 0:
			set_cell_item(map_cell, RoadMeshes.BRIDGE_ITEM, 0)
			return
		if mask & along_z == 0:
			set_cell_item(map_cell, RoadMeshes.BRIDGE_ITEM, _orientation_for_mask[CityGrid.DIR_E | CityGrid.DIR_W])
			return
	set_cell_item(map_cell, _piece_for_mask[mask], _orientation_for_mask[mask])
