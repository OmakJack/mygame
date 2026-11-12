class_name StationModules
extends RefCounted
## Станции с модулями, как в SimCity: игрок ставит здание станции (участок 4×3 клетки, на нём —
## диспетчерская и первый, встроенный модуль), а потом сам расставляет модули на карте рядом с ней:
## кнопка в карточке «Инфо» станции включает постановку (BuildTool, режим MODULE), модуль встаёт на
## клетку, куда щёлкнули.
## - Служебная дорога — бесплатная, тянется по клеткам от участка станции или от своего конца;
## - ветряки встают вдоль служебной дороги или вплотную к участку станции;
## - насосы и башни водозабора — вплотную к станции, к её служебной дороге или к другим своим модулям.
## Модуль занимает клетку карты (CityGrid.add_station_module): клетка — здания станции, щелчок по
## ней открывает карточку станции. Бульдозер сносит модуль по одному (деньги не возвращаются); модуль,
## на котором держатся другие (кусок дороги, насос в цепочке), не сносится, пока те стоят.
## Тип станции — обычный BuildingData (wind_station, water_station): его свет, вода и содержание —
## это сама станция со встроенным модулем. Достроенные модули — у здания (BuildingInstance.modules
## и module_cells, по порядку постройки); их свет, вода и содержание прибавляются сверху.
## Раскладка участка — та же, что в моделях (tools/blender/make_stations.py): менять вместе.

## Модуль станции.
class Module extends RefCounted:
	var id: StringName
	var name: String
	var cost: int = 0
	## Содержание за тик, сверх станции.
	var upkeep: int = 0
	## Сколько даёт света и воды и сколько берёт света (насосам нужен свет).
	var power: int = 0
	var water: int = 0
	var power_use: int = 0
	## Тип здания, чья модель (и ротор) у модуля, — ветряки и башня остались от прежних отдельных
	## зданий. Пусто — своя модель model.
	var visual: StringName
	## Путь к своей модели (res://…glb).
	var model: String = ""
	## Служебная дорога: тянется по клеткам, на ней держатся ветряки.
	var is_road: bool = false
	## Ветряк: встаёт только вдоль служебной дороги или у самого участка станции.
	var along_road: bool = false

	func _init(p_id: StringName, p_name: String, p_cost: int, p_upkeep: int) -> void:
		id = p_id
		name = p_name
		cost = p_cost
		upkeep = p_upkeep


const ROAD: StringName = &"service_road"
## Площадка встроенного модуля на участке: середина в координатах здания (x — вдоль улицы, z — вглубь,
## фасад на −z), м.
const BUILTIN_PAD := Vector2(1, -2)
## Высота площадки над землёй, м: встроенный модуль стоит на ней.
const PAD_TOP: float = 0.07
## Сколько модулей можно достроить одной станции (дорога не в счёт) и сколько клеток служебной дороги.
const MAX_MODULES: int = 12
const MAX_ROAD: int = 48
const MODELS: String = "res://assets/models/blender/stations/"
const NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Станции: тип здания → {встроенный модуль, модули на выбор}.
const STATIONS: Dictionary[StringName, Dictionary] = {
	&"wind_station": {"builtin": &"wind_small", "modules": [&"wind_small", &"wind_large", ROAD]},
	&"water_station": {"builtin": &"water_pump", "modules": [&"water_pump", &"water_tower", ROAD]},
}

static var _modules: Dictionary[StringName, Module] = {}
static var _meshes: Dictionary[StringName, Mesh] = {}


static func _ensure() -> void:
	if not _modules.is_empty():
		return
	var small := Module.new(&"wind_small", "Ветряк", 80, 1)
	small.power = 25
	small.visual = &"wind_turbine_01"
	small.along_road = true
	var large := Module.new(&"wind_large", "Вертикальный ветряк", 180, 2)
	large.power = 55
	large.visual = &"wind_turbine_02"
	large.along_road = true
	var pump := Module.new(&"water_pump", "Насос", 70, 1)
	pump.water = 40
	pump.power_use = 1
	pump.model = MODELS + "water_pump.glb"
	var tower := Module.new(&"water_tower", "Водонапорная башня", 160, 2)
	tower.water = 100
	tower.power_use = 2
	tower.visual = &"water_tower_01"
	var road := Module.new(ROAD, "Служебная дорога", 0, 0)
	road.is_road = true
	for module: Module in [small, large, pump, tower, road]:
		_modules[module.id] = module


