class_name Hints
extends RefCounted
## Подсказки игроку — что мешает городу расти. Только читают GameState.

const MAX_HINTS: int = 5

## С этого населения советуем первый парк.
const PARK_HINT_FROM: int = 100

const SERVICE_NAMES: Dictionary[BuildingData.Service, String] = {
	BuildingData.Service.SCHOOL: "школа",
	BuildingData.Service.HEALTH: "поликлиника",
	BuildingData.Service.FIRE: "пожарная часть",
	BuildingData.Service.POLICE: "полиция",
}
## Ниже этого покрытия служба считается нехватающей.
const LOW_COVERAGE: float = 0.5
## С этой доли тяжёлых поездок подсказываем, что жителям далеко до работы.
const LONG_COMMUTE_HINT: float = 0.25
## С этого загрязнения жилой участок считается «у завода» (как запрет роста жилья).
const DIRTY_HOME: int = Growth.MAX_HOME_POLLUTION


static func build() -> Array[String]:
	var hints: Array[String] = []
	var utilities: Utilities = GameState.utilities
	var grid: CityGrid = GameState.grid

	var zoned: int = 0
	for cells: Dictionary in grid.zoned_empty_cells.values():
		zoned += cells.size()
	# Пустой город: ведём по первым шагам. Станции — раньше зон, чтобы не потратить деньги на зоны.
	if GameState.population == 0:
		var step: String = _first_step(grid, utilities, zoned)
		if not step.is_empty():
			hints.append(step)
			return hints
	var cut_off: int = 0
	for cells: Dictionary in grid.zoned_empty_cells.values():
		for cell: Vector2i in cells:
			if grid.in_strip(cell) and not GameState.network.reaches_highway(grid, cell):
				cut_off += 1
	if cut_off > 0:
		hints.append("%d кл. зон не связаны с трассой — дома там не строятся" % cut_off)
	if zoned > 0 and utilities.power_supply == 0 and utilities.water_supply == 0:
		hints.append("Нет ТЭЦ или водокачки: без света и воды дома не повышаются и пустеют — поставьте их у дороги")
	elif zoned > 0 and utilities.power_supply == 0:
		hints.append("Нет ТЭЦ или ветряка: без света дома не повышаются и пустеют — поставьте у дороги")
	elif zoned > 0 and utilities.water_supply == 0:
		hints.append("Нет водокачки: без воды дома не повышаются и пустеют — поставьте её у дороги")
	if utilities.unpowered_count > 0:
		hints.append("Нет света у %d зд.: нужна ТЭЦ, ветряк или дорога к ним" % utilities.unpowered_count)
	if utilities.no_water_count > 0:
		hints.append("Нет воды у %d зд.: нужна водокачка (ей нужен свет)" % utilities.no_water_count)
	# Упадок (Decay): здания без дороги скоро опустеют, брошенные ждут бульдозера или починки.
	var cut_road: int = 0
	var abandoned: int = 0
	for building: BuildingInstance in grid.buildings.values():
		if building.abandoned:
			abandoned += 1
		elif building.no_road_ticks > 0:
			cut_road += 1
	if cut_road > 0:
		hints.append("Без дороги %d зд.: верните дорогу, иначе через пару часов опустеют" % cut_road)
	if abandoned > 0:
		hints.append("Заброшено %d зд.: снесите бульдозером [B] или исправьте причину (клик по дому)" % abandoned)

	for service: BuildingData.Service in Services.REQUIRED_FROM:
		if GameState.population < Services.REQUIRED_FROM[service]:
			continue
		var coverage: float = GameState.service_coverage.get(service, 0.0)
		if coverage < LOW_COVERAGE:
			hints.append("Нужна %s: покрытие %d%%" % [SERVICE_NAMES[service], roundi(coverage * 100.0)])

	var traffic: Traffic = GameState.traffic
	if traffic.jammed_cells > 0:
		var advice: String = "постройте объезд"
		if RoadTypes.is_unlocked(RoadTypes.Type.AVENUE, GameState.rank):
			advice = "проложите проспект [T] поверх улицы или объезд"
		hints.append("Пробки на %d кл. дорог: %s" % [traffic.jammed_cells, advice])
	if traffic.total_workers > 0.0 and traffic.long_commute_share >= LONG_COMMUTE_HINT:
		hints.append("Жителям далеко до работы: %d%%" % roundi(traffic.long_commute_share * 100.0))

	# Фаза 9: грязь у жилья и подсказка про парки.
	var land: LandValue = GameState.land
	var dirty_homes: int = 0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.population > 0 and not building.abandoned \
				and land.building_value(land.pollution, grid, building) >= DIRTY_HOME:
			dirty_homes += 1
	var dirty_zone: int = 0
	for cell: Vector2i in grid.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL]:
		if land.value_at(land.pollution, grid, cell) >= DIRTY_HOME:
			dirty_zone += 1
	if dirty_homes > 0:
		hints.append("Дома рядом с заводами: %d — жильё лучше подальше от промзоны" % dirty_homes)
	elif dirty_zone > 0:
		hints.append("Жильё не растёт у заводов: %d кл. жилой зоны в загрязнении" % dirty_zone)
	# Застройщик (Р3) не ставит жильё, где «счастье места» ниже Growth.MIN_HOME_MOOD (шум, дешёвая земля).
	var poor_spots: int = _poor_home_spots(grid, land)
	if poor_spots > 0 and GameState.demand_by_zone()[CityGrid.Zone.RESIDENTIAL] > 0.0:
		hints.append("Жильё не строят на шумных местах: %d кл. у улицы — тише улица, парк или служба рядом (клик: почему)" % poor_spots)
	var unhappy: int = 0
	for mood: int in GameState.happiness.by_building.values():
		if mood < Levels.DECLINE_HAPPINESS:
			unhappy += 1
	if unhappy > 0:
		hints.append("Жителям плохо в %d домах — скоро уедут (клик по дому: почему)" % unhappy)
	if GameState.population >= PARK_HINT_FROM and not _has_parks(grid):
		hints.append("Парк поднимет цену земли и налоги вокруг (вкладка «Парки»)")

	var balance: int = GameState.income - GameState.expenses
	if GameState.money < 0:
		hints.append("Казна в минусе: поднимите налог или снесите лишнее")
	elif balance < 0:
		hints.append("Расходы больше доходов: %+d $/ч" % GameTime.per_hour(balance))

	if hints.size() > MAX_HINTS:
		hints.resize(MAX_HINTS)
	return hints


