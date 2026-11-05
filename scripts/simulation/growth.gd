class_name Growth
extends RefCounted
## Застройщик по месту (переделка роста, Р2; как в Cities: Skylines и SimCity 4): размер дома решает
## город, а не жест разметки. Застройщик берёт свободную клетку зоны у самой улицы (полоса CityGrid,
## глубина 1), смотрит, сколько свободного фасада вдоль улицы и насколько глубока полоса за ним, и выбирает
## ширину дома по зоне, спросу и цене земли. Участок — от улицы на всю свободную глубину полосы (до 4),
## дом — у улицы фасадом к ней, позади — двор (CityGrid.Lot). Каждый дом смотрит на свою улицу.
## Свет и вода росту не нужны (как в SimCity): дом растёт и без них, а над ним висит значок
## (BadgeVisualizer), пока игрок не проведёт свет и воду. Запас компонента, если хватает, сразу уменьшается.
## Фаза 9: жильё не растёт в грязи; жильё и магазины выбирают землю подороже.

## С такого загрязнения жильё на клетке не растёт.
const MAX_HOME_POLLUTION: int = 40
## Сколько случайных фасадных клеток застройщик рассматривает за раз; побеждает лучший план.
const VALUE_SAMPLES: int = 6
## Сколько свободного фасада вдоль улицы смотрит застройщик в каждую сторону от клетки.
const MAX_RUN: int = 7
## Желаемая ширина дома по зоне — при спросе 0 и цене земли VALUE_MID.
const BASE_WIDTH: Dictionary[CityGrid.Zone, float] = {
	CityGrid.Zone.RESIDENTIAL: 1.4,
	CityGrid.Zone.RESIDENTIAL_HIGH: 1.8,
	CityGrid.Zone.COMMERCIAL: 1.6,
	CityGrid.Zone.COMMERCIAL_HIGH: 2.4,
	CityGrid.Zone.INDUSTRIAL: 2.4,
	CityGrid.Zone.OFFICE: 2.0,
}
## Прибавка к желаемой ширине: за спрос 1.0 и за каждое очко цены земли выше VALUE_MID (промзоне цена всё равно).
const WIDTH_PER_DEMAND: float = 1.6
const WIDTH_PER_VALUE: float = 0.04
const VALUE_MID: int = 30
## Разброс желаемой ширины: ± столько клеток случайно — улица не из одинаковых домов.
const WIDTH_JITTER: float = 0.9
## Штрафы плана (в клетках ширины): за «сироту» — клетку колонки глубже участка (её потом не достать)
## и за ряд, разорванный посередине (свободный фасад остаётся с двух сторон).
const ORPHAN_PENALTY: float = 0.5
const SPLIT_PENALTY: float = 0.4
## Насколько цена земли важнее точности плана при выборе из VALUE_SAMPLES (очков цены за клетку штрафа).
const VALUE_PER_PENALTY: float = 4.0
## Доля домов глубиной 2, когда участок позволяет (иначе — глубиной 1, двор длиннее).
const DEEP_SHARE: float = 0.6


## Ставит один дом на зону zone_type. Возвращает левую верхнюю клетку дома или NO_CELL, если места нет.
## demand — спрос категории зоны (0..1): чем выше, тем шире дома.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator,
		network: RoadNetwork, utilities: Utilities, land: LandValue = null, demand: float = 0.5) -> Vector2i:
	var types: Array[BuildingData] = BuildingCatalog.growable_types(zone_type)
	if types.is_empty():
		return CityGrid.NO_CELL
	var by_width: Dictionary[int, Array] = {}
	for data: BuildingData in types:
		if not by_width.has(data.size.x):
			by_width[data.size.x] = []
		by_width[data.size.x].append(data)

	# Фасадные клетки: свободная земля зоны у самой улицы, улица связана с трассой.
	var entry_comp: int = network.component_of.get(grid.entry, -2) if grid.has_entry() else -1
	var frontage: Array[Vector2i] = []
	for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
		if grid.get_strip_depth(cell) != 1:
			continue
		var component: int = network.component_of.get(cell + CityGrid.NEIGHBORS[grid.get_strip_dir(cell)], -1)
		if component == -1 or (grid.has_entry() and component != entry_comp):
			continue
		frontage.append(cell)
	if frontage.is_empty():
		return CityGrid.NO_CELL

	var use_value: bool = land != null and zone_type != CityGrid.Zone.INDUSTRIAL
	var best: Dictionary = {}
	var best_score: float = -INF
	for sample: int in mini(VALUE_SAMPLES, frontage.size()):
		var cell: Vector2i = frontage[rng.randi_range(0, frontage.size() - 1)]
		var value: int = land.value_at(land.land_value, grid, cell) if land != null else VALUE_MID
		var target: float = BASE_WIDTH.get(zone_type, 2.0) + clampf(demand, 0.0, 1.0) * WIDTH_PER_DEMAND \
				+ rng.randf_range(-WIDTH_JITTER, WIDTH_JITTER)
		if use_value:
			target += (value - VALUE_MID) * WIDTH_PER_VALUE
		var plan: Dictionary = plan_at(grid, land, zone_type, cell, by_width, target)
		if plan.is_empty():
			continue
		var score: float = -plan.penalty * VALUE_PER_PENALTY + (value if use_value else 0.0)
		if score > best_score:
			best_score = score
			best = plan
	if best.is_empty():
		return CityGrid.NO_CELL

	var data: BuildingData = _pick_type(best.options, best.depth, rng)
	var dir: int = best.dir
	var front: Array[Vector2i] = best.front
	var building_rect: Rect2i = _rect_inward(front, dir, data.size.y)
	var id: int = grid.place_building(data.id, building_rect.position, dir)
	if id == -1:
		return CityGrid.NO_CELL
	grid.add_lot(_rect_inward(front, dir, best.depth), dir)
	# Свет и вода — из запаса компонента, если хватает; нет — дом стоит без них (со значком),
	# пока следующий пересчёт (Utilities.distribute) не найдёт ему запас.
	var building: BuildingInstance = grid.buildings[id]
	var component: int = network.component_of.get(front[0] + CityGrid.NEIGHBORS[dir], -1)
	building.powered = utilities.spare_power.get(component, 0) >= data.power_use
	building.has_water = utilities.spare_water.get(component, 0) >= data.water_use
	if building.powered:
		utilities.spare_power[component] = utilities.spare_power.get(component, 0) - data.power_use
	if building.has_water:
		utilities.spare_water[component] = utilities.spare_water.get(component, 0) - data.water_use
	return building_rect.position


