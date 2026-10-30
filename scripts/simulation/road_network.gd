class_name RoadNetwork
extends RefCounted
## Связные компоненты дорог (соседство по 4 сторонам). По дорогам идут свет и вода.
## Пересчитывается лениво — только если изменилась CityGrid.roads_version или сама сетка.

## Клетка дороги → номер компонента.
var component_of: Dictionary[Vector2i, int] = {}
var component_count: int = 0

var _grid: CityGrid = null
var _version: int = -1


## Пересчитывает компоненты, если дороги менялись. Возвращает true, если пересчитал.
func update(grid: CityGrid) -> bool:
	if grid == _grid and grid.roads_version == _version:
		return false
	_grid = grid
	_version = grid.roads_version
	component_of.clear()
	component_count = 0
	for start: Vector2i in grid.road_cells:
		if component_of.has(start):
			continue
		var id: int = component_count
		component_count += 1
		# Обход в ширину; head вместо pop_front, чтобы не сдвигать массив.
		var queue: Array[Vector2i] = [start]
		component_of[start] = id
		var head: int = 0
		while head < queue.size():
			var cell: Vector2i = queue[head]
			head += 1
			for offset: Vector2i in CityGrid.NEIGHBORS:
				var next: Vector2i = cell + offset
				if grid.road_cells.has(next) and not component_of.has(next):
					component_of[next] = id
					queue.append(next)
	return true


## Компонент, к которому подключена клетка (через ближайшую дорогу), или −1.
## Связана ли клетка (через ближайшую дорогу) с въездом трассы. Без въезда — всегда да.
func reaches_highway(grid: CityGrid, cell: Vector2i) -> bool:
	if not grid.has_entry():
		return true
	var component: int = component_for(grid, cell)
	return component != -1 and component == component_of.get(grid.entry, -2)


func component_for(grid: CityGrid, cell: Vector2i) -> int:
	return component_of.get(grid.find_nearest_road(cell), -1)


## Компонент, к которому подключено здание (через ближайшую к нему дорогу), или −1.
func component_for_building(grid: CityGrid, building: BuildingInstance) -> int:
	return component_of.get(grid.find_building_road(building), -1)