static func _has_parks(grid: CityGrid) -> bool:
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.park != BuildingData.Park.NONE:
			return true
	return false


static func _first_step(grid: CityGrid, utilities: Utilities, zoned: int) -> String:
	if grid.has_entry() and grid.road_cells.size() <= grid.highway_cells.size():
		return "Шаг 1: проведите дорогу [R] от трассы у края карты — по ней в город приедут жители"
	if grid.road_cells.is_empty():
		return "Шаг 1: проведите дорогу [R]"
	if utilities.power_supply == 0 and utilities.water_supply == 0:
		return "Шаг 2: поставьте у дороги ТЭЦ (или ветряк) и водокачку (кнопки внизу)"
	if utilities.power_supply == 0:
		return "Шаг 2: поставьте у дороги ТЭЦ или ветряк — свет нужен и водокачке"
	if utilities.water_supply == 0:
		return "Шаг 2: поставьте у дороги водокачку (вкладка «Свет и вода»)"
	if zoned == 0:
		return "Шаг 3: разметьте у дороги жилую [1] и промышленную [3] зоны"
	return ""


## Сколько свободных клеток жилья у самой улицы застройщик обходит: чисто, но «место» ниже MIN_HOME_MOOD.
static func _poor_home_spots(grid: CityGrid, land: LandValue) -> int:
	var context: Dictionary = {}
	var count: int = 0
	for zone_type: CityGrid.Zone in [CityGrid.Zone.RESIDENTIAL, CityGrid.Zone.RESIDENTIAL_HIGH]:
		for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
			if grid.get_strip_depth(cell) != 1 or land.value_at(land.pollution, grid, cell) >= DIRTY_HOME:
				continue
			if context.is_empty():
				context = Growth.place_context(grid, GameState.traffic)
			var cells: Array[Vector2i] = [cell]
			if Happiness.score_of(Growth.home_factors(grid, cells, land, context)) < Growth.MIN_HOME_MOOD:
				count += 1
	return count
