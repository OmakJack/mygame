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
## plot_size != Vector2i.ZERO — только типы указанного размера участка.
static func level_types(zone_type: CityGrid.Zone, level: int,
		plot_size: Vector2i = Vector2i.ZERO) -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for data: BuildingData in types_for_zone(zone_type):
		if data.grows and data.level == level and (plot_size == Vector2i.ZERO or data.size == plot_size):
			result.append(data)
	return result


## Типы следующего уровня для повышения дома типа data — дом растёт, а не подменяется чужим:
## у семейства — следующая стадия того же семейства; у модели без стадий (Kenney, Gemini — один вид на все уровни)
## — дома с семействами: старый дом перестраивают в больший, дальше он растёт уже сам.
## Нет таких — любые типы следующего уровня того же размера (как раньше).
static func next_level_types(data: BuildingData) -> Array[BuildingData]:
	var options: Array[BuildingData] = level_types(data.zone, data.level + 1, data.size)
	var staged: Array[BuildingData] = []
	for option: BuildingData in options:
		if option.family != &"" and (data.family == &"" or option.family == data.family):
			staged.append(option)
	return staged if not staged.is_empty() else options


## Доля выбора «предпочтительных» типов (пак Gemini), если такие есть среди вариантов.
const PREFERRED_SHARE: float = 0.75


## Случайный тип из options: сначала группа (пак Gemini — в PREFERRED_SHARE случаев), внутри — по весу.
static func pick_weighted(options: Array, rng: RandomNumberGenerator) -> BuildingData:
	var preferred: Array = options.filter(func(data: BuildingData) -> bool: return data.preferred)
	var others: Array = options.filter(func(data: BuildingData) -> bool: return not data.preferred)
	var group: Array = others
	if not preferred.is_empty() and (others.is_empty() or rng.randf() < PREFERRED_SHARE):
		group = preferred
	var weights := PackedFloat32Array()
	for data: BuildingData in group:
		weights.append(maxf(0.0, data.weight))
	return group[maxi(0, rng.rand_weighted(weights))]


## Служебные здания (zone = NONE), которые ставит игрок. Возвращает общий массив — не изменять.
static func buildable_types() -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for data: BuildingData in types_for_zone(CityGrid.Zone.NONE):
		if data.buildable:
			result.append(data)
	return result


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
	# Многоэтажки, офисы и составные участки 2..7 клеток, которые строит код (их нет в data/buildings).
	for data: BuildingData in ProceduralBuildings.types():
		_types[data.id] = data
	for data: BuildingData in CompoundBuildings.types():
		_types[data.id] = data
	# Жилые дома в стадиях по уровням (одно здание на участок).
	for data: BuildingData in ProceduralHouses.types():
		_types[data.id] = data
	_sorted.assign(_types.values())
	_sorted.sort_custom(func(a: BuildingData, b: BuildingData) -> bool: return a.id < b.id)
	for data: BuildingData in _sorted:
		if not _by_zone.has(data.zone):
			var list: Array[BuildingData] = []
			_by_zone[data.zone] = list
		_by_zone[data.zone].append(data)