static func is_station(type_id: StringName) -> bool:
	return STATIONS.has(type_id)


## Модуль по id или null.
static func module(id: StringName) -> Module:
	_ensure()
	return _modules.get(id)


## Модули, которые можно достроить станции типа type_id (пусто — не станция).
static func options(type_id: StringName) -> Array[Module]:
	_ensure()
	var result: Array[Module] = []
	if STATIONS.has(type_id):
		for id: StringName in STATIONS[type_id].modules:
			result.append(_modules[id])
	return result


## Сколько достроено модулей (без служебной дороги) и сколько клеток дороги.
static func module_count(building: BuildingInstance) -> int:
	return building.modules.size() - building.modules.count(ROAD)


static func road_count(building: BuildingInstance) -> int:
	return building.modules.count(ROAD)


## Номер модуля станции на клетке или −1.
static func index_at(building: BuildingInstance, cell: Vector2i) -> int:
	return building.module_cells.find(cell)


## Что стоит у станции: [[модуль, трансформ в мире], …] — встроенный на своей площадке участка,
## достроенные — на своих клетках (повёрнуты как станция). Служебная дорога сюда не входит — её рисует
## ModuleVisualizer полотном. Не станция — пусто.
static func placed(grid: CityGrid, building: BuildingInstance) -> Array[Array]:
	_ensure()
	var result: Array[Array] = []
	if not STATIONS.has(building.type_id):
		return result
	var place: Transform3D = grid.building_transform(building)
	result.append([_modules[STATIONS[building.type_id].builtin],
			place * Transform3D(Basis.IDENTITY, Vector3(BUILTIN_PAD.x, PAD_TOP, BUILTIN_PAD.y))])
	for i: int in building.modules.size():
		var item: Module = _modules.get(building.modules[i])
		if item == null or item.is_road:
			continue
		result.append([item, Transform3D(place.basis, grid.grid_to_world(building.module_cells[i]))])
	return result


## Почему модуль module_id нельзя достроить станции вообще ("" — можно): не тот модуль или предел.
static func why_not(building: BuildingInstance, module_id: StringName) -> String:
	_ensure()
	if not STATIONS.has(building.type_id) or not STATIONS[building.type_id].modules.has(module_id):
		return "этой станции такой модуль не подходит"
	if module_id == ROAD:
		return "служебная дорога уже %d клеток — длиннее нельзя" % MAX_ROAD if road_count(building) >= MAX_ROAD else ""
	if module_count(building) >= MAX_MODULES:
		return "у станции уже %d модулей — больше нельзя" % MAX_MODULES
	return ""


## Почему модуль нельзя поставить на клетку cell ("" — можно). planned — клетки служебной дороги,
## которые кладутся тем же протягиванием перед этой (их считаем уже лежащими).
static func why_not_at(grid: CityGrid, building: BuildingInstance, module_id: StringName, cell: Vector2i,
		planned: Dictionary[Vector2i, bool] = {}) -> String:
	var reason: String = why_not(building, module_id)
	if not reason.is_empty():
		return reason
	if module_id == ROAD and road_count(building) + planned.size() >= MAX_ROAD:
		return "служебная дорога уже %d клеток — длиннее нельзя" % MAX_ROAD
	if not grid.is_in_bounds(cell):
		return "за краем карты"
	if grid.is_water(cell):
		return "на воде нельзя"
	if grid.tile_type[grid.index_of(cell)] != CityGrid.Tile.EMPTY or planned.has(cell):
		return "клетка занята"
	var item: Module = module(module_id)
	if not _touches(building, item, cell, planned):
		if item.is_road:
			return "дорога тянется от участка станции или от своего конца"
		if item.along_road:
			return "ветряк ставится вдоль служебной дороги или у самой станции"
		return "ставится вплотную к станции, её дороге или другим её модулям"
	return ""


