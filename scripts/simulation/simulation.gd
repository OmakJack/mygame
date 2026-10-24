extends Node
## Порядок одного тика симуляции: заброшенные здания → рост → подсчёт → спрос → деньги → сигналы.
## Вне тика (снос на паузе, налог, новая сетка) тоже пересчитывает статистику для UI.
## Узлы сцены не ищет: работает с GameState и Events.

## Через сколько тиков без доступа к дороге здание сносится.
const ABANDON_TICKS: int = 3

var _rng := RandomNumberGenerator.new()
## Идёт тик: свой же cells_changed не пересчитываем второй раз.
var _in_tick: bool = false


func _ready() -> void:
	_rng.randomize()
	Events.sim_tick.connect(_on_sim_tick)
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_refresh_stats)
	Events.tax_rate_requested.connect(_on_tax_rate_requested)
	# Спрос пустого города — чтобы первые дома выросли уже на первом тике.
	_refresh_stats()


func _on_sim_tick() -> void:
	var grid: CityGrid = GameState.grid
	var changed: Array[Vector2i] = []
	_abandon_buildings(grid, changed)
	_grow(grid, changed)
	_update_stats()
	Economy.apply_day()
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


func _abandon_buildings(grid: CityGrid, changed: Array[Vector2i]) -> void:
	var abandoned: Array[int] = []
	for building: BuildingInstance in grid.buildings.values():
		if grid.has_road_access(building.cell):
			building.no_road_ticks = 0
			continue
		building.no_road_ticks += 1
		if building.no_road_ticks >= ABANDON_TICKS:
			abandoned.append(building.id)
	# Удаляем после обхода, чтобы не менять словарь во время итерации.
	for id: int in abandoned:
		changed.append(grid.buildings[id].cell)
		grid.remove_building(id)


func _grow(grid: CityGrid, changed: Array[Vector2i]) -> void:
	var demands: Dictionary[CityGrid.Zone, float] = {
		CityGrid.Zone.RESIDENTIAL: GameState.demand_r,
		CityGrid.Zone.COMMERCIAL: GameState.demand_c,
		CityGrid.Zone.INDUSTRIAL: GameState.demand_i,
	}
	for zone_type: CityGrid.Zone in demands:
		if demands[zone_type] <= 0.0:
			continue
		var cell: Vector2i = Growth.grow_one(grid, zone_type, _rng)
		if cell.x >= 0:
			changed.append(cell)


## Пересчитывает население и рабочие места по всем зданиям, затем спрос.
func _update_stats() -> void:
	var population: int = 0
	var jobs_commercial: int = 0
	var jobs_industrial: int = 0
	for building: BuildingInstance in GameState.grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		population += data.population
		match data.zone:
			CityGrid.Zone.COMMERCIAL:
				jobs_commercial += data.jobs
			CityGrid.Zone.INDUSTRIAL:
				jobs_industrial += data.jobs
	GameState.population = population
	GameState.jobs_commercial = jobs_commercial
	GameState.jobs_industrial = jobs_industrial
	var tax_rate: int = GameState.tax_rate
	GameState.demand_r = Demand.residential(population, jobs_commercial, jobs_industrial, tax_rate)
	GameState.demand_c = Demand.commercial(population, jobs_commercial, tax_rate)
	GameState.demand_i = Demand.industrial(population, jobs_industrial, tax_rate)
