class_name Growth
extends RefCounted
## Рост зданий: выбирает пустой участок с зоной, у компонента дорог которого хватает
## свободного света и воды, и ставит на него здание от 1 до 7 клеток (если позволяет место).
## Фаза 9: жильё не растёт в грязи; жильё и магазины выбирают землю подороже.

## С такого загрязнения жильё на клетке не растёт.
const MAX_HOME_POLLUTION: int = 40
## Из скольких случайных подходящих клеток выбирается самая дорогая.
const VALUE_SAMPLES: int = 6
## Веса корзин размеров [1 кл., 2..4 кл., 5..7 кл.], когда на участке хватает места.
const BUCKET_WEIGHTS: Array[float] = [0.3, 0.35, 0.35]
## Сколько клеток зоны осматривать в поисках крупного участка: у одной случайной клетки длинный
## участок вдоль улицы (5–7 клеток) находится редко — мелкие дома успевают разбить ряд.
const LOT_SEEDS: int = 8


## Ставит одно здание на зону zone_type. Возвращает левую верхнюю клетку или NO_CELL, если места нет.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator,
		network: RoadNetwork, utilities: Utilities, land: LandValue = null) -> Vector2i:
	var types: Array[BuildingData] = BuildingCatalog.growable_types(zone_type)
	if types.is_empty():
		return CityGrid.NO_CELL

	var by_size: Dictionary[Vector2i, Array] = {}
	var min_power: int = 1 << 20
	var min_water: int = 1 << 20
	for data: BuildingData in types:
		if not by_size.has(data.size):
			by_size[data.size] = []
		by_size[data.size].append(data)
		min_power = mini(min_power, data.power_use)
		min_water = mini(min_water, data.water_use)

	# Нет запаса даже на самый маленький дом ни в одном компоненте — не перебираем клетки.
	if not _has_any_capacity(utilities, min_power, min_water):
		return CityGrid.NO_CELL

	var empty_set: Dictionary = grid.zoned_empty_cells[zone_type]
	var residential: bool = CityGrid.is_residential(zone_type)
	var entry_comp: int = network.component_of.get(grid.entry, -2) if grid.has_entry() else -1
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in empty_set:
		if residential and land != null and land.value_at(land.pollution, grid, cell) >= MAX_HOME_POLLUTION:
			continue
		var component: int = network.component_for(grid, cell)
		if component == -1:
			continue
		# Новые жители и фирмы приезжают по трассе: участок должен быть связан с въездом.
		if grid.has_entry() and component != entry_comp:
			continue
		if utilities.spare_power.get(component, 0) >= min_power \
				and utilities.spare_water.get(component, 0) >= min_water:
			candidates.append(cell)
	if candidates.is_empty():
		return CityGrid.NO_CELL

	var pick: int = rng.randi_range(0, candidates.size() - 1)
	# Промзоне всё равно, где расти; жильё и магазины — на земле подороже.
	if land != null and zone_type != CityGrid.Zone.INDUSTRIAL:
		var best: int = land.value_at(land.land_value, grid, candidates[pick])
		for sample: int in VALUE_SAMPLES - 1:
			var other: int = rng.randi_range(0, candidates.size() - 1)
			var value: int = land.value_at(land.land_value, grid, candidates[other])
			if value > best:
				best = value
				pick = other
	var seed_cell: Vector2i = candidates[pick]

	# Собираем все подходящие варианты участков по корзинам площади: 1, 2..4, 5..7+.
	# Одиночный дом — только у выбранной (самой дорогой) клетки; крупные — ещё у нескольких случайных.
	var seeds: Array[Vector2i] = [seed_cell]
	for i: int in mini(LOT_SEEDS - 1, candidates.size() - 1):
		seeds.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	var buckets: Array[Array] = [[], [], []]
	var seen_lots: Dictionary = {}
	for plot_size: Vector2i in by_size:
		var sample_data: BuildingData = by_size[plot_size][0]
		var area: int = plot_size.x * plot_size.y
		if area == 1:
			var comp_1x1: int = network.component_for(grid, seed_cell)
			if comp_1x1 != -1 and _component_fits(utilities, comp_1x1, sample_data):
				var dir_1x1: int = _best_1x1_dir(grid, seed_cell)
				if dir_1x1 != -1:
					buckets[0].append([plot_size, seed_cell, dir_1x1, comp_1x1])
			continue
		var bucket_idx: int = 2 if area >= 5 else 1
		for seed: Vector2i in seeds:
			for dir: int in 4:
				var span: Vector2i = sample_data.footprint(dir)
				for dy: int in span.y:
					for dx: int in span.x:
						var top_left := Vector2i(seed.x - dx, seed.y - dy)
						var lot_key := [plot_size, top_left, dir]
						if seen_lots.has(lot_key):
							continue
						seen_lots[lot_key] = true
						var comp: int = _fit_lot(grid, empty_set, residential, land, network, utilities,
								sample_data, top_left, span, dir, entry_comp)
						if comp != -1:
							buckets[bucket_idx].append([plot_size, top_left, dir, comp])

	var chosen_bucket: Array = _pick_bucket(buckets, rng)
	if chosen_bucket.is_empty():
		return CityGrid.NO_CELL
	var placement: Array = chosen_bucket[rng.randi_range(0, chosen_bucket.size() - 1)]
	var chosen_size: Vector2i = placement[0]
	var top_left: Vector2i = placement[1]
	var orientation: int = placement[2]
	var component: int = placement[3]
	var options: Array = by_size[chosen_size]
	var data: BuildingData = options[rng.randi_range(0, options.size() - 1)]

	var id: int = grid.place_building(data.id, top_left, orientation)
	if id == -1:
		return CityGrid.NO_CELL
	# Новый дом сразу со светом и водой: запас под него мы только что проверили.
	var building: BuildingInstance = grid.buildings[id]
	building.powered = true
	building.has_water = true
	utilities.spare_power[component] -= data.power_use
	utilities.spare_water[component] -= data.water_use
	return top_left


