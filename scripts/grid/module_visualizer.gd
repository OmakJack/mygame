class_name ModuleVisualizer
extends Node3D
## Модули станций (StationModules) на площадках участка: ветряки, насосы, башни, служебная дорога.
## Само здание станции рисует BuildingVisualizer; здесь — по мультимешу на вид модуля (как роторы
## в RotorVisualizer). Модуль стоит на своей площадке в координатах здания, поэтому поворачивается
## вместе со станцией — и по клеткам, и под углом дороги (CityGrid.building_transform).
## Роторы ветряков-модулей крутит RotorVisualizer.

## Мультимеш по id модуля.
var _layers: Dictionary[StringName, MultiMeshInstance3D] = {}


func _ready() -> void:
	Events.cells_changed.connect(func(_cells: Array[Vector2i]) -> void: _sync())
	Events.grid_reset.connect(_sync)
	_sync()


## Сколько модулей каждого вида нарисовано (для проверок): id модуля → число.
func counts() -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for id: StringName in _layers:
		if _layers[id].multimesh.instance_count > 0:
			result[id] = _layers[id].multimesh.instance_count
	return result


## Где нарисован i-й модуль вида id (для проверок).
func transform_of(id: StringName, index: int) -> Transform3D:
	return _layers[id].multimesh.get_instance_transform(index)


func _sync() -> void:
	var grid: CityGrid = GameState.grid
	var places: Dictionary[StringName, Array] = {}
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			continue
		var items: Array[Array] = StationModules.placed(building)
		if items.is_empty():
			continue
		var place: Transform3D = grid.building_transform(building)
		for item: Array in items:
			var module: StationModules.Module = item[0]
			if not places.has(module.id):
				places[module.id] = []
			places[module.id].append(place * StationModules.pad_transform(item[1]))
	for id: StringName in places:
		if not _layers.has(id):
			_layers[id] = _make_layer(StationModules.module(id))
	for id: StringName in _layers:
		var list: Array = places.get(id, [])
		var multimesh: MultiMesh = _layers[id].multimesh
		if multimesh.instance_count != list.size():
			multimesh.instance_count = list.size()
		for i: int in list.size():
			multimesh.set_instance_transform(i, list[i])
			# Службы не перекрашиваются (как BuildingPalette.custom_for у зданий без зоны).
			multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))


func _make_layer(module: StationModules.Module) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = BuildingPalette.convert(StationModules.mesh_of(module))
	add_child(layer)
	return layer
