class_name Growth
extends RefCounted
## Рост зданий (как в Cities: Skylines): размер здания задаёт игрок разметкой зоны.
## Каждый участок (CityGrid.Lot, его нарезает LotPlanner) — одно здание ровно его размера, фасадом
## к дороге. Клетки зоны без участка (старые сохранения, остатки после снятия зоны) растут по одной.
## Выбирается свободный участок, у компонента дорог которого хватает света и воды; запас сразу уменьшается.
## Фаза 9: жильё не растёт в грязи; жильё и магазины выбирают землю подороже.

## С такого загрязнения жильё на клетке не растёт.
const MAX_HOME_POLLUTION: int = 40
## Из скольких случайных подходящих участков выбирается самый дорогой.
const VALUE_SAMPLES: int = 6


## Ставит одно здание на зону zone_type. Возвращает левую верхнюю клетку или NO_CELL, если места нет.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator,
		network: RoadNetwork, utilities: Utilities, land: LandValue = null) -> Vector2i:
	var types: Array[BuildingData] = BuildingCatalog.growable_types(zone_type)
	if types.is_empty():
		return CityGrid.NO_CELL
	var by_size: Dictionary[Vector2i, Array] = {}
	for data: BuildingData in types:
		if not by_size.has(data.size):
			by_size[data.size] = []
		by_size[data.size].append(data)

	var empty_set: Dictionary = grid.zoned_empty_cells[zone_type]
	var residential: bool = CityGrid.is_residential(zone_type)
	var entry_comp: int = network.component_of.get(grid.entry, -2) if grid.has_entry() else -1
	# Кандидаты: [прямоугольник, сторона фасада, компонент дорог, размер типа].
	var candidates: Array[Array] = []
	var seen: Dictionary[int, bool] = {}
	var unbuildable: Array[int] = []
	for cell: Vector2i in empty_set:
		var lot: CityGrid.Lot = grid.get_lot(cell)
		var rect := Rect2i(cell, Vector2i.ONE)
		var dir: int
		var size := Vector2i.ONE
		if lot != null:
			if seen.has(lot.id):
				continue
			seen[lot.id] = true
			rect = lot.rect
			dir = lot.dir
			size = lot.building_size()
			if not by_size.has(size):
				# Зону перекрасили, а у новой зоны нет зданий такого размера — участок распадается.
				unbuildable.append(lot.id)
				continue
			if not _all_free(rect, empty_set):
				continue
		else:
			dir = _best_1x1_dir(grid, cell)
		if residential and land != null and _max_pollution(grid, land, rect) >= MAX_HOME_POLLUTION:
			continue
		var component: int = _component_of(grid, network, rect, dir)
		if component == -1 or (grid.has_entry() and component != entry_comp):
			continue
		if not _component_fits(utilities, component, by_size[size][0]):
			continue
		candidates.append([rect, dir, component, size])
	for id: int in unbuildable:
		grid.dissolve_lot(id)
	if candidates.is_empty():
		return CityGrid.NO_CELL

	var pick: int = rng.randi_range(0, candidates.size() - 1)
	# Промзоне всё равно, где расти; жильё и магазины — на земле подороже.
	if land != null and zone_type != CityGrid.Zone.INDUSTRIAL:
		var best: int = _value(grid, land, candidates[pick][0])
		for sample: int in VALUE_SAMPLES - 1:
			var other: int = rng.randi_range(0, candidates.size() - 1)
			var value: int = _value(grid, land, candidates[other][0])
			if value > best:
				best = value
				pick = other
	var chosen: Array = candidates[pick]
	var rect: Rect2i = chosen[0]
	var options: Array = by_size[chosen[3]]
	var data: BuildingData = BuildingCatalog.pick_weighted(options, rng)
	var id: int = grid.place_building(data.id, rect.position, chosen[1])
	if id == -1:
		return CityGrid.NO_CELL
	# Новый дом сразу со светом и водой: запас под него мы только что проверили.
	var building: BuildingInstance = grid.buildings[id]
	building.powered = true
	building.has_water = true
	utilities.spare_power[chosen[2]] -= data.power_use
	utilities.spare_water[chosen[2]] -= data.water_use
	return rect.position


static func _all_free(rect: Rect2i, empty_set: Dictionary) -> bool:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if not empty_set.has(Vector2i(x, y)):
				return false
	return true


static func _max_pollution(grid: CityGrid, land: LandValue, rect: Rect2i) -> int:
	var worst: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			worst = maxi(worst, land.value_at(land.pollution, grid, Vector2i(x, y)))
	return worst


## Средняя цена земли участка.
static func _value(grid: CityGrid, land: LandValue, rect: Rect2i) -> int:
	var sum: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			sum += land.value_at(land.land_value, grid, Vector2i(x, y))
	return roundi(float(sum) / (rect.size.x * rect.size.y))


## Компонент дорог участка: по дороге у фасада, иначе — ближайшей к любой его клетке.
static func _component_of(grid: CityGrid, network: RoadNetwork, rect: Rect2i, dir: int) -> int:
	for cell: Vector2i in BuildingInstance.edge_cells(rect.position, rect.size, dir):
		var road: Vector2i = cell + CityGrid.NEIGHBORS[dir]
		if grid.is_access_road(road):
			return network.component_of.get(road, -1)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var component: int = network.component_for(grid, Vector2i(x, y))
			if component != -1:
				return component
	return -1


static func _best_1x1_dir(grid: CityGrid, cell: Vector2i) -> int:
	for dir: int in 4:
		if grid.is_access_road(cell + CityGrid.NEIGHBORS[dir]):
			return dir
	return maxi(0, grid.find_nearest_road_dir(cell))


static func _component_fits(utilities: Utilities, component: int, data: BuildingData) -> bool:
	return utilities.spare_power.get(component, 0) >= data.power_use \
			and utilities.spare_water.get(component, 0) >= data.water_use
