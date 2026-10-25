class_name CityGrid
extends RefCounted
## Данные карты города — единственный источник правды.
## Визуал только читает эти данные и слушает Events.

enum Tile { EMPTY, ROAD, BUILDING }
enum Zone { NONE, RESIDENTIAL, COMMERCIAL, INDUSTRIAL }

const GRID_SIZE: int = 64
## Размер клетки в мире, метры.
const CELL_SIZE: float = 2.0

## Сторона карты в клетках.
var size: int

# Слои, по одному значению на клетку. Индекс = y * size + x.
var tile_type: PackedByteArray
var zone: PackedByteArray
var building_at: PackedInt32Array

# Кэши, чтобы не сканировать всю карту.
var buildings: Dictionary[int, BuildingInstance] = {}
var road_cells: Dictionary[Vector2i, bool] = {}
var next_building_id: int = 0
## Растёт при каждом изменении дорог — по нему RoadNetwork понимает, что пора пересчитаться.
var roads_version: int = 0
## Растёт при каждой постройке и сносе здания — по нему пересчитывается трафик.
var buildings_version: int = 0
## Пустые клетки с зоной, по зонам R/C/I: Vector2i → true. Клетка здесь ⇔ EMPTY и зона не NONE.
## Обновляется только внутри CityGrid (_update_zoned_cache). Внутренний словарь без типа:
## Godot не поддерживает вложенные типизированные словари.
var zoned_empty_cells: Dictionary[Zone, Dictionary] = {
	Zone.RESIDENTIAL: {},
	Zone.COMMERCIAL: {},
	Zone.INDUSTRIAL: {},
}


func _init(p_size: int = GRID_SIZE) -> void:
	size = p_size
	var count: int = size * size
	tile_type.resize(count)
	tile_type.fill(Tile.EMPTY)
	zone.resize(count)
	zone.fill(Zone.NONE)
	building_at.resize(count)
	building_at.fill(-1)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size


## Ближайшая к cell клетка внутри карты.
func clamp_to_bounds(cell: Vector2i) -> Vector2i:
	return cell.clamp(Vector2i.ZERO, Vector2i(size - 1, size - 1))


## Индекс клетки в слоях. Клетка должна быть в границах.
func index_of(cell: Vector2i) -> int:
	return cell.y * size + cell.x


## Центр клетки в мире (высота 0).
func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)


## Клетка, в которую попадает точка мира. Может быть за границей — проверяй is_in_bounds.
func world_to_grid(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))


## Размер карты в мире, метры.
func world_size() -> float:
	return size * CELL_SIZE


# --- Дороги ---

## Биты соседей в маске дороги.
const DIR_N: int = 1  # −Z
const DIR_E: int = 2  # +X
const DIR_S: int = 4  # +Z
const DIR_W: int = 8  # −X
## Смещения соседей в порядке битов N, E, S, W.
const NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func is_road(cell: Vector2i) -> bool:
	return road_cells.has(cell)