## Проверяет многоклеточный участок (top_left, span) фасадом dir к улице; возвращает компонент или −1.
static func _fit_lot(grid: CityGrid, empty_set: Dictionary, residential: bool, land: LandValue,
		network: RoadNetwork, utilities: Utilities, sample_data: BuildingData,
		top_left: Vector2i, span: Vector2i, dir: int, entry_comp: int) -> int:
	# Крупное здание ставится фасадом прямо вдоль улицы (первая линия), чтобы арки и витрины выходили на дорогу.
	var step: Vector2i = CityGrid.NEIGHBORS[dir]
	var front: Array[Vector2i] = BuildingInstance.edge_cells(top_left, span, dir)
	var road_hits: int = 0
	var first_road := CityGrid.NO_CELL
	for fc: Vector2i in front:
		var road_cell: Vector2i = fc + step
		if grid.is_access_road(road_cell):
			road_hits += 1
			if first_road == CityGrid.NO_CELL:
				first_road = road_cell
	if road_hits * 2 < front.size() or first_road == CityGrid.NO_CELL:
		return -1
	var component: int = network.component_of.get(first_road, -1)
	if component == -1 or (grid.has_entry() and component != entry_comp):
		return -1
	if not _component_fits(utilities, component, sample_data):
		return -1
	for dy: int in span.y:
		for dx: int in span.x:
			var c := Vector2i(top_left.x + dx, top_left.y + dy)
			if not empty_set.has(c):
				return -1
			if residential and land != null and land.value_at(land.pollution, grid, c) >= MAX_HOME_POLLUTION:
				return -1
	return component


static func _best_1x1_dir(grid: CityGrid, cell: Vector2i) -> int:
	for dir: int in 4:
		if grid.is_access_road(cell + CityGrid.NEIGHBORS[dir]):
			return dir
	return grid.find_nearest_road_dir(cell)


static func _pick_bucket(buckets: Array[Array], rng: RandomNumberGenerator) -> Array:
	var total_weight: float = 0.0
	for i: int in buckets.size():
		if not buckets[i].is_empty():
			total_weight += BUCKET_WEIGHTS[i]
	if total_weight <= 0.0:
		return []
	var roll: float = rng.randf() * total_weight
	var acc: float = 0.0
	for i: int in buckets.size():
		if buckets[i].is_empty():
			continue
		acc += BUCKET_WEIGHTS[i]
		if roll <= acc:
			return buckets[i]
	for i: int in range(buckets.size() - 1, -1, -1):
		if not buckets[i].is_empty():
			return buckets[i]
	return []


static func _component_fits(utilities: Utilities, component: int, data: BuildingData) -> bool:
	return utilities.spare_power.get(component, 0) >= data.power_use \
			and utilities.spare_water.get(component, 0) >= data.water_use


static func _has_any_capacity(utilities: Utilities, need_power: int, need_water: int) -> bool:
	for component: int in utilities.spare_power:
		if utilities.spare_power[component] >= need_power \
				and utilities.spare_water.get(component, 0) >= need_water:
			return true
	return false
