class_name Levels
extends RefCounted
## Уровни зданий (фаза 10): повышение, перестройка под новую плотность зоны и упадок домов.
## Повышение и перестройка — замена type_id того же размера участка и 2 тика стройплощадки.

## Цена земли и счастье для уровня 2 и 3 (индекс — уровень).
const LAND_FOR_LEVEL: Array[int] = [0, 0, 30, 50]
const HAPPINESS_FOR_LEVEL: Array[int] = [0, 0, 45, 60]
## Сколько зданий за тик может повыситься или перестроиться, и с каким шансом на каждую попытку.
const CHANGES_PER_TICK: int = 2
const CHANGE_CHANCE: float = 0.5
## Упадок: дом пустеет, если счастье ниже этого дольше DECLINE_TICKS тиков. Дом без света или воды
## от несчастья не пустеет — его срок Decay.NO_UTILITY_TICKS (иначе дома, выросшие до
## первой ТЭЦ, исчезали бы через 20 минут).
const DECLINE_HAPPINESS: int = 20
const DECLINE_TICKS: int = 20
## Сколько тиков здание стоит стройплощадкой: чем больше здание, тем дольше (как в Cities: Skylines) —
## CONSTRUCTION_BASE_TICKS + CONSTRUCTION_TICKS_PER_ROOT · √(жители + места). Домик 1×1 — 8 игровых
## минут, дом 5×1 — 13, многоэтажка 1×1 ур.3 — 21, многоэтажка 7×1 ур.3 — 52.
const CONSTRUCTION_BASE_TICKS: int = 3
const CONSTRUCTION_TICKS_PER_ROOT: float = 2.6


static func construction_ticks_for(data: BuildingData) -> int:
	return CONSTRUCTION_BASE_TICKS + roundi(CONSTRUCTION_TICKS_PER_ROOT * sqrt(float(maxi(0, data.population + data.jobs))))


## Здание становится стройплощадкой на срок по своему размеру.
static func start_construction(building: BuildingInstance, data: BuildingData) -> void:
	building.construction_ticks = construction_ticks_for(data)
	building.construction_total = building.construction_ticks


## Что мешает зданию подняться на следующий уровень; пусто — может (если есть спрос).
static func blockers(grid: CityGrid, building: BuildingInstance, data: BuildingData, land: LandValue,
		happiness: Happiness) -> PackedStringArray:
	var result: PackedStringArray = []
	if data.level >= 3:
		return result
	if not building.powered:
		result.append("нет света")
	if not building.has_water:
		result.append("нет воды")
	var next: int = data.level + 1
	var value: int = land.building_value(land.land_value, grid, building)
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
		if data == null or data.zone == CityGrid.Zone.NONE or building.construction_ticks > 0 or building.abandoned:
			continue
		if demands.get(CityGrid.zone_category(data.zone), 0.0) <= 0.0:
			continue
		var action: Variant = _plan_change(grid, building, data, land, happiness, rng)
		if action != null:
			candidates.append([building, data, action])
	for attempt: int in CHANGES_PER_TICK:
		if candidates.is_empty() or rng.randf() >= CHANGE_CHANCE:
			continue
		var pick: Array = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var building: BuildingInstance = pick[0]
		if not grid.buildings.has(building.id):
			continue
		var occupied: Array[Vector2i] = building.cells()
		if pick[2] is StringName and pick[2] == &"redevelop":
			# Участок разделили разными зонами или под новую плотность нет такого размера — освобождаем клетки под новый рост.
			grid.remove_building(building.id)
			changed.append_array(occupied)
		elif pick[2] is BuildingData and _apply(grid, building, pick[1], pick[2], network, utilities):
			changed.append_array(occupied)
	return changed


## Упадок: считает несчастные тики; дом, где жителям плохо дольше DECLINE_TICKS, пустеет (Decay.abandon) —
## стоит брошенным, пока его не снесут или не станет лучше. Стройплощадки не пустеют. Возвращает клетки.
static func decline(grid: CityGrid, happiness: Happiness) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for building: BuildingInstance in grid.buildings.values():
		if not happiness.by_building.has(building.id) or building.abandoned or building.construction_ticks > 0:
			continue
		if not building.powered or not building.has_water:
			building.unhappy_ticks = 0
			continue
		if happiness.by_building[building.id] < DECLINE_HAPPINESS:
			building.unhappy_ticks += 1
			if building.unhappy_ticks >= DECLINE_TICKS:
				Decay.abandon(grid, building)
				cells.append_array(building.cells())
		else:
			building.unhappy_ticks = 0
	return cells


## Стройплощадки: минус тик; возвращает клетки, где стройка закончилась (показать дом).
static func tick_construction(grid: CityGrid) -> Array[Vector2i]:
	var done: Array[Vector2i] = []
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			building.construction_ticks -= 1
			if building.construction_ticks == 0:
				done.append_array(building.cells())
	return done


## План изменения здания: BuildingData (новый тип того же размера), &"redevelop" (разбор под новый рост) или null.
static func _plan_change(grid: CityGrid, building: BuildingInstance, data: BuildingData, land: LandValue,
		happiness: Happiness, rng: RandomNumberGenerator) -> Variant:
	var occupied: Array[Vector2i] = building.cells()
	var first_zone: CityGrid.Zone = grid.get_zone(occupied[0])
	var same_across_lot: bool = true
	var any_rezoned: bool = false
	for c: Vector2i in occupied:
		var z: CityGrid.Zone = grid.get_zone(c)
		if z != first_zone:
			same_across_lot = false
		if z != data.zone and z != CityGrid.Zone.NONE:
			any_rezoned = true
	if any_rezoned:
		if not same_across_lot or first_zone == CityGrid.Zone.NONE:
			return &"redevelop"
		var rezoned_options: Array[BuildingData] = BuildingCatalog.level_types(first_zone, 1, data.size)
		if rezoned_options.is_empty():
			return &"redevelop"
		return BuildingCatalog.pick_weighted(rezoned_options, rng)
	if data.level < 3 and blockers(grid, building, data, land, happiness).is_empty():
		var options: Array[BuildingData] = BuildingCatalog.level_types(data.zone, data.level + 1, data.size)
		if not options.is_empty():
			return BuildingCatalog.pick_weighted(options, rng)
	return null


## Замена типа, если в компоненте дорог хватает запаса света и воды на прибавку.
static func _apply(grid: CityGrid, building: BuildingInstance, data: BuildingData, target: BuildingData,
		network: RoadNetwork, utilities: Utilities) -> bool:
	var component: int = network.component_for_building(grid, building)
	if component == -1:
		return false
	var more_power: int = target.power_use - data.power_use
	var more_water: int = target.water_use - data.water_use
	if utilities.spare_power.get(component, 0) < more_power or utilities.spare_water.get(component, 0) < more_water:
		return false
	building.type_id = target.id
	start_construction(building, target)
	building.unhappy_ticks = 0
	grid.buildings_version += 1
	utilities.spare_power[component] -= maxi(0, more_power)
	utilities.spare_water[component] -= maxi(0, more_water)
	return true
