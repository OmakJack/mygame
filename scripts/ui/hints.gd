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
	if zoned > 0 and (utilities.power_supply == 0 or utilities.water_supply == 0):
		hints.append("Без света и воды город не растёт: поставьте у дороги ТЭЦ и водокачку")
	if utilities.unpowered_count > 0:
		hints.append("Нет света у %d зд.: нужна ТЭЦ или дорога к ней" % utilities.unpowered_count)
	if utilities.no_water_count > 0:
		hints.append("Нет воды у %d зд.: нужна водокачка (ей нужен свет)" % utilities.no_water_count)

	for service: BuildingData.Service in Services.REQUIRED_FROM:
		if GameState.population < Services.REQUIRED_FROM[service]:
			continue
		var coverage: float = GameState.service_coverage.get(service, 0.0)
		if coverage < LOW_COVERAGE:
			hints.append("Нужна %s: покрытие %d%%" % [SERVICE_NAMES[service], roundi(coverage * 100.0)])

	var traffic: Traffic = GameState.traffic
	if traffic.jammed_cells > 0:
		hints.append("Пробки на %d кл. дорог: постройте объезд" % traffic.jammed_cells)
	if traffic.total_workers > 0.0 and traffic.long_commute_share >= LONG_COMMUTE_HINT:
		hints.append("Жителям далеко до работы: %d%%" % roundi(traffic.long_commute_share * 100.0))

	# Фаза 9: грязь у жилья и подсказка про парки.
	var land: LandValue = GameState.land
	var dirty_homes: int = 0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.population > 0 and land.value_at(land.pollution, grid, building.cell) >= DIRTY_HOME:
			dirty_homes += 1
	var dirty_zone: int = 0
	for cell: Vector2i in grid.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL]:
		if land.value_at(land.pollution, grid, cell) >= DIRTY_HOME:
			dirty_zone += 1
	if dirty_homes > 0:
		hints.append("Дома рядом с заводами: %d — жильё лучше подальше от промзоны" % dirty_homes)
	elif dirty_zone > 0:
		hints.append("Жильё не растёт у заводов: %d кл. жилой зоны в загрязнении" % dirty_zone)
	if GameState.population >= PARK_HINT_FROM and not _has_parks(grid):
		hints.append("Парк поднимет цену земли и налоги вокруг (вкладка «Парки»)")

	var balance: int = GameState.income - GameState.expenses
	if GameState.money < 0:
		hints.append("Казна в минусе: поднимите налог или снесите лишнее")
	elif balance < 0:
		hints.append("Расходы больше доходов: %+d $/день" % balance)

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
	if grid.road_cells.is_empty():
		return "Шаг 1: проведите дорогу [R]"
	if utilities.power_supply == 0 or utilities.water_supply == 0:
		return "Шаг 2: поставьте у дороги ТЭЦ и водокачку (кнопки внизу)"
	if zoned == 0:
		return "Шаг 3: разметьте у дороги жилую [1] и промышленную [3] зоны"
	return ""
