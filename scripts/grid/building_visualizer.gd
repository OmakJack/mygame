extends Node3D
## Показывает здания из GameState.grid: по мультимешу на тип здания (и один — на стройплощадки).
## Мультимеш, а не GridMap, — чтобы у каждого здания был свой цвет (BuildingPalette, INSTANCE_CUSTOM).
## Поворот — по BuildingInstance.orientation (по часовой, как у дорог).

## Номер «куска» стройплощадки — после всех типов.
var _construction_item: int = 0
var _item_for_type: Dictionary[StringName, int] = {}
var _layers: Array[MultiMeshInstance3D] = []
## Клетка → номер куска, который там нарисован.
var _item_at: Dictionary[Vector2i, int] = {}
## Номер куска → клетки с ним (порядок = номера экземпляров мультимеша).
var _cells_of: Array[Array] = []


func _ready() -> void:
	var types: Array[BuildingData] = BuildingCatalog.all_types()
	for item: int in types.size():
		_item_for_type[types[item].id] = item
		_add_layer(BuildingPalette.convert(BuildingMeshes.mesh_for(types[item])))
	_construction_item = types.size()
	_add_layer(BuildingMeshes.construction_mesh())
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _add_layer(mesh: Mesh) -> void:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = mesh
	add_child(layer)
	_layers.append(layer)
	_cells_of.append([])


## Номер куска в клетке (как GridMap.get_cell_item); −1 — пусто.
func get_cell_item(map_cell: Vector3i) -> int:
	return _item_at.get(Vector2i(map_cell.x, map_cell.z), -1)


## Клетки со зданиями (как GridMap.get_used_cells).
func get_used_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: Vector2i in _item_at:
		result.append(Vector3i(cell.x, 0, cell.y))
	return result


func _rebuild() -> void:
	_item_at.clear()
	for cells: Array in _cells_of:
		cells.clear()
	for building: BuildingInstance in GameState.grid.buildings.values():
		var item: int = _item_for(building)
		if item >= 0:
			_item_at[building.cell] = item
			_cells_of[item].append(building.cell)
	for item: int in _layers.size():
		_write_layer(item)


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	var dirty: Dictionary[int, bool] = {}
	var grid: CityGrid = GameState.grid
	for cell: Vector2i in cells:
		if not grid.is_in_bounds(cell):
			continue
		var old: int = _item_at.get(cell, -1)
		var building: BuildingInstance = grid.get_building_at(cell)
		var item: int = _item_for(building) if building != null else -1
		if old == item and item != -1:
			# Тот же кусок, но здание могло смениться (снос и рост за один тик) — цвет обновим.
			dirty[item] = true
			continue
		if old >= 0:
			_cells_of[old].erase(cell)
			_item_at.erase(cell)
			dirty[old] = true
		if item >= 0:
			_cells_of[item].append(cell)
			_item_at[cell] = item
			dirty[item] = true
	for item: int in dirty:
		_write_layer(item)


func _item_for(building: BuildingInstance) -> int:
	if building.construction_ticks > 0:
		return _construction_item
	if not _item_for_type.has(building.type_id):
		push_warning("BuildingVisualizer: неизвестный тип %s" % building.type_id)
		return -1
	return _item_for_type[building.type_id]


## Переписывает все экземпляры куска: позиция, поворот и цвет каждого здания.
func _write_layer(item: int) -> void:
	var grid: CityGrid = GameState.grid
	var cells: Array = _cells_of[item]
	var multimesh: MultiMesh = _layers[item].multimesh
	multimesh.instance_count = cells.size()
	for i: int in cells.size():
		var building: BuildingInstance = grid.get_building_at(cells[i])
		var basis := Basis(Vector3.UP, -building.orientation * PI * 0.5)
		multimesh.set_instance_transform(i, Transform3D(basis, grid.grid_to_world(cells[i])))
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		multimesh.set_instance_custom_data(i, BuildingPalette.custom_for(building, data) if data != null else Color())
