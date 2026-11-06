extends Node
## Порядок одного тика симуляции: упадок и возвращение жильцов (Decay) → рост → повышения и укрупнение → пересчёт (сеть, свет и вода, подсчёт,
## трафик, службы, спрос, прогноз денег) → деньги → сигналы.
## Вне тика (стройка и снос на паузе, налог, новая сетка) тоже пересчитывает всё для UI.
## Узлы сцены не ищет: работает с GameState и Events.

## Во сколько раз шанс роста больше спроса.
const GROWTH_CHANCE_FACTOR: float = 0.7
## Р5, темп от размера города: у каждой зоны 1 попытка роста на тик + ещё одна на каждые GROWTH_POP_PER_TRY
## жителей, всего не больше MAX_GROWTH_TRIES — большой город застраивает новый район быстрее.
const GROWTH_POP_PER_TRY: int = 250
const MAX_GROWTH_TRIES: int = 5
## На тике трафик пересчитывается раз в столько тиков (и сразу — при изменении дорог).
const TRAFFIC_PERIOD: int = 5
## На тике слои земли (цена, дым, шум) — не чаще раза в столько тиков и не в тик трафика:
## оба счёта по ~20 мс, вместе на каждом тике город за 250 домов терял кадры (Р5).
const LAND_PERIOD: int = 5

## Идёт тик: свой же cells_changed не пересчитываем второй раз.
var _in_tick: bool = false
# По чему был посчитан текущий трафик — чтобы не пересчитывать его на каждый клик.
var _traffic_grid: CityGrid = null
var _traffic_roads_version: int = -1
var _traffic_buildings_version: int = -1
var _ticks_since_traffic: int = 0
# По чему были посчитаны слои земли.
var _land_traffic: Traffic = null
var _land_grid: CityGrid = null
var _land_buildings_version: int = -1
var _ticks_since_land: int = 0


func _ready() -> void:
	Events.sim_tick.connect(_on_sim_tick)
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_refresh_stats)
	Events.tax_rate_requested.connect(_on_tax_rate_requested)
	# Спрос пустого города — чтобы первые дома выросли уже на первом тике.
	_refresh_stats()


func _on_sim_tick() -> void:
	var grid: CityGrid = GameState.grid
	var changed: Array[Vector2i] = []
	changed.append_array(Decay.step(grid, GameState.network, GameState.land, GameState.traffic, GameState.tax_rate,
			_demands()))
	# Фаза 10: упадок несчастных домов, конец стройки, рост, повышения и перестройки.
	changed.append_array(Levels.decline(grid, GameState.happiness))
	changed.append_array(Levels.tick_construction(grid))
	_grow(grid, changed)
	changed.append_array(Levels.step(grid, GameState.rng, GameState.network, GameState.utilities, GameState.land,
			GameState.happiness, _demands()))
	# Р4: соседние дома на дорогой земле сливаются в один побольше.
	changed.append_array(Consolidation.step(grid, GameState.rng, GameState.network, GameState.utilities,
			GameState.land, _demands()))
	_ticks_since_traffic += 1
	_ticks_since_land += 1
	_update_stats(true)
	Economy.apply_tick()
	if not changed.is_empty():
		_in_tick = true
		Events.cells_changed.emit(changed)
		_in_tick = false
	Events.stats_changed.emit()


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	if not _in_tick:
		_refresh_stats()


func _on_tax_rate_requested(rate: int) -> void:
	var clamped: int = clampi(rate, Economy.MIN_TAX_RATE, Economy.MAX_TAX_RATE)
	if clamped == GameState.tax_rate:
		return
	GameState.tax_rate = clamped
	_refresh_stats()


func _refresh_stats() -> void:
	_update_stats()
	Events.stats_changed.emit()


## Шанс вырасти дому зоны на попытке = min(1, спрос · GROWTH_CHANCE_FACTOR):
## при спросе 0.5 — примерно раз в 3 попытки, при просадке (налог, нет служб) — реже.
## Попыток — growth_tries (от населения). Тик не перерастает спрос: у категории запас — спрос × шкала
## (сколько жителей или мест не хватает, Demand.scale_of); стройки тика вычитают из него, на нуле — хватит.
## Первая попытка — всегда (малый город растёт, как раньше, и тот же ход случайности).
func _grow(grid: CityGrid, changed: Array[Vector2i]) -> void:
	var demands: Dictionary[CityGrid.Zone, float] = _demands()
	var tries: int = growth_tries(GameState.population)
	var room: Dictionary[CityGrid.Zone, float] = {}
	for category: CityGrid.Zone in demands:
		room[category] = demands[category] * Demand.scale_of(category, GameState.population)
	# Слои и жители для «желанности места» — один раз на тик, общие для всех попыток.
	var context: Dictionary = {}
	# Каждая зона (и высокой плотности, и офисы) растёт по спросу своей категории (фаза 10).
	for zone_type: CityGrid.Zone in grid.zoned_empty_cells:
		var category: CityGrid.Zone = CityGrid.zone_category(zone_type)
		var demand: float = demands[category]
		var chance: float = clampf(demand * GROWTH_CHANCE_FACTOR, 0.0, 1.0)
		for attempt: int in tries:
			if grid.zoned_empty_cells[zone_type].is_empty() or (attempt > 0 and room[category] <= 0.0):
				break
			if GameState.rng.randf() >= chance:
				continue
			var cell: Vector2i = Growth.grow_one(grid, zone_type, GameState.rng, GameState.network,
					GameState.utilities, GameState.land, demand, GameState.traffic, context)
			if cell == CityGrid.NO_CELL:
				break
			var building: BuildingInstance = grid.get_building_at(cell)
			var data: BuildingData = BuildingCatalog.get_type(building.type_id)
			Levels.start_construction(building, data)
			changed.append_array(building.cells())
			room[category] -= data.population + data.jobs