## План застройщика для фасадной клетки cell: {front — клетки фасада участка вдоль улицы, dir — сторона
## на улицу, depth — глубина участка, options — подходящие типы (ширина окна, глубина ≤ depth),
## penalty — штраф плана в клетках}. Пусто — здесь ничего не встаёт.
## Окно ряда, содержащее cell, оценивается: отличие ширины от желаемой target, «сироты» за мелкими
## колонками, разрыв ряда посередине. Жильё не встаёт там, где у улицы грязно.
static func plan_at(grid: CityGrid, land: LandValue, zone_type: CityGrid.Zone, cell: Vector2i,
		by_width: Dictionary[int, Array], target: float) -> Dictionary:
	var dir: int = grid.get_strip_dir(cell)
	if dir < 0:
		return {}
	var along: Vector2i = CityGrid.NEIGHBORS[(dir + 1) % 4]
	var run: Array[Vector2i] = [cell]
	for k: int in range(1, MAX_RUN):
		var c: Vector2i = cell - along * k
		if not _is_frontage(grid, c, zone_type, dir):
			break
		run.push_front(c)
	var seed_index: int = run.size() - 1
	for k: int in range(1, MAX_RUN):
		var c: Vector2i = cell + along * k
		if not _is_frontage(grid, c, zone_type, dir):
			break
		run.append(c)
	var depths: Array[int] = []
	var dirty: Array[bool] = []
	var residential: bool = CityGrid.is_residential(zone_type)
	for c: Vector2i in run:
		depths.append(_column_depth(grid, c, zone_type, dir))
		dirty.append(residential and land != null
				and land.value_at(land.pollution, grid, c) >= MAX_HOME_POLLUTION)

	var best: Dictionary = {}
	for width: int in by_width:
		for start: int in range(seed_index - width + 1, seed_index + 1):
			if start < 0 or start + width > run.size():
				continue
			var depth: int = CityGrid.STRIP_DEPTH
			var polluted: bool = false
			for i: int in range(start, start + width):
				depth = mini(depth, depths[i])
				polluted = polluted or dirty[i]
			if polluted:
				continue
			var options: Array = by_width[width].filter(
					func(data: BuildingData) -> bool: return data.size.y <= depth)
			if options.is_empty():
				continue
			var penalty: float = absf(width - target)
			for i: int in range(start, start + width):
				penalty += (depths[i] - depth) * ORPHAN_PENALTY
			if start > 0 and start + width < run.size():
				penalty += SPLIT_PENALTY
			if best.is_empty() or penalty < best.penalty:
				best = {
					"front": run.slice(start, start + width),
					"dir": dir,
					"depth": depth,
					"options": options,
					"penalty": penalty,
				}
	return best


## Свободная фасадная клетка той же зоны и той же улицы.
static func _is_frontage(grid: CityGrid, cell: Vector2i, zone_type: CityGrid.Zone, dir: int) -> bool:
	return grid.zoned_empty_cells[zone_type].has(cell) and grid.get_strip_dir(cell) == dir \
			and grid.get_strip_depth(cell) == 1


## Сколько свободных клеток той же зоны и полосы подряд от фасадной клетки вглубь (до STRIP_DEPTH).
static func _column_depth(grid: CityGrid, front: Vector2i, zone_type: CityGrid.Zone, dir: int) -> int:
	var inward: Vector2i = -CityGrid.NEIGHBORS[dir]
	var depth: int = 1
	while depth < CityGrid.STRIP_DEPTH:
		var c: Vector2i = front + inward * depth
		if not grid.zoned_empty_cells[zone_type].has(c) or grid.get_strip_dir(c) != dir \
				or grid.get_strip_depth(c) != depth + 1:
			break
		depth += 1
	return depth


## Тип дома: при глубоком участке чаще глубиной 2 (меньше двора), иначе — глубиной 1.
static func _pick_type(options: Array, depth: int, rng: RandomNumberGenerator) -> BuildingData:
	var deep: Array = options.filter(func(data: BuildingData) -> bool: return data.size.y >= 2)
	var shallow: Array = options.filter(func(data: BuildingData) -> bool: return data.size.y < 2)
	if not deep.is_empty() and depth >= 2 and (shallow.is_empty() or rng.randf() < DEEP_SHARE):
		return BuildingCatalog.pick_weighted(deep, rng)
	return BuildingCatalog.pick_weighted(shallow if not shallow.is_empty() else options, rng)


## Прямоугольник от клеток фасада front вглубь (от улицы в сторону −dir) на depth клеток.
static func _rect_inward(front: Array[Vector2i], dir: int, depth: int) -> Rect2i:
	var inward: Vector2i = -CityGrid.NEIGHBORS[dir]
	var lo: Vector2i = front[0]
	var hi: Vector2i = front[0]
	for c: Vector2i in front:
		for k: int in depth:
			var p: Vector2i = c + inward * k
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2i(lo, hi - lo + Vector2i.ONE)
