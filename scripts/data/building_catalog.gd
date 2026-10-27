class_name BuildingCatalog
extends RefCounted
## Все типы зданий из data/buildings/. Загружаются один раз при первом обращении;
## отсортированный список и списки по зонам собираются тогда же.

const DATA_DIR: String = "res://data/buildings/"

static var _types: Dictionary[StringName, BuildingData] = {}
static var _sorted: Array[BuildingData] = []
## Зона → Array[BuildingData]. В объявлении тип значения — просто Array (вложенные типы
## Godot не поддерживает), но кладём туда типизированные массивы.
static var _by_zone: Dictionary[CityGrid.Zone, Array] = {}
static var _empty: Array[BuildingData] = []
static var _loaded: bool = false


static func get_type(id: StringName) -> BuildingData:
	_ensure_loaded()
	return _types.get(id)


## Все типы, отсортированные по id (порядок стабилен — на нём номера кусков MeshLibrary).
## Возвращает общий массив — не изменять.
static func all_types() -> Array[BuildingData]:
	_ensure_loaded()
	return _sorted


## Типы зданий зоны. Возвращает общий массив — не изменять.
static func types_for_zone(zone_type: CityGrid.Zone) -> Array[BuildingData]:
	_ensure_loaded()
	return _by_zone.get(zone_type, _empty)


## Типы зоны, которые растут сами (BuildingData.grows): рост ставит только уровень 1.
static func growable_types(zone_type: CityGrid.Zone) -> Array[BuildingData]:
	return level_types(zone_type, 1)


## Растущие типы зоны данного уровня — для роста (ур.1) и повышения (фаза 10).
static func level_types(zone_type: CityGrid.Zone, level: int) -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for data: BuildingData in types_for_zone(zone_type):
		if data.grows and data.level == level:
			result.append(data)
	return result


## Служебные здания (zone = NONE), которые ставит игрок. Возвращает общий массив — не изменять.
static func buildable_types() -> Array[BuildingData]:
	return types_for_zone(CityGrid.Zone.NONE)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# list_directory понимает и экспортированную игру, где .tres переименованы.
	for file_name: String in ResourceLoader.list_directory(DATA_DIR):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var data := load(DATA_DIR + file_name) as BuildingData
		if data == null:
			push_error("BuildingCatalog: %s — не BuildingData" % file_name)
			continue
		if data.id.is_empty():
			push_error("BuildingCatalog: пустой id в %s" % file_name)
			continue
		if _types.has(data.id):
			push_error("BuildingCatalog: повтор id %s в %s" % [data.id, file_name])
			continue
		_types[data.id] = data
	_sorted.assign(_types.values())
	_sorted.sort_custom(func(a: BuildingData, b: BuildingData) -> bool: return a.id < b.id)
	for data: BuildingData in _sorted:
		if not _by_zone.has(data.zone):
			var list: Array[BuildingData] = []
			_by_zone[data.zone] = list
		_by_zone[data.zone].append(data)
