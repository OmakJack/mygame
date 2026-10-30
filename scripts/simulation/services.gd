class_name Services
extends RefCounted
## Покрытие служб: доля жителей, чьи дома в радиусе работающего здания службы.
## Службы нужны по ступеням населения и поправляют жилой спрос.

## С какого населения служба нужна городу.
const REQUIRED_FROM: Dictionary[BuildingData.Service, int] = {
	BuildingData.Service.SCHOOL: 150,
	BuildingData.Service.HEALTH: 250,
	BuildingData.Service.FIRE: 350,
	BuildingData.Service.POLICE: 500,
}
## Поправка спроса R за каждую нужную службу: (покрытие − 0.5) · WEIGHT.
const WEIGHT: float = 0.25
const NEUTRAL_COVERAGE: float = 0.5


## Покрытие каждой службы в [0, 1]. Служба работает, если у здания есть дорога, свет и вода.
static func coverage(grid: CityGrid, population: int) -> Dictionary[BuildingData.Service, float]:
	# Работающие здания служб: служба → [клетка, радиус].
	var active: Dictionary[BuildingData.Service, Array] = {}
	var homes: Array[BuildingInstance] = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		if data.population > 0:
			homes.append(building)
		if is_active(grid, building, data):
			if not active.has(data.service):
				active[data.service] = []
			for c: Vector2i in building.cells():
				active[data.service].append([c, data.service_radius])

	var result: Dictionary[BuildingData.Service, float] = {}
	for service: BuildingData.Service in REQUIRED_FROM:
		var covered: int = 0
		for home: BuildingInstance in homes:
			if _is_building_covered(home, active.get(service, [])):
				covered += BuildingCatalog.get_type(home.type_id).population
		result[service] = float(covered) / population if population > 0 else 0.0
	return result


## Здание службы работает: есть дорога, свет и вода.
static func is_active(grid: CityGrid, building: BuildingInstance, data: BuildingData) -> bool:
	return data.service != BuildingData.Service.NONE and building.powered and building.has_water \
			and grid.has_building_road_access(building)


## Поправка жилого спроса от служб, которые уже нужны при таком населении.
static func demand_offset(coverage_by_service: Dictionary[BuildingData.Service, float], population: int) -> float:
	var offset: float = 0.0
	for service: BuildingData.Service in REQUIRED_FROM:
		if population >= REQUIRED_FROM[service]:
			offset += (coverage_by_service.get(service, 0.0) - NEUTRAL_COVERAGE) * WEIGHT
	return offset


static func _is_building_covered(building: BuildingInstance, sources: Array) -> bool:
	var max_x: int = building.cell.x + building.size.x - 1
	var max_y: int = building.cell.y + building.size.y - 1
	for source: Array in sources:
		var sc: Vector2i = source[0]
		var radius: int = source[1]
		var nx: int = clampi(sc.x, building.cell.x, max_x)
		var ny: int = clampi(sc.y, building.cell.y, max_y)
		if absi(sc.x - nx) + absi(sc.y - ny) <= radius:
			return true
	return false
