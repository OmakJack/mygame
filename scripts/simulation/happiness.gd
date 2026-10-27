class_name Happiness
extends RefCounted
## Счастье жителей дома (фаза 10), 0..100. Не сохраняется — считается по городу.
## Из него: повышение уровня дома и упадок (Levels), плашка в HUD, причины в карточке «Инфо».

const BASE: float = 50.0
## За каждую работающую службу, покрывающую дом (школа, поликлиника, пожарные, полиция).
const PER_SERVICE: float = 8.0
const LAND_WEIGHT: float = 0.5
const POLLUTION_WEIGHT: float = 0.6
const NOISE_WEIGHT: float = 0.3
## Долгая дорога до работы (Traffic.home_badness 0..1).
const COMMUTE_WEIGHT: float = 25.0
## За каждый процент налога выше нейтрального.
const TAX_WEIGHT: float = 2.0
## Нет света или воды.
const NO_UTILITY: float = 30.0

## Дом → счастье. Только дома с жителями.
var by_building: Dictionary[int, int] = {}
## Среднее по жителям; −1 — жителей нет.
var average: int = -1


static func compute(grid: CityGrid, land: LandValue, traffic: Traffic, tax_rate: int) -> Happiness:
	var result := Happiness.new()
	var services: Array = _active_services(grid)
	var total: float = 0.0
	var people: int = 0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or data.population == 0:
			continue
		var value: int = _score(factors(grid, building, data, land, traffic, tax_rate, services))
		result.by_building[building.id] = value
		total += value * data.population
		people += data.population
	if people > 0:
		result.average = roundi(total / people)
	return result


## Слагаемые счастья дома: [подпись, прибавка]. Для карточки «Инфо» и для счёта.
static func factors(grid: CityGrid, building: BuildingInstance, data: BuildingData, land: LandValue,
		traffic: Traffic, tax_rate: int, services: Array = []) -> Array[Array]:
	if services.is_empty():
		services = _active_services(grid)
	var result: Array[Array] = []
	var covered: int = 0
	for source: Array in services:
		var cell: Vector2i = source[0]
		if absi(cell.x - building.cell.x) + absi(cell.y - building.cell.y) <= source[1]:
			covered += 1
	result.append(["Службы рядом", covered * PER_SERVICE])
	var value: int = land.value_at(land.land_value, grid, building.cell)
	result.append(["Цена земли", (value - LandValue.BASE_VALUE) * LAND_WEIGHT])
	result.append(["Загрязнение", -land.value_at(land.pollution, grid, building.cell) * POLLUTION_WEIGHT])
	result.append(["Шум", -land.value_at(land.noise, grid, building.cell) * NOISE_WEIGHT])
	result.append(["Дорога до работы", -traffic.home_badness.get(building.id, 0.0) * COMMUTE_WEIGHT])
	result.append(["Налог", -(tax_rate - Economy.DEFAULT_TAX_RATE) * TAX_WEIGHT])
	if not building.powered or not building.has_water:
		result.append(["Нет света или воды", -NO_UTILITY])
	return result


static func score_of(factor_list: Array[Array]) -> int:
	return _score(factor_list)


static func _score(factor_list: Array[Array]) -> int:
	var sum: float = BASE
	for factor: Array in factor_list:
		sum += factor[1]
	return roundi(clampf(sum, 0.0, 100.0))


## Работающие службы: [клетка, радиус].
static func _active_services(grid: CityGrid) -> Array:
	var result: Array = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and Services.is_active(grid, building, data):
			result.append([building.cell, data.service_radius])
	return result
