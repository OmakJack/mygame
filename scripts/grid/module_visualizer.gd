class_name ModuleVisualizer
extends Node3D
## Модули станций (StationModules): встроенный — на площадке участка (поворачивается со станцией),
## достроенные — на своих клетках рядом со станцией (ветряки, насосы, башни) — по мультимешу на вид
## модуля (как роторы в RotorVisualizer); служебная дорога — одним полотном по её клеткам: квадрат на
## клетке и проезд к соседним клеткам дороги и к участку станции, к модулям у дороги — гравийный съезд.
## Само здание станции рисует BuildingVisualizer, роторы ветряков — RotorVisualizer.

## Ширина полотна служебной дороги и его высота над землёй, м.
const ROAD_WIDTH: float = 0.9
const ROAD_HEIGHT: float = 0.03
## Съезд от дороги к ветряку или насосу (до края клетки дороги): ширина, м.
const SPUR_WIDTH: float = 0.36
## Асфальт — как проезд на участке станции, съезд — гравий.
const ROAD_COLOR := Color(0.2, 0.21, 0.23)
const SPUR_COLOR := Color(0.55, 0.52, 0.47)

## Мультимеш по id модуля.
var _layers: Dictionary[StringName, MultiMeshInstance3D] = {}
var _roads := MeshInstance3D.new()
## Сколько клеток служебной дороги нарисовано (для проверок).
var road_cells: int = 0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	_roads.material_override = material
	add_child(_roads)
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
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	road_cells = 0
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			continue
		for item: Array in StationModules.placed(grid, building):
			var module: StationModules.Module = item[0]
			if not places.has(module.id):
				places[module.id] = []
			places[module.id].append(item[1])
		_add_road(grid, building, road)
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
	_roads.mesh = road.commit() if road_cells > 0 else null


## Полотно служебной дороги станции: квадрат на клетке, проезд к соседней дороге и к участку станции
## во всю ширину, к модулю у дороги — короткий съезд.
func _add_road(grid: CityGrid, building: BuildingInstance, road: SurfaceTool) -> void:
	var station: Array[Vector2i] = building.cells()
	for i: int in building.modules.size():
		if building.modules[i] != StationModules.ROAD:
			continue
		road_cells += 1
		var cell: Vector2i = building.module_cells[i]
		var middle: Vector3 = grid.grid_to_world(cell)
		var half: float = ROAD_WIDTH * 0.5
		_quad(road, middle, Vector2(half, half), ROAD_COLOR)
		for step: Vector2i in StationModules.NEIGHBORS:
			var near: Vector2i = cell + step
			var index: int = StationModules.index_at(building, near)
			var width: float = half
			var color: Color = ROAD_COLOR
			if station.has(near) or (index != -1 and building.modules[index] == StationModules.ROAD):
				pass
			elif index != -1:
				width = SPUR_WIDTH * 0.5
				color = SPUR_COLOR
			else:
				continue
			# Проезд от края квадрата до края клетки в сторону соседа.
			var reach: float = CityGrid.CELL_SIZE * 0.5
			var dir := Vector3(step.x, 0.0, step.y)
			var center: Vector3 = middle + dir * (half + reach) * 0.5
			var extent := Vector2(absf(dir.x) * (reach - half) * 0.5 + absf(dir.z) * width,
					absf(dir.z) * (reach - half) * 0.5 + absf(dir.x) * width)
			_quad(road, center, extent, color)


## Плоский прямоугольник на высоте полотна: середина center, полуразмеры extent по x и z.
static func _quad(road: SurfaceTool, center: Vector3, extent: Vector2, color: Color) -> void:
	var y: float = ROAD_HEIGHT
	var a := Vector3(center.x - extent.x, y, center.z - extent.y)
	var b := Vector3(center.x + extent.x, y, center.z - extent.y)
	var c := Vector3(center.x + extent.x, y, center.z + extent.y)
	var d := Vector3(center.x - extent.x, y, center.z + extent.y)
	road.set_normal(Vector3.UP)
	road.set_color(color)
	for p: Vector3 in [a, b, c, a, c, d]:
		road.add_vertex(p)


func _make_layer(module: StationModules.Module) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = BuildingPalette.convert(StationModules.mesh_of(module))
	add_child(layer)
	return layer