## Можно ли поставить дорогу (те же правила, что в set_road).
func can_set_road(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and tile_type[index_of(cell)] == Tile.EMPTY


## Ставит дорогу. Единственное место изменения дорог.
## Возвращает true, если клетка изменилась. Сигнал шлёт вызывающий (пакетом).
func set_road(cell: Vector2i) -> bool:
	if not can_set_road(cell):
		return false
	var i: int = index_of(cell)
	tile_type[i] = Tile.ROAD
	zone[i] = Zone.NONE
	road_cells[cell] = true
	roads_version += 1
	_update_zoned_cache(cell)
	return true


## Убирает дорогу. Возвращает true, если клетка изменилась.
func remove_road(cell: Vector2i) -> bool:
	if not is_road(cell):
		return false
	tile_type[index_of(cell)] = Tile.EMPTY
	road_cells.erase(cell)
	roads_version += 1
	return true


## Снос клетки. Единственное место правил сноса: убирает здание или дорогу.
## Зону не трогает. Возвращает true, если клетка изменилась.
func bulldoze(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var building_id: int = building_at[index_of(cell)]
	if building_id != -1:
		return remove_building(building_id)
	return remove_road(cell)


## Маска соседей-дорог: N=1, E=2, S=4, W=8.
func get_road_mask(cell: Vector2i) -> int:
	var mask: int = 0
	for bit: int in NEIGHBORS.size():
		if is_road(cell + NEIGHBORS[bit]):
			mask |= 1 << bit
	return mask


# --- Зоны ---

## Насколько далеко (по Манхэттену) может быть дорога, чтобы у зоны был доступ.
const ROAD_ACCESS_RANGE: int = 3


## Клетка должна быть в границах.
func get_zone(cell: Vector2i) -> Zone:
	return zone[index_of(cell)] as Zone


## Можно ли поставить зону zone_type на клетку (те же правила, что в set_zone).
func can_zone(cell: Vector2i, zone_type: Zone) -> bool:
	if not is_in_bounds(cell):
		return false
	var i: int = index_of(cell)
	if tile_type[i] != Tile.EMPTY or zone[i] == zone_type:
		return false
	# Снять зону можно всегда, поставить — только рядом с дорогой.
	return zone_type == Zone.NONE or has_road_access(cell)


## Ставит или снимает (Zone.NONE) зону. Единственное место изменения зон.
## Возвращает true, если клетка изменилась. Сигнал шлёт вызывающий (пакетом).
func set_zone(cell: Vector2i, zone_type: Zone) -> bool:
	if not can_zone(cell, zone_type):
		return false
	zone[index_of(cell)] = zone_type
	_update_zoned_cache(cell)
	return true


## «Клетки нет» — для find_nearest_road.
const NO_CELL := Vector2i(-1, -1)


## Есть ли дорога на расстоянии не больше ROAD_ACCESS_RANGE клеток.
func has_road_access(cell: Vector2i) -> bool:
	return find_nearest_road(cell) != NO_CELL


## Клетка ближайшей дороги не дальше ROAD_ACCESS_RANGE (по Манхэттену) или NO_CELL.
## Ищет кольцами от расстояния 1.
func find_nearest_road(cell: Vector2i) -> Vector2i:
	for dist: int in range(1, ROAD_ACCESS_RANGE + 1):
		for dy: int in range(-dist, dist + 1):
			var dx: int = dist - absi(dy)
			if road_cells.has(cell + Vector2i(-dx, dy)):
				return cell + Vector2i(-dx, dy)
			if dx != 0 and road_cells.has(cell + Vector2i(dx, dy)):
				return cell + Vector2i(dx, dy)
	return NO_CELL


## Направление на ближайшую дорогу: 0..3 = N/E/S/W (биты как в get_road_mask), −1 — дороги нет.
## Для дороги по диагонали берётся ось с большим смещением.
func find_nearest_road_dir(cell: Vector2i) -> int:
	var road: Vector2i = find_nearest_road(cell)
	return -1 if road == NO_CELL else _dir_of(road - cell)


static func _dir_of(offset: Vector2i) -> int:
	if absi(offset.x) >= absi(offset.y):
		return 1 if offset.x > 0 else 3
	return 2 if offset.y > 0 else 0


func _update_zoned_cache(cell: Vector2i) -> void:
	for cells: Dictionary in zoned_empty_cells.values():
		cells.erase(cell)
	var i: int = index_of(cell)
	if tile_type[i] == Tile.EMPTY and zone[i] != Zone.NONE:
		zoned_empty_cells[zone[i] as Zone][cell] = true


# --- Здания ---

## Ставит здание на пустую клетку. Какой тип на какой зоне — решает вызывающий.
## clear_zone — стереть зону клетки (служебные здания: после их сноса дом не вырастет).
## Возвращает номер экземпляра или −1. Сигнал шлёт вызывающий (пакетом).
func place_building(type_id: StringName, cell: Vector2i, orientation: int, clear_zone: bool = false) -> int:
	if not is_in_bounds(cell):
		return -1
	var i: int = index_of(cell)
	if tile_type[i] != Tile.EMPTY:
		return -1
	if clear_zone:
		zone[i] = Zone.NONE
	var id: int = next_building_id
	next_building_id += 1
	buildings[id] = BuildingInstance.new(id, type_id, cell, orientation)
	buildings_version += 1
	tile_type[i] = Tile.BUILDING
	building_at[i] = id
	_update_zoned_cache(cell)
	return id


## Убирает здание. Клетка снова пустая, зона остаётся. Возвращает true, если здание было.
func remove_building(instance_id: int) -> bool:
	var building: BuildingInstance = buildings.get(instance_id)
	if building == null:
		return false
	var i: int = index_of(building.cell)
	tile_type[i] = Tile.EMPTY
	building_at[i] = -1
	buildings.erase(instance_id)
	buildings_version += 1
	_update_zoned_cache(building.cell)
	return true


## Здание на клетке или null. Клетка должна быть в границах.
func get_building_at(cell: Vector2i) -> BuildingInstance:
	return buildings.get(building_at[index_of(cell)])


# --- Загрузка ---

## Пересобирает кэши по слоям tile_type (дороги), zone и словарю buildings.
## Вызывает загрузка сохранения после прямой записи слоёв (фаза 7).
## Клетки зданий в tile_type выставляются здесь по buildings.
func rebuild_caches() -> void:
	road_cells.clear()
	building_at.fill(-1)
	for y: int in size:
		for x: int in size:
			var i: int = index_of(Vector2i(x, y))
			if tile_type[i] == Tile.ROAD:
				road_cells[Vector2i(x, y)] = true
				# Под дорогой зоны не бывает (как в set_road).
				zone[i] = Zone.NONE
			elif tile_type[i] == Tile.BUILDING:
				tile_type[i] = Tile.EMPTY
	var max_id: int = -1
	for building: BuildingInstance in buildings.values():
		var i: int = index_of(building.cell)
		tile_type[i] = Tile.BUILDING
		building_at[i] = building.id
		max_id = maxi(max_id, building.id)
	next_building_id = maxi(next_building_id, max_id + 1)
	buildings_version += 1
	for cells: Dictionary in zoned_empty_cells.values():
		cells.clear()
	for y: int in size:
		for x: int in size:
			_update_zoned_cache(Vector2i(x, y))
	roads_version += 1
