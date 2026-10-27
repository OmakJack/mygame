class_name Growth
extends RefCounted
## Рост зданий: выбирает пустую клетку с зоной, у компонента дорог которой хватает
## свободного света и воды, и ставит на неё дом. Свободный запас сразу уменьшается.


## Ставит одно здание на зону zone_type. Возвращает клетку или −1/−1, если места нет.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator,
		network: RoadNetwork, utilities: Utilities) -> Vector2i:
	var types: Array[BuildingData] = BuildingCatalog.growable_types(zone_type)
	if types.is_empty():
		return CityGrid.NO_CELL
	var data: BuildingData = types[rng.randi_range(0, types.size() - 1)]
	# Нет запаса ни в одном компоненте — не перебираем клетки.
	if not _has_capacity(utilities, data):
		return CityGrid.NO_CELL
	var candidates: Array[Vector2i] = []
	var components: Array[int] = []
	for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
		var component: int = network.component_for(grid, cell)
		if component == -1:
			continue
		if utilities.spare_power.get(component, 0) >= data.power_use \
				and utilities.spare_water.get(component, 0) >= data.water_use:
			candidates.append(cell)
			components.append(component)
	if candidates.is_empty():
		return CityGrid.NO_CELL
	var pick: int = rng.randi_range(0, candidates.size() - 1)
	var cell: Vector2i = candidates[pick]
	var component: int = components[pick]
	# Фасад — к ближайшей дороге.
	var id: int = grid.place_building(data.id, cell, grid.find_nearest_road_dir(cell))
	# Новый дом сразу со светом и водой: запас под него мы только что проверили.
	var building: BuildingInstance = grid.buildings[id]
	building.powered = true
	building.has_water = true
	utilities.spare_power[component] -= data.power_use
	utilities.spare_water[component] -= data.water_use
	return cell


static func _has_capacity(utilities: Utilities, data: BuildingData) -> bool:
	for component: int in utilities.spare_power:
		var enough_water: bool = utilities.spare_water.get(component, 0) >= data.water_use
		if utilities.spare_power[component] >= data.power_use and enough_water:
			return true
	return false