## Попыток роста у зоны за тик: 1 + по одной на каждые GROWTH_POP_PER_TRY жителей, не больше MAX_GROWTH_TRIES.
static func growth_tries(population: int) -> int:
	return clampi(1 + population / GROWTH_POP_PER_TRY, 1, MAX_GROWTH_TRIES)


## Спрос по категориям зон.
func _demands() -> Dictionary[CityGrid.Zone, float]:
	return GameState.demand_by_zone()


## Пересчитывает всё, что видит UI: сеть, свет и воду, население и рабочие места,
## трафик (когда пора), покрытие служб, спрос и прогноз денег на тик.
func _update_stats(from_tick: bool = false) -> void:
	var grid: CityGrid = GameState.grid
	GameState.network.update(grid)
	GameState.utilities = Utilities.distribute(grid, GameState.network)

	var population: int = 0
	var jobs_commercial: int = 0
	var jobs_industrial: int = 0
	var service_upkeep: int = 0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or building.abandoned:
			continue
		population += data.population
		match CityGrid.zone_category(data.zone):
			CityGrid.Zone.COMMERCIAL:
				jobs_commercial += data.jobs
			CityGrid.Zone.INDUSTRIAL:
				jobs_industrial += data.jobs
			CityGrid.Zone.NONE:
				service_upkeep += data.upkeep
	GameState.population = population
	GameState.jobs_commercial = jobs_commercial
	GameState.jobs_industrial = jobs_industrial

	var traffic_now: bool = _traffic_due(grid, from_tick)
	if traffic_now:
		GameState.traffic = Traffic.compute(grid)
		_traffic_grid = grid
		_traffic_roads_version = grid.roads_version
		_traffic_buildings_version = grid.buildings_version
		_ticks_since_traffic = 0

	if _land_due(grid, from_tick, traffic_now):
		GameState.land = LandValue.compute(grid, GameState.traffic)
		_land_grid = grid
		_land_traffic = GameState.traffic
		_land_buildings_version = grid.buildings_version
		_ticks_since_land = 0

	GameState.happiness = Happiness.compute(grid, GameState.land, GameState.traffic, GameState.tax_rate)
	_update_rank(population)

	GameState.service_coverage = Services.coverage(grid, population)
	var offset: float = Services.demand_offset(GameState.service_coverage, population) \
			+ GameState.traffic.demand_offset()
	var tax_rate: int = GameState.tax_rate
	GameState.demand_r = Demand.residential(population, jobs_commercial, jobs_industrial, tax_rate, offset)
	GameState.demand_c = Demand.commercial(population, jobs_commercial, tax_rate)
	GameState.demand_i = Demand.industrial(population, jobs_industrial, tax_rate)
	# Прогноз денег на тик — тоже здесь, чтобы UI видел его сразу (и на паузе).
	GameState.income = Economy.daily_income(_tax_base(grid), tax_rate)
	var road_upkeep: float = 0.0
	for road: Vector2i in grid.road_cells:
		road_upkeep += RoadTypes.UPKEEP.get(grid.road_type[grid.index_of(road)], Economy.ROAD_UPKEEP)
	GameState.expenses = Economy.daily_expenses(road_upkeep, service_upkeep)


## Звание растёт с населением и не падает. Старое сохранение (−1) — по населению, без награды.
func _update_rank(population: int) -> void:
	var reached: int = Ranks.for_population(population)
	if GameState.rank < 0:
		GameState.rank = reached
	elif reached > GameState.rank:
		for rank: int in range(GameState.rank + 1, reached + 1):
			GameState.money += Ranks.REWARDS[rank]
		GameState.rank = reached
		Events.rank_changed.emit(reached)


## Налоговая база: жители и рабочие места, каждое здание — с поправкой на стоимость земли под ним.
func _tax_base(grid: CityGrid) -> float:
	var base: float = 0.0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or data.population + data.jobs == 0 or building.abandoned:
			continue
		var value: int = GameState.land.building_value(GameState.land.land_value, grid, building)
		base += (data.population + data.jobs) * Economy.land_factor(value)
	return base


## Слои земли — по зданиям, воде и трафику. Вне тика (стройка на паузе) и для новой сетки — сразу, при любой смене.
## На тике — раз в LAND_PERIOD и не вместе с трафиком (тогда на следующем тике).
func _land_due(grid: CityGrid, from_tick: bool, traffic_now: bool) -> bool:
	if GameState.land.size != grid.size or grid != _land_grid:
		return true
	if GameState.traffic == _land_traffic and grid.buildings_version == _land_buildings_version:
		return false
	if not from_tick:
		return true
	return _ticks_since_land >= LAND_PERIOD and not traffic_now


## Дороги или сетка изменились — сразу (иначе ездили бы по снесённой улице).
## Здания: вне тика (стройка на паузе) — сразу; на тике — раз в TRAFFIC_PERIOD.
## Налог и покраска зон трафик не трогают.
func _traffic_due(grid: CityGrid, from_tick: bool) -> bool:
	if grid != _traffic_grid or grid.roads_version != _traffic_roads_version:
		return true
	if from_tick:
		return _ticks_since_traffic >= TRAFFIC_PERIOD
	return grid.buildings_version != _traffic_buildings_version
