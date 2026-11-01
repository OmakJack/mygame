class_name Growth
extends RefCounted
## Рост зданий (как в Cities: Skylines): размер здания задаёт игрок разметкой зоны.
## Каждый участок (CityGrid.Lot, его нарезает LotPlanner) — одно здание ровно его размера, фасадом
## к дороге. Клетки зоны без участка (старые сохранения, остатки после снятия зоны) растут по одной.
## Свет и вода росту не нужны (как в SimCity): дом растёт и без них, а над ним висит значок
## (BadgeVisualizer), пока игрок не проведёт свет и воду. Запас компонента, если хватает, сразу уменьшается.
## Фаза 9: жильё не растёт в грязи; жильё и магазины выбирают землю подороже.
## Если дом во весь участок сейчас не встаёт (спрос слабый — город его «не потянет», часть участка
## в грязи), на участке ставится дом поменьше — у фасада, а если там грязно, то глубже; остаток участка
## снова делится на участки (LotPlanner). Иначе один большой дом съедал спрос или участок у заводов
## стоял пустым целиком, и рост вставал.

## С такого загрязнения жильё на клетке не растёт.
const MAX_HOME_POLLUTION: int = 40
## Из скольких случайных подходящих участков выбирается самый дорогой.
const VALUE_SAMPLES: int = 6
## Сколько клеток может занять новый дом на каждую единицу спроса (max_cells): при спросе 0.1 —
## до 2 клеток, 0.4 — до 5, 1.0 — до 11. Дом 1×1 растёт всегда.
const CELLS_PER_DEMAND: float = 10.0


## Самый большой новый дом (в клетках) при спросе demand его категории.
static func max_cells(demand: float) -> int:
	return 1 + floori(maxf(0.0, demand) * CELLS_PER_DEMAND)


## Ставит одно здание на зону zone_type. Возвращает левую верхнюю клетку или NO_CELL, если места нет.
## cells_limit — самый большой дом в клетках (по спросу, max_cells); участок крупнее застраивается частью.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator,
		network: RoadNetwork, utilities: Utilities, land: LandValue = null, cells_limit: int = 1 << 20) -> Vector2i:
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
	# Кандидаты: [прямоугольник дома, сторона фасада, компонент дорог, подходящие типы,
	# участок, который придётся поделить (дом меньше участка), или -1].
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
		var component: int = _component_of(grid, network, rect, dir)
		if component == -1 or (grid.has_entry() and component != entry_comp):
			continue
		# Самый большой дом, который сейчас встаёт на участок (во весь участок или у его начала).
		var part: Array = _fitting_part(grid, land, by_size, rect, dir, size, residential, cells_limit)
		if part.is_empty():
			continue
		var split_lot: int = lot.id if lot != null and part[0] != rect else -1
		candidates.append([part[0], dir, component, part[1], split_lot])
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
	if chosen[4] != -1:
		_split_lot(grid, zone_type, chosen[4], rect, chosen[1])
	var data: BuildingData = BuildingCatalog.pick_weighted(chosen[3], rng)
	var id: int = grid.place_building(data.id, rect.position, chosen[1])
	if id == -1:
		return CityGrid.NO_CELL
	# Свет и вода — из запаса компонента, если хватает; нет — дом стоит без них (со значком),
	# пока следующий пересчёт (Utilities.distribute) не найдёт ему запас.
	var building: BuildingInstance = grid.buildings[id]
	var component: int = chosen[2]
	building.powered = utilities.spare_power.get(component, 0) >= data.power_use
	building.has_water = utilities.spare_water.get(component, 0) >= data.water_use
	if building.powered:
		utilities.spare_power[component] = utilities.spare_power.get(component, 0) - data.power_use
	if building.has_water:
		utilities.spare_water[component] = utilities.spare_water.get(component, 0) - data.water_use
	return rect.position


## Самый большой дом для участка rect (размер типа full — вдоль фасада × вглубь): сначала во весь
## участок, иначе — поменьше: у фасада с начала участка, потом дальше вдоль и вглубь. Подходит дом,
## если он не больше cells_limit клеток (1×1 — всегда) и жильё не в грязи.
## Возвращает [прямоугольник, подходящие типы] или [], если не встаёт ничего.
static func _fitting_part(grid: CityGrid, land: LandValue, by_size: Dictionary[Vector2i, Array], rect: Rect2i,
		dir: int, full: Vector2i, residential: bool, cells_limit: int) -> Array:
	var sizes: Array[Vector2i] = []
	for size: Vector2i in by_size:
		if size.x <= full.x and size.y <= full.y and (size == Vector2i.ONE or size.x * size.y <= cells_limit):
			sizes.append(size)
	# Крупнее — раньше; при равной площади — во всю глубину участка (не оставлять узкую полосу сзади).
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x * a.y != b.x * b.y:
			return a.x * a.y > b.x * b.y
		return a.y > b.y)
	for size: Vector2i in sizes:
		var options: Array = by_size[size]
		for v: int in full.y - size.y + 1:
			for u: int in full.x - size.x + 1:
				var part: Rect2i = LotPlanner.part_of(rect, dir, u, v, size.x, size.y)
				if residential and land != null and _max_pollution(grid, land, part) >= MAX_HOME_POLLUTION:
					continue
				return [part, options]
	return []


## Дом встаёт на часть участка: часть становится своим участком, остаток делится заново.
static func _split_lot(grid: CityGrid, zone_type: CityGrid.Zone, lot_id: int, part: Rect2i, dir: int) -> void:
	var lot: CityGrid.Lot = grid.lots.get(lot_id)
	if lot == null:
		return
	var rest: Array[Vector2i] = []
	for cell: Vector2i in lot.cells():
		if not part.has_point(cell):
			rest.append(cell)
	grid.dissolve_lot(lot_id)
	grid.add_lot(part, dir)
	for plan: Array in LotPlanner.plan(grid, rest, zone_type):
		grid.add_lot(plan[0], plan[1])


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
