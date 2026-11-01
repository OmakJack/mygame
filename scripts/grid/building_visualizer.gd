extends Node3D
## Показывает здания из GameState.grid: по мультимешу на тип здания. Стройку (construction_ticks > 0)
## рисует ConstructionVisualizer; здесь у неё только номер куска (_construction_item) для get_cell_item.
## Мультимеш, а не GridMap, — чтобы у каждого здания был свой цвет (BuildingPalette, INSTANCE_CUSTOM).
## Поворот — по BuildingInstance.orientation (по часовой, как у дорог).

## Номер «куска» стройплощадки — после всех типов (его слой пустой).
var _construction_item: int = 0
var _item_for_type: Dictionary[StringName, int] = {}
var _layers: Array[MultiMeshInstance3D] = []
## Клетка → номер куска, который там нарисован (все клетки многоклеточного здания).
var _item_at: Dictionary[Vector2i, int] = {}
## Клетка → id здания, которое там нарисовано.
var _building_at_vis: Dictionary[Vector2i, int] = {}
## id здания → номер куска, которым оно сейчас нарисовано.
var _drawn_item: Dictionary[int, int] = {}
## id здания → массив его клеток на момент отрисовки.
var _drawn_cells: Dictionary[int, Array] = {}
## Номер куска → список id зданий в этом слое.
var _ids_of: Array[Array] = []


func _ready() -> void:
	var types: Array[BuildingData] = BuildingCatalog.all_types()
	for item: int in types.size():
		_item_for_type[types[item].id] = item
		_add_layer(BuildingPalette.convert(BuildingMeshes.mesh_for(types[item])))
	_construction_item = types.size()
	_add_layer(ArrayMesh.new())
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
	_ids_of.append([])


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
	_building_at_vis.clear()
	_drawn_item.clear()
	_drawn_cells.clear()
	for ids: Array in _ids_of:
		ids.clear()
	for building: BuildingInstance in GameState.grid.buildings.values():
		_register_building(building)
	for item: int in _layers.size():
		_write_layer(item)


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	var dirty: Dictionary[int, bool] = {}
	var affected: Dictionary[int, bool] = {}
	var grid: CityGrid = GameState.grid
	for cell: Vector2i in cells:
		if not grid.is_in_bounds(cell):
			continue
		if _building_at_vis.has(cell):
			affected[_building_at_vis[cell]] = true
		var current: BuildingInstance = grid.get_building_at(cell)
		if current != null:
			affected[current.id] = true
	for id: int in affected:
		var building: BuildingInstance = grid.buildings.get(id)
		var new_item: int = _item_for(building) if building != null else -1
		if _drawn_item.has(id):
			var old_item: int = _drawn_item[id]
			if building != null and new_item == old_item and building.cells() == _drawn_cells[id]:
				dirty[old_item] = true
				continue
			_unregister_building(id)
			dirty[old_item] = true
		if building != null and new_item >= 0:
			_register_building(building)
			dirty[new_item] = true
	for item: int in dirty:
		_write_layer(item)


func _register_building(building: BuildingInstance) -> void:
	var item: int = _item_for(building)
	if item < 0:
		return
	var occupied: Array[Vector2i] = building.cells()
	_drawn_item[building.id] = item
	_drawn_cells[building.id] = occupied
	_ids_of[item].append(building.id)
	for c: Vector2i in occupied:
		_building_at_vis[c] = building.id
		_item_at[c] = item


func _unregister_building(id: int) -> void:
	var old_item: int = _drawn_item[id]
	_ids_of[old_item].erase(id)
	for c: Vector2i in _drawn_cells[id]:
		if _building_at_vis.get(c, -1) == id:
			_building_at_vis.erase(c)
			_item_at.erase(c)
	_drawn_item.erase(id)
	_drawn_cells.erase(id)


func _item_for(building: BuildingInstance) -> int:
	if building.construction_ticks > 0:
		return _construction_item
	if not _item_for_type.has(building.type_id):
		push_warning("BuildingVisualizer: неизвестный тип %s" % building.type_id)
		return -1
	return _item_for_type[building.type_id]


## Переписывает все экземпляры куска: позиция (по центру участка), поворот и цвет каждого здания.
func _write_layer(item: int) -> void:
	var grid: CityGrid = GameState.grid
	var ids: Array = _ids_of[item]
	var multimesh: MultiMesh = _layers[item].multimesh
	if item == _construction_item:
		multimesh.instance_count = 0
		return
	multimesh.instance_count = ids.size()
	for i: int in ids.size():
		var building: BuildingInstance = grid.buildings.get(ids[i])
		if building == null:
			continue
		var basis := Basis(Vector3.UP, -building.orientation * PI * 0.5)
		var center: Vector3 = grid.footprint_center(building.cell, building.size)
		multimesh.set_instance_transform(i, Transform3D(basis, center))
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		multimesh.set_instance_custom_data(i, BuildingPalette.custom_for(building, data) if data != null else Color())
