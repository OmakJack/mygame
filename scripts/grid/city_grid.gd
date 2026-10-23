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