## Клетки, куда модуль можно поставить сейчас (для подсветки): соседи участка и модулей станции.
static func free_cells(grid: CityGrid, building: BuildingInstance, module_id: StringName) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not why_not(building, module_id).is_empty():
		return result
	var seen: Dictionary[Vector2i, bool] = {}
	for base: Vector2i in building.cells() + building.module_cells:
		for step: Vector2i in NEIGHBORS:
			var cell: Vector2i = base + step
			if seen.has(cell):
				continue
			seen[cell] = true
			if why_not_at(grid, building, module_id, cell).is_empty():
				result.append(cell)
	return result


## Клетки служебной дороги, которые положит протягивание по path (по порядку): клетки самой станции
## и уже лежащая дорога пропускаются, на первой клетке, куда дорогу положить нельзя, путь кончается.
static func road_plan(grid: CityGrid, building: BuildingInstance, path: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var planned: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in path:
		if grid.is_in_bounds(cell) and grid.get_building_at(cell) == building:
			var index: int = index_at(building, cell)
			if index == -1 or building.modules[index] == ROAD:
				continue
		if not why_not_at(grid, building, ROAD, cell, planned).is_empty():
			break
		planned[cell] = true
		result.append(cell)
	return result


## Держится ли модуль item на клетке cell: за участок станции, за клетки planned (дорога того же
## протягивания) или за модули с номерами из held — за дорогу, а насос и башня и за другие насосы и башни.
static func _holds(building: BuildingInstance, item: Module, cell: Vector2i, held: Dictionary[int, bool],
		planned: Dictionary[Vector2i, bool] = {}) -> bool:
	var station: Array[Vector2i] = building.cells()
	for step: Vector2i in NEIGHBORS:
		var near: Vector2i = cell + step
		if station.has(near) or planned.has(near):
			return true
		var index: int = index_at(building, near)
		if index == -1 or not held.has(index):
			continue
		var other: Module = module(building.modules[index])
		if other != null and (other.is_road or (not item.is_road and not item.along_road and not other.along_road)):
			return true
	return false


## Касается ли модуль на клетке того, за что держится, — при всех модулях станции на месте.
static func _touches(building: BuildingInstance, item: Module, cell: Vector2i,
		planned: Dictionary[Vector2i, bool] = {}) -> bool:
	var all: Dictionary[int, bool] = {}
	for i: int in building.modules.size():
		all[i] = true
	return _holds(building, item, cell, all, planned)


## Номера модулей, что держатся (от участка — по дороге и цепочкам насосов), если модуля skip нет.
static func _held(building: BuildingInstance, skip: int = -1) -> Dictionary[int, bool]:
	var held: Dictionary[int, bool] = {}
	var grew: bool = true
	while grew:
		grew = false
		for i: int in building.modules.size():
			if i == skip or held.has(i):
				continue
			var item: Module = module(building.modules[i])
			if item != null and _holds(building, item, building.module_cells[i], held):
				held[i] = true
				grew = true
	return held


## Почему модуль номер index нельзя снести ("" — можно): его нет или на нём держатся другие.
static func why_not_remove(grid: CityGrid, building: BuildingInstance, index: int) -> String:
	if index < 0 or index >= building.modules.size():
		return "такого модуля нет"
	if _held(building, index).size() < building.modules.size() - 1:
		if building.modules[index] == ROAD:
			return "на этом куске дороги держатся ветряки или дальняя дорога — сначала уберите их"
		return "на нём держатся другие модули — сначала уберите их"
	return ""


## Сносит модуль номер index (деньги не возвращаются). Клетка модуля или NO_CELL — не снесён.
static func remove(grid: CityGrid, building: BuildingInstance, index: int) -> Vector2i:
	if not why_not_remove(grid, building, index).is_empty():
		return CityGrid.NO_CELL
	return grid.remove_station_module(building, index)


## Ставит модуль на клетку (деньги списывает вызывающий). true — поставлен.
static func add(grid: CityGrid, building: BuildingInstance, module_id: StringName, cell: Vector2i) -> bool:
	if not why_not_at(grid, building, module_id, cell).is_empty():
		return false
	return grid.add_station_module(building, module_id, cell)


## После загрузки: модули, которые не подходят станции или не держатся, убираются (повреждённое
## сохранение). Сколько убрано.
static func prune(grid: CityGrid, building: BuildingInstance) -> int:
	var removed: int = 0
	for i: int in range(building.modules.size() - 1, -1, -1):
		if module(building.modules[i]) == null or not STATIONS.has(building.type_id) 				or not STATIONS[building.type_id].modules.has(building.modules[i]):
			grid.remove_station_module(building, i)
			removed += 1
	# Кто не держится, тот и других не держит — убираем всех разом, с конца.
	var held: Dictionary[int, bool] = _held(building)
	for i: int in range(building.modules.size() - 1, -1, -1):
		if not held.has(i):
			grid.remove_station_module(building, i)
			removed += 1
	return removed


## Старые сохранения (модули на площадках участка): модуль ставится на ближайшую к станции клетку,
## куда его можно поставить; служебная дорога старого вида не переносится. Сколько поставлено.
static func place_legacy(grid: CityGrid, building: BuildingInstance, ids: Array[StringName]) -> int:
	var placed_count: int = 0
	var center: Vector2 = Vector2(building.cell) + Vector2(building.size) * 0.5
	for id: StringName in ids:
		if id == ROAD or module(id) == null:
			continue
		var cells: Array[Vector2i] = free_cells(grid, building, id)
		if cells.is_empty():
			continue
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: float = (Vector2(a) + Vector2.ONE * 0.5).distance_squared_to(center)
			var db: float = (Vector2(b) + Vector2.ONE * 0.5).distance_squared_to(center)
			return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
		if grid.add_station_module(building, id, cells[0]):
			placed_count += 1
	return placed_count


## Свет, вода, расход света и содержание здания вместе с достроенными модулями.
static func power_supply(building: BuildingInstance, data: BuildingData) -> int:
	var total: int = data.power_supply
	for id: StringName in building.modules:
		total += module(id).power if module(id) != null else 0
	return total


static func water_supply(building: BuildingInstance, data: BuildingData) -> int:
	var total: int = data.water_supply
	for id: StringName in building.modules:
		total += module(id).water if module(id) != null else 0
	return total


static func power_use(building: BuildingInstance, data: BuildingData) -> int:
	var total: int = data.power_use
	for id: StringName in building.modules:
		total += module(id).power_use if module(id) != null else 0
	return total


static func upkeep(building: BuildingInstance, data: BuildingData) -> int:
	var total: int = data.upkeep
	for id: StringName in building.modules:
		total += module(id).upkeep if module(id) != null else 0
	return total


## Тип здания, чей вид (модель и ротор) у модуля, или null — своя модель.
static func visual_data(item: Module) -> BuildingData:
	return BuildingCatalog.get_type(item.visual) if item.visual != &"" else null


static var _ghosts: Dictionary[StringName, Mesh] = {}


## Модель модуля для постановки (полупрозрачная под мышью): основание и ротор ветряка одним мешем.
static func ghost_mesh(item: Module) -> Mesh:
	if item.is_road:
		return null
	if not _ghosts.has(item.id):
		var visual: BuildingData = visual_data(item)
		if visual == null or visual.rotor == null or visual.model == null:
			_ghosts[item.id] = mesh_of(item)
		else:
			var tool := SurfaceTool.new()
			var base: Mesh = mesh_of(item)
			for surface: int in base.get_surface_count():
				tool.append_from(base, surface, Transform3D.IDENTITY)
			var rotor: Mesh = ModelLoader.merge(visual.rotor)
			var seat: Transform3D = BuildingMeshes.model_placement(visual) * Transform3D(Basis.IDENTITY, visual.rotor_pivot)
			for surface: int in rotor.get_surface_count():
				tool.append_from(rotor, surface, seat)
			_ghosts[item.id] = tool.commit()
	return _ghosts[item.id]


## Меш модуля в координатах его клетки, фасадом на −Z (у дороги меша нет — её рисует ModuleVisualizer).
static func mesh_of(item: Module) -> Mesh:
	if item.is_road:
		return null
	if not _meshes.has(item.id):
		var data: BuildingData = visual_data(item)
		if data != null:
			_meshes[item.id] = BuildingMeshes.mesh_for(data)
		else:
			# Модели станций — в координатах игры после разворота на 180° (как model_turns = 2).
			_meshes[item.id] = ModelLoader.merge(load(item.model), Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	return _meshes[item.id]
