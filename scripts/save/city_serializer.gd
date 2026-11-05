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
	## Игровое время, минуты (GameState.minutes).
	var minutes: int = GameTime.START_MINUTES
	var rank: int = -1
	## Случайность симуляции: [зерно, положение]; пусто — старое сохранение (случайное зерно).
	var rng_state: Array[int] = []


static func to_dict(grid: CityGrid, city_name: String, money: int, tax_rate: int, minutes: int,
		population: int, rank: int = -1, rng: RandomNumberGenerator = null) -> Dictionary:
	var roads := PackedByteArray()
	roads.resize(grid.size * grid.size)
	roads.fill(0)
	# Дороги — их тип (RoadTypes.Type): 1 — улица, как в старых сохранениях.
	for cell: Vector2i in grid.road_cells:
		roads[grid.index_of(cell)] = grid.road_type[grid.index_of(cell)]
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
			"nh": building.unhappy_ticks,
			"ct": building.construction_ticks,
			"ctt": building.construction_total,
			"age": building.age_ticks,
			"ab": 1 if building.abandoned else 0,
			"rt": building.recover_ticks,
		})
	return {
		"format": FORMAT,
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"meta": {"name": city_name, "day": GameTime.day_of(minutes), "population": population, "money": money},
		# Зерно и положение случайности — строками: в JSON числа становятся float и теряют 64-битную точность.
		"state": {"money": money, "tax_rate": tax_rate, "minutes": minutes, "rank": rank,
				"rng": [str(rng.seed), str(rng.state)] if rng != null else []},
		"grid": {
			"size": grid.size,
			"next_building_id": grid.next_building_id,
			"roads": Marshalls.raw_to_base64(roads),
			"zones": Marshalls.raw_to_base64(grid.zone),
			"water": Marshalls.raw_to_base64(grid.water),
			"entry": [grid.entry.x, grid.entry.y, grid.entry_dir, grid.highway_cells.size()] if grid.has_entry() else [],
			"lots": _lots_to_list(grid),
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
		if roads[i] >= RoadTypes.Type.size() or zones[i] >= CityGrid.Zone.size():
			return _fail(result, "повреждены слои карты")
		if roads[i] > 0:
			grid.tile_type[i] = CityGrid.Tile.ROAD
			grid.road_type[i] = roads[i]
			if zones[i] != CityGrid.Zone.NONE:
				zones_on_roads += 1
		else:
			grid.zone[i] = zones[i]
	if zones_on_roads > 0:
		result.warnings.append("зона снята с %d клеток дороги" % zones_on_roads)
	# Вода (фаза 9): нет поля — суша; битое поле — суша с предупреждением.
	if grid_data.has("water"):
		var water: PackedByteArray = _bytes(grid_data.get("water"))
		if water.size() == size * size:
			for i: int in size * size:
				grid.water[i] = 1 if water[i] == 1 else 0
		else:
			result.warnings.append("повреждён слой воды — карта без воды")
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
	# Участки: [x, y, ширина, глубина по сетке, сторона фасада]; нет поля — участков нет.
	# Участок без дома (старые сохранения: его нарезала разметка) молча отбрасывается — застройщик нарежет заново.
	var raw_lots: Variant = grid_data.get("lots", [])
	if raw_lots is Array:
		var skipped: int = 0
		for entry_lot: Variant in raw_lots:
			if _is_empty_lot(grid, entry_lot):
				continue
			if not _load_lot(grid, entry_lot):
				skipped += 1
		if skipped > 0:
			result.warnings.append("пропущено участков: %d" % skipped)
	# Въезд трассы: [x, y, направление, длина]; нет поля — без въезда (старые сохранения растут как раньше).
	var entry: Variant = grid_data.get("entry", [])
	if entry is Array and (entry as Array).size() == 4:
		var edge := Vector2i(_int(entry[0], -1), _int(entry[1], -1))
		if grid.is_in_bounds(edge):
			grid.set_entry(edge, clampi(_int(entry[2], 0), 0, 3), clampi(_int(entry[3], 1), 1, 16))

	var state: Dictionary = _dict(root.get("state"))
	result.money = _int(state.get("money"), Economy.START_MONEY)
	result.tax_rate = clampi(_int(state.get("tax_rate"), Economy.DEFAULT_TAX_RATE),
			Economy.MIN_TAX_RATE, Economy.MAX_TAX_RATE)
	# Игровое время в минутах; в старых сохранениях тик был часом (hours) или днём (day).
	if state.has("minutes"):
		result.minutes = maxi(0, _int(state.get("minutes"), GameTime.START_MINUTES))
	elif state.has("hours"):
		result.minutes = GameTime.from_old_hours(_int(state.get("hours"), 0))
	else:
		result.minutes = GameTime.from_old_days(_int(state.get("day"), 0))
	# Звание (фаза 10): нет поля — −1, Simulation выставит по населению без награды.
	result.rank = clampi(_int(state.get("rank"), -1), -1, Ranks.NAMES.size() - 1)
	var rng: Variant = state.get("rng", [])
	if rng is Array and (rng as Array).size() == 2 and str(rng[0]).is_valid_int() and str(rng[1]).is_valid_int():
		result.rng_state = [str(rng[0]).to_int(), str(rng[1]).to_int()]
	var meta: Dictionary = _dict(root.get("meta"))
	result.name = str(meta.get("name", "Город"))
	result.grid = grid
	result.ok = true
	return result


static func _lots_to_list(grid: CityGrid) -> Array:
	var list: Array = []
	for lot: CityGrid.Lot in grid.lots.values():
		list.append([lot.rect.position.x, lot.rect.position.y, lot.rect.size.x, lot.rect.size.y, lot.dir])
	return list


## Участок из сохранения без единого здания на нём (до застройщика по месту участки резала разметка).
static func _is_empty_lot(grid: CityGrid, entry: Variant) -> bool:
	if not entry is Array or (entry as Array).size() != 5:
		return false
	var rect := Rect2i(_int(entry[0], -1), _int(entry[1], -1), _int(entry[2], 0), _int(entry[3], 0))
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if grid.is_in_bounds(Vector2i(x, y)) and grid.get_building_at(Vector2i(x, y)) != null:
				return false
	return true


## Участок из сохранения: все клетки на карте и с зоной, не больше 7 × STRIP_DEPTH клеток (дом и двор).
## false — пропущен.
static func _load_lot(grid: CityGrid, entry: Variant) -> bool:
	if not entry is Array or (entry as Array).size() != 5:
		return false
	var rect := Rect2i(_int(entry[0], -1), _int(entry[1], -1), _int(entry[2], 0), _int(entry[3], 0))
	var dir: int = _int(entry[4], -1)
	if rect.size.x < 1 or rect.size.y < 1 or rect.size.x * rect.size.y > Growth.MAX_RUN * CityGrid.STRIP_DEPTH or dir < 0 or dir > 3:
		return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not grid.is_in_bounds(cell) or grid.get_zone(cell) == CityGrid.Zone.NONE or grid.get_lot(cell) != null:
				return false
	grid.add_lot(rect, dir)
	return true


## Добавляет здание в grid.buildings. Возвращает причину пропуска или "".
static func _load_building(grid: CityGrid, entry: Dictionary, occupied: Dictionary[Vector2i, bool]) -> String:
	var id: int = _int(entry.get("id"), -1)
	var type_id := StringName(str(entry.get("type", "")))
	var cell := Vector2i(_int(entry.get("x"), -1), _int(entry.get("y"), -1))
	var orientation: int = _int(entry.get("o"), -1)
	if id < 0 or grid.buildings.has(id):
		return "пропущено здание с неверным или повторным номером"
	var data: BuildingData = BuildingCatalog.get_type(type_id)
	if data == null:
		return "пропущено здание неизвестного типа «%s»" % type_id
	if orientation < 0 or orientation > 3:
		return "пропущено здание с неверным поворотом"
	var span: Vector2i = data.footprint(orientation)
	var building := BuildingInstance.new(id, type_id, cell, orientation, span)
	var cells: Array[Vector2i] = building.cells()
	for c: Vector2i in cells:
		if not grid.is_in_bounds(c):
			return "пропущено здание за картой"
		if grid.tile_type[grid.index_of(c)] == CityGrid.Tile.ROAD or grid.is_water(c) or occupied.has(c):
			return "пропущено здание на занятой клетке %s" % c
	building.no_road_ticks = maxi(0, _int(entry.get("nr"), 0))
	building.no_power_ticks = maxi(0, _int(entry.get("np"), 0))
	building.no_water_ticks = maxi(0, _int(entry.get("nw"), 0))
	building.unhappy_ticks = maxi(0, _int(entry.get("nh"), 0))
	# Стройплощадка: нет поля — здание готово (старые сохранения).
	building.construction_ticks = maxi(0, _int(entry.get("ct"), 0))
	building.construction_total = maxi(building.construction_ticks, _int(entry.get("ctt"), 0))
	# Возраст: нет поля — считаем с загрузки (старые сохранения).
	building.age_ticks = maxi(0, _int(entry.get("age"), 0))
	# Брошенное здание (Decay): нет поля — жилое (старые сохранения).
	building.abandoned = _int(entry.get("ab"), 0) == 1 and data.zone != CityGrid.Zone.NONE
	building.recover_ticks = maxi(0, _int(entry.get("rt"), 0)) if building.abandoned else 0
	grid.buildings[id] = building
	for c: Vector2i in cells:
		occupied[c] = true
		# Под служебным зданием зоны нет (как при постройке): после сноса там не вырастет дом.
		if data.zone == CityGrid.Zone.NONE:
			grid.zone[grid.index_of(c)] = CityGrid.Zone.NONE
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
