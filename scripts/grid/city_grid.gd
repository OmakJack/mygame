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


## Ставит дорогу. Единственное место изменения дорог.
## Возвращает true, если клетка изменилась. Сигнал шлёт вызывающий (пакетом).
func set_road(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var i: int = index_of(cell)
	if tile_type[i] != Tile.EMPTY:
		return false
	tile_type[i] = Tile.ROAD
	zone[i] = Zone.NONE
	road_cells[cell] = true
	return true


## Убирает дорогу. Возвращает true, если клетка изменилась.
func remove_road(cell: Vector2i) -> bool:
	if not is_road(cell):
		return false
	tile_type[index_of(cell)] = Tile.EMPTY
	road_cells.erase(cell)
	return true


## Снос клетки. Единственное место правил сноса: убирает дорогу (фаза 4 — и здание).
## Зону не трогает. Возвращает true, если клетка изменилась.
func bulldoze(cell: Vector2i) -> bool:
	return remove_road(cell)


## Маска соседей-дорог: N=1, E=2, S=4, W=8.
func get_road_mask(cell: Vector2i) -> int:
	var mask: int = 0
	for bit: int in NEIGHBORS.size():
		if is_road(cell + NEIGHBORS[bit]):
			mask |= 1 << bit
	return mask
