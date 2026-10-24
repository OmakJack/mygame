class_name Growth
extends RefCounted
## Рост зданий: выбирает пустую клетку с зоной и доступом к дороге и ставит на неё дом.


## Ставит одно здание на зону zone_type. Возвращает клетку или −1/−1, если места нет.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator) -> Vector2i:
	var types: Array[BuildingData] = BuildingCatalog.types_for_zone(zone_type)
	if types.is_empty():
		return Vector2i(-1, -1)
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
		if grid.has_road_access(cell):
			candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var cell: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	var data: BuildingData = types[rng.randi_range(0, types.size() - 1)]
	# Фасад — к ближайшей дороге.
	grid.place_building(data.id, cell, grid.find_nearest_road_dir(cell))
	return cell
