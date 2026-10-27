class_name Levels
extends RefCounted
## Уровни зданий (фаза 10): повышение, перестройка под новую плотность зоны и упадок домов.
## Повышение и перестройка — замена type_id (формат сохранений не меняется) и 2 дня стройплощадки.

## Цена земли и счастье для уровня 2 и 3 (индекс — уровень).
const LAND_FOR_LEVEL: Array[int] = [0, 0, 30, 50]
const HAPPINESS_FOR_LEVEL: Array[int] = [0, 0, 45, 60]
## Сколько зданий за тик может повыситься или перестроиться, и с каким шансом на каждую попытку.
const CHANGES_PER_TICK: int = 2
const CHANGE_CHANCE: float = 0.5
## Упадок: дом пустеет, если счастье ниже этого дольше DECLINE_TICKS дней.
const DECLINE_HAPPINESS: int = 20
const DECLINE_TICKS: int = 20
## Сколько дней здание стоит стройплощадкой.
const CONSTRUCTION_TICKS: int = 2


## Что мешает зданию подняться на следующий уровень; пусто — может (если есть спрос и свет с водой).
static func blockers(grid: CityGrid, building: BuildingInstance, data: BuildingData, land: LandValue,
		happiness: Happiness) -> PackedStringArray:
	var result: PackedStringArray = []
	if data.level >= 3:
		return result
	var next: int = data.level + 1
	var value: int = land.value_at(land.land_value, grid, building.cell)
	if value < LAND_FOR_LEVEL[next]:
		result.append("цена земли %d из %d" % [value, LAND_FOR_LEVEL[next]])
	if data.population > 0:
		var mood: int = happiness.by_building.get(building.id, 0)
		if mood < HAPPINESS_FOR_LEVEL[next]:
			result.append("счастье %d из %d" % [mood, HAPPINESS_FOR_LEVEL[next]])
	return result


## Повышения и перестройки за тик. Возвращает изменённые клетки.
static func step(grid: CityGrid, rng: RandomNumberGenerator, network: RoadNetwork, utilities: Utilities,
		land: LandValue, happiness: Happiness, demands: Dictionary[CityGrid.Zone, float]) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var candidates: Array[Array] = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or data.zone == CityGrid.Zone.NONE or building.construction_ticks > 0:
			continue
		if demands.get(CityGrid.zone_category(data.zone), 0.0) <= 0.0:
			continue
		var target: BuildingData = _target(grid, building, data, land, happiness, rng)
		if target != null:
			candidates.append([building, data, target])
	for attempt: int in CHANGES_PER_TICK:
		if candidates.is_empty() or rng.randf() >= CHANGE_CHANCE:
			continue
		var pick: Array = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var building: BuildingInstance = pick[0]
		if _apply(grid, building, pick[1], pick[2], network, utilities):
			changed.append(building.cell)
	return changed


## Упадок: считает несчастные дни, пустые дома сносит (зона остаётся). Возвращает клетки снесённых.
static func decline(grid: CityGrid, happiness: Happiness) -> Array[Vector2i]:
	var gone: Array[int] = []
	for building: BuildingInstance in grid.buildings.values():
		if not happiness.by_building.has(building.id):
			continue
		if happiness.by_building[building.id] < DECLINE_HAPPINESS:
			building.unhappy_ticks += 1
			if building.unhappy_ticks >= DECLINE_TICKS:
				gone.append(building.id)
		else:
			building.unhappy_ticks = 0
	var cells: Array[Vector2i] = []
	for id: int in gone:
		cells.append(grid.buildings[id].cell)
		grid.remove_building(id)
	return cells


## Стройплощадки: минус день; возвращает клетки, где стройка закончилась (показать дом).
static func tick_construction(grid: CityGrid) -> Array[Vector2i]:
	var done: Array[Vector2i] = []
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			building.construction_ticks -= 1
			if building.construction_ticks == 0:
				done.append(building.cell)
	return done


## Во что превратить здание: тип зоны клетки ур.1, если плотность сменили; иначе следующий уровень.
static func _target(grid: CityGrid, building: BuildingInstance, data: BuildingData, land: LandValue,
		happiness: Happiness, rng: RandomNumberGenerator) -> BuildingData:
	var cell_zone: CityGrid.Zone = grid.get_zone(building.cell)
	var options: Array[BuildingData]
	if cell_zone != data.zone and cell_zone != CityGrid.Zone.NONE:
		options = BuildingCatalog.level_types(cell_zone, 1)
	elif data.level < 3 and blockers(grid, building, data, land, happiness).is_empty():
		options = BuildingCatalog.level_types(data.zone, data.level + 1)
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]


## Замена типа, если в компоненте дорог хватает запаса света и воды на прибавку.
static func _apply(grid: CityGrid, building: BuildingInstance, data: BuildingData, target: BuildingData,
		network: RoadNetwork, utilities: Utilities) -> bool:
	var component: int = network.component_for(grid, building.cell)
	if component == -1:
		return false
	var more_power: int = target.power_use - data.power_use
	var more_water: int = target.water_use - data.water_use
	if utilities.spare_power.get(component, 0) < more_power or utilities.spare_water.get(component, 0) < more_water:
		return false
	building.type_id = target.id
	building.construction_ticks = CONSTRUCTION_TICKS
	building.unhappy_ticks = 0
	grid.buildings_version += 1
	utilities.spare_power[component] -= maxi(0, more_power)
	utilities.spare_water[component] -= maxi(0, more_water)
	return true
