class_name Hints
extends RefCounted
## Подсказки игроку — что мешает городу расти. Только читают GameState.

const MAX_HINTS: int = 5

const SERVICE_NAMES: Dictionary[BuildingData.Service, String] = {
	BuildingData.Service.SCHOOL: "школа",
	BuildingData.Service.HEALTH: "поликлиника",
	BuildingData.Service.FIRE: "пожарная часть",
	BuildingData.Service.POLICE: "полиция",
}
## Ниже этого покрытия служба считается нехватающей.
const LOW_COVERAGE: float = 0.5


static func build() -> Array[String]:
	var hints: Array[String] = []
	var utilities: Utilities = GameState.utilities
	var grid: CityGrid = GameState.grid

	var zoned: int = 0
	for cells: Dictionary in grid.zoned_empty_cells.values():
		zoned += cells.size()
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

	var balance: int = GameState.income - GameState.expenses
	if GameState.money < 0:
		hints.append("Казна в минусе: поднимите налог или снесите лишнее")
	elif balance < 0:
		hints.append("Расходы больше доходов: %+d $/день" % balance)

	if hints.size() > MAX_HINTS:
		hints.resize(MAX_HINTS)
	return hints
