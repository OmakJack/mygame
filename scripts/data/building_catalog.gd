class_name BuildingCatalog
extends RefCounted
## Все типы зданий из data/buildings/. Загружаются при первом обращении.

const DATA_DIR: String = "res://data/buildings/"

static var _types: Dictionary[StringName, BuildingData] = {}
static var _loaded: bool = false


static func get_type(id: StringName) -> BuildingData:
	_ensure_loaded()
	return _types.get(id)


## Все типы, отсортированные по id (порядок стабилен — на нём номера кусков MeshLibrary).
static func all_types() -> Array[BuildingData]:
	_ensure_loaded()
	var result: Array[BuildingData] = []
	result.assign(_types.values())
	result.sort_custom(func(a: BuildingData, b: BuildingData) -> bool: return a.id < b.id)
	return result


static func types_for_zone(zone_type: CityGrid.Zone) -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	result.assign(all_types().filter(func(data: BuildingData) -> bool: return data.zone == zone_type))
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
		if _types.has(data.id):
			push_error("BuildingCatalog: повтор id %s в %s" % [data.id, file_name])
			continue
		_types[data.id] = data
