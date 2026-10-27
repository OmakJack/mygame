extends GridMap
## Показывает здания из GameState.grid. Поворот — по BuildingInstance.orientation.

var _item_for_type: Dictionary[StringName, int] = {}
## Кусок стройплощадки — последний в библиотеке (BuildingMeshes.build_library).
var _construction_item: int = 0
## Ориентация GridMap для направлений N/E/S/W (поворот по часовой, как у дорог).
var _orientation_for_dir: Array[int] = []


func _ready() -> void:
	var types: Array[BuildingData] = BuildingCatalog.all_types()
	mesh_library = BuildingMeshes.build_library(types)
	_construction_item = types.size()
	for item: int in types.size():
		_item_for_type[types[item].id] = item
	for dir: int in 4:
		_orientation_for_dir.append(get_orthogonal_index_from_basis(Basis(Vector3.UP, -dir * PI * 0.5)))
	cell_size = Vector3(CityGrid.CELL_SIZE, 1.0, CityGrid.CELL_SIZE)
	cell_center_y = false
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	clear()
	for building: BuildingInstance in GameState.grid.buildings.values():
		_update_cell(building.cell)


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		_update_cell(cell)


func _update_cell(cell: Vector2i) -> void:
	var grid: CityGrid = GameState.grid
	if not grid.is_in_bounds(cell):
		return
	var map_cell := Vector3i(cell.x, 0, cell.y)
	var building: BuildingInstance = grid.get_building_at(cell)
	if building == null:
		if get_cell_item(map_cell) != INVALID_CELL_ITEM:
			set_cell_item(map_cell, INVALID_CELL_ITEM)
		return
	if not _item_for_type.has(building.type_id):
		push_warning("BuildingVisualizer: неизвестный тип %s" % building.type_id)
		return
	var item: int = _construction_item if building.construction_ticks > 0 else _item_for_type[building.type_id]
	set_cell_item(map_cell, item, _orientation_for_dir[building.orientation])
