class_name StationModules
extends RefCounted
## Станции с модулями, как в SimCity: игрок ставит здание станции на участок 4×3 клетки, а потом
## достраивает на нём модули — ветряки, насосы, башни, служебную дорогу (карточка «Инфо» станции).
## Тип станции — обычный BuildingData (wind_station, water_station): его свет, вода и содержание —
## это сама станция с первым, встроенным модулем на площадке 0. Достроенные модули — у здания
## (BuildingInstance.modules, по порядку постройки); их свет, вода и содержание прибавляются сверху.
## Площадок шесть: три — сразу, ещё три открывает модуль «Служебная дорога» (сам площадку не занимает).
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
	## Тип здания, чья модель (и ротор) стоит на площадке, — ветряки и башня остались от прежних
	## отдельных зданий. Пусто — своя модель model.
	var visual: StringName
	## Путь к своей модели (res://…glb).
	var model: String = ""
	## Служебная дорога: площадку не занимает, открывает остальные; модель — в координатах участка.
	var is_road: bool = false

	func _init(p_id: StringName, p_name: String, p_cost: int, p_upkeep: int) -> void:
		id = p_id
		name = p_name
		cost = p_cost
		upkeep = p_upkeep


const ROAD: StringName = &"service_road"
## Площадки участка: середина в координатах здания (x — вдоль улицы, z — вглубь, фасад на −z), м.
const PADS: Array[Vector2] = [Vector2(1, -2), Vector2(-1, 2), Vector2(1, 2), Vector2(3, -2), Vector2(3, 2),
		Vector2(-3, 2)]
## Сколько площадок доступно без служебной дороги.
const BASE_PADS: int = 3
## Высота площадки над землёй, м: модуль стоит на ней.
const PAD_TOP: float = 0.07
const MODELS: String = "res://assets/models/blender/stations/"

## Станции: тип здания → {встроенный модуль (на площадке 0), модули на выбор}.
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
	var large := Module.new(&"wind_large", "Вертикальный ветряк", 180, 2)
	large.power = 55
	large.visual = &"wind_turbine_02"
	var pump := Module.new(&"water_pump", "Насос", 70, 1)
	pump.water = 40
	pump.power_use = 1
	pump.model = MODELS + "water_pump.glb"
	var tower := Module.new(&"water_tower", "Водонапорная башня", 160, 2)
	tower.water = 100
	tower.power_use = 2
	tower.visual = &"water_tower_01"
	var road := Module.new(ROAD, "Служебная дорога", 60, 0)
	road.is_road = true
	road.model = MODELS + "station_road.glb"
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


static func has_road(building: BuildingInstance) -> bool:
	return building.modules.has(ROAD)


## Сколько площадок у станции: три или шесть со служебной дорогой.
static func pad_count(building: BuildingInstance) -> int:
	return PADS.size() if has_road(building) else BASE_PADS


## Сколько площадок занято: встроенный модуль и достроенные (дорога не в счёт).
static func used_pads(building: BuildingInstance) -> int:
	var used: int = 1
	for id: StringName in building.modules:
		if id != ROAD:
			used += 1
	return used


## Модули станции по площадкам: [[модуль, номер площадки], …]; у дороги номер −1. Не станция — пусто.
static func placed(building: BuildingInstance) -> Array[Array]:
	_ensure()
	var result: Array[Array] = []
	if not STATIONS.has(building.type_id):
		return result
	result.append([_modules[STATIONS[building.type_id].builtin], 0])
	var pad: int = 1
	for id: StringName in building.modules:
		var item: Module = _modules.get(id)
		if item == null:
			continue
		if item.is_road:
			result.append([item, -1])
		elif pad < PADS.size():
			result.append([item, pad])
			pad += 1
	return result


## Почему модуль нельзя достроить ("" — можно): не тот модуль, дорога уже есть, нет свободной площадки.
static func why_not(building: BuildingInstance, module_id: StringName) -> String:
	_ensure()
	if not STATIONS.has(building.type_id) or not STATIONS[building.type_id].modules.has(module_id):
		return "этой станции такой модуль не подходит"
	if module_id == ROAD:
		return "служебная дорога уже есть" if has_road(building) else ""
	if used_pads(building) >= pad_count(building):
		return "все площадки заняты" if has_road(building) else "площадки заняты — нужна служебная дорога"
	return ""


## Достраивает модуль (деньги списывает вызывающий). true — достроен.
static func add(building: BuildingInstance, module_id: StringName) -> bool:
	if not why_not(building, module_id).is_empty():
		return false
	building.modules.append(module_id)
	return true


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


## Меш модуля в координатах площадки (дорога — в координатах участка), фасадом на −Z.
static func mesh_of(item: Module) -> Mesh:
	if not _meshes.has(item.id):
		var data: BuildingData = visual_data(item)
		if data != null:
			_meshes[item.id] = BuildingMeshes.mesh_for(data)
		else:
			# Модели станций — в координатах игры после разворота на 180° (как model_turns = 2).
			_meshes[item.id] = ModelLoader.merge(load(item.model), Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	return _meshes[item.id]


## Где модуль стоит на участке (координаты здания): середина площадки на её высоте; дорога — в нуле.
static func pad_transform(pad: int) -> Transform3D:
	if pad < 0 or pad >= PADS.size():
		return Transform3D.IDENTITY
	return Transform3D(Basis.IDENTITY, Vector3(PADS[pad].x, PAD_TOP, PADS[pad].y))
