class_name CitySerializer
extends RefCounted
## Город ↔ словарь для JSON. Без файлов и сигналов — файлы читает и пишет SaveManager.
## Правило совместимости: незнакомые поля пропускаем, отсутствующие берём по умолчанию.
## JSON.parse_string отдаёт все числа как float — целые поля приводим явно (_int).

const FORMAT: String = "citybuilder-save"
const VERSION: int = 1
const MIN_SIZE: int = 16
const MAX_SIZE: int = 256


## Результат загрузки. grid собран «в стороне» и ещё нигде не используется.
class LoadResult extends RefCounted:
	var ok: bool = false
	var error: String = ""
	var warnings: Array[String] = []
	var grid: CityGrid
	var name: String = ""
	var money: int = 0
	var tax_rate: int = 0
	var day: int = 0


static func to_dict(grid: CityGrid, city_name: String, money: int, tax_rate: int, day: int,
		population: int) -> Dictionary:
	var roads := PackedByteArray()
	roads.resize(grid.size * grid.size)
	roads.fill(0)
	for cell: Vector2i in grid.road_cells:
		roads[grid.index_of(cell)] = 1
	var buildings: Array[Dictionary] = []
	for building: BuildingInstance in grid.buildings.values():
		buildings.append({
			"id": building.id,
			"type": String(building.type_id),
			"x": building.cell.x,
			"y": building.cell.y,
			"o": building.orientation,
			"nr": building.no_road_ticks,
			"np": building.no_power_ticks,
			"nw": building.no_water_ticks,
		})
	return {
		"format": FORMAT,
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"meta": {"name": city_name, "day": day, "population": population, "money": money},
		"state": {"money": money, "tax_rate": tax_rate, "day": day},
		"grid": {
			"size": grid.size,
			"next_building_id": grid.next_building_id,
			"roads": Marshalls.raw_to_base64(roads),
			"zones": Marshalls.raw_to_base64(grid.zone),
		},
		"buildings": buildings,
	}


static func from_dict(data: Variant) -> LoadResult:
	var result := LoadResult.new()
	if not data is Dictionary:
		return _fail(result, "файл не похож на сохранение")
	var root: Dictionary = data
	if root.get("format") != FORMAT:
		return _fail(result, "это не сохранение города")
	var version: int = _int(root.get("version"), -1)
	if version < 1:
		return _fail(result, "неизвестная версия сохранения")
	if version > VERSION:
		return _fail(result, "сохранение из более новой версии игры (%d)" % version)
	root = _migrate(root, version)

	var grid_data: Dictionary = _dict(root.get("grid"))
	var size: int = _int(grid_data.get("size"), 0)
	if size < MIN_SIZE or size > MAX_SIZE:
		return _fail(result, "неверный размер карты")
	var roads: PackedByteArray = _bytes(grid_data.get("roads"))
	var zones: PackedByteArray = _bytes(grid_data.get("zones"))
	if roads.size() != size * size or zones.size() != size * size:
		return _fail(result, "повреждены слои карты")

	var grid := CityGrid.new(size)
	var zones_on_roads: int = 0
	for i: int in size * size:
		if roads[i] > 1 or zones[i] >= CityGrid.Zone.size():
			return _fail(result, "повреждены слои карты")
		if roads[i] == 1:
			grid.tile_type[i] = CityGrid.Tile.ROAD
			if zones[i] != CityGrid.Zone.NONE:
				zones_on_roads += 1
		else:
			grid.zone[i] = zones[i]
	if zones_on_roads > 0:
		result.warnings.append("зона снята с %d клеток дороги" % zones_on_roads)
	grid.next_building_id = maxi(0, _int(grid_data.get("next_building_id"), 0))

	var entries: Array[Dictionary] = []
	var raw_buildings: Variant = root.get("buildings", [])
	if not raw_buildings is Array:
		return _fail(result, "повреждён список зданий")
	for entry: Variant in raw_buildings:
		if entry is Dictionary:
			entries.append(entry)
		else:
			result.warnings.append("пропущена повреждённая запись здания")
	# Здания — по возрастанию id: на этом порядке держится раздача света и воды.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _int(a.get("id"), -1) < _int(b.get("id"), -1))
	var occupied: Dictionary[Vector2i, bool] = {}
	for entry: Dictionary in entries:
		var problem: String = _load_building(grid, entry, occupied)
		if not problem.is_empty():
			result.warnings.append(problem)
	grid.rebuild_caches()

	var state: Dictionary = _dict(root.get("state"))
	result.money = _int(state.get("money"), Economy.START_MONEY)
	result.tax_rate = clampi(_int(state.get("tax_rate"), Economy.DEFAULT_TAX_RATE),
			Economy.MIN_TAX_RATE, Economy.MAX_TAX_RATE)
	result.day = maxi(0, _int(state.get("day"), 0))
	var meta: Dictionary = _dict(root.get("meta"))
	result.name = str(meta.get("name", "Город"))
	result.grid = grid
	result.ok = true
	return result


## Добавляет здание в grid.buildings. Возвращает причину пропуска или "".
static func _load_building(grid: CityGrid, entry: Dictionary, occupied: Dictionary[Vector2i, bool]) -> String:
	var id: int = _int(entry.get("id"), -1)
	var type_id := StringName(str(entry.get("type", "")))
	var cell := Vector2i(_int(entry.get("x"), -1), _int(entry.get("y"), -1))
	var orientation: int = _int(entry.get("o"), -1)
	if id < 0 or grid.buildings.has(id):
		return "пропущено здание с неверным или повторным номером"
	if BuildingCatalog.get_type(type_id) == null:
		return "пропущено здание неизвестного типа «%s»" % type_id
	if not grid.is_in_bounds(cell):
		return "пропущено здание за картой"
	if grid.tile_type[grid.index_of(cell)] == CityGrid.Tile.ROAD or occupied.has(cell):
		return "пропущено здание на занятой клетке %s" % cell
	if orientation < 0 or orientation > 3:
		return "пропущено здание с неверным поворотом"
	var building := BuildingInstance.new(id, type_id, cell, orientation)
	building.no_road_ticks = maxi(0, _int(entry.get("nr"), 0))
	building.no_power_ticks = maxi(0, _int(entry.get("np"), 0))
	building.no_water_ticks = maxi(0, _int(entry.get("nw"), 0))
	grid.buildings[id] = building
	occupied[cell] = true
	return ""


## Место под миграции старых версий: _migrate_v1_to_v2 и т. д. Пока версия одна.
static func _migrate(root: Dictionary, _version: int) -> Dictionary:
	return root


## Целое из JSON: int или float без дробной части; иначе default.
static func _int(value: Variant, default: int) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value):
		return int(value)
	return default


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _bytes(value: Variant) -> PackedByteArray:
	return Marshalls.base64_to_raw(value) if value is String else PackedByteArray()


static func _fail(result: LoadResult, message: String) -> LoadResult:
	result.ok = false
	result.error = message
	return result
