class_name CityGrid
extends RefCounted
## Данные карты города — единственный источник правды.
## Визуал только читает эти данные и слушает Events.

enum Tile { EMPTY, ROAD, BUILDING }
## Значения 0..3 не менять: на них держатся сохранения. Новые — только в конец (фаза 10).
enum Zone { NONE, RESIDENTIAL, COMMERCIAL, INDUSTRIAL, RESIDENTIAL_HIGH, COMMERCIAL_HIGH, OFFICE }

const GRID_SIZE: int = 64
## Размер клетки в мире, метры.
const CELL_SIZE: float = 2.0

## Сторона карты в клетках.
var size: int

# Слои, по одному значению на клетку. Индекс = y * size + x.
var tile_type: PackedByteArray
var zone: PackedByteArray
var building_at: PackedInt32Array
## Участок клетки (как в Cities: Skylines): номер в lots или −1. Участок задаёт игрок разметкой зоны:
## на нём вырастает ровно одно здание его размера (LotPlanner делит большое выделение на участки).
var lot_at: PackedInt32Array
var lots: Dictionary[int, Lot] = {}
var next_lot_id: int = 0
## Вода (фаза 9): 1 — вода, 0 — суша. Отдельный слой: дорога-мост лежит поверх воды, после сноса вода остаётся.
var water: PackedByteArray
## Тип дороги на клетке (RoadTypes.Type, фаза 11): 0 — нет дороги, 1 — улица, 2 — проспект, 3 — шоссе.
var road_type: PackedByteArray
## Въезд трассы (как в Cities: Skylines): клетка на краю карты и направление наружу (0..3 = N/E/S/W).
## От въезда внутрь карты лежит отрезок трассы (highway_cells) — его нельзя снести. Город растёт
## только у дорог, связанных с въездом. NO_CELL — въезда нет (старые сохранения, тесты): рост без условия.
var entry: Vector2i = Vector2i(-1, -1)
var entry_dir: int = 0
var highway_cells: Dictionary[Vector2i, bool] = {}

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
	Zone.RESIDENTIAL_HIGH: {},
	Zone.COMMERCIAL_HIGH: {},
	Zone.OFFICE: {},
}


## Категория зоны для спроса и подсчёта: высокая плотность — к своей зоне, офисы — к промзоне
## («базовые» рабочие места, ревью Argon 013).
static func zone_category(zone_type: Zone) -> Zone:
	match zone_type:
		Zone.RESIDENTIAL_HIGH:
			return Zone.RESIDENTIAL
		Zone.COMMERCIAL_HIGH:
			return Zone.COMMERCIAL
		Zone.OFFICE:
			return Zone.INDUSTRIAL
	return zone_type


## Жильё ли это (любой плотности).
static func is_residential(zone_type: Zone) -> bool:
	return zone_category(zone_type) == Zone.RESIDENTIAL


func _init(p_size: int = GRID_SIZE) -> void:
	size = p_size
	var count: int = size * size
	tile_type.resize(count)
	tile_type.fill(Tile.EMPTY)
	zone.resize(count)
	zone.fill(Zone.NONE)
	building_at.resize(count)
	building_at.fill(-1)
	lot_at.resize(count)
	lot_at.fill(-1)
	water.resize(count)
	water.fill(0)
	road_type.resize(count)
	road_type.fill(0)


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


## Центр прямоугольника клеток (левый верхний угол cell, габариты span) в мире (высота 0).
func footprint_center(cell: Vector2i, span: Vector2i = Vector2i.ONE) -> Vector3:
	return Vector3((cell.x + span.x * 0.5) * CELL_SIZE, 0.0, (cell.y + span.y * 0.5) * CELL_SIZE)


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


## Есть ли въезд трассы.
func has_entry() -> bool:
	return entry != NO_CELL


## Ставит въезд: трасса length клеток от края внутрь (по направлению dir наружу). Клетки трассы — дороги.
func set_entry(edge_cell: Vector2i, dir: int, length: int) -> void:
	entry = edge_cell
	entry_dir = dir
	highway_cells.clear()
	var inward: Vector2i = -NEIGHBORS[dir]
	for k: int in length:
		var cell: Vector2i = edge_cell + inward * k
		if not is_in_bounds(cell):
			break
		# При загрузке дорога уже лежит; на новой карте клетка пустая (вода обойдена генератором).
		if is_road(cell) or set_road(cell, RoadTypes.Type.HIGHWAY):
			road_type[index_of(cell)] = RoadTypes.Type.HIGHWAY
			highway_cells[cell] = true


## Клетки трассы за картой: от края наружу на count клеток (только для вида — их нет в слоях).
func outside_highway(count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not has_entry():
		return cells
	for k: int in range(1, count + 1):
		cells.append(entry + NEIGHBORS[entry_dir] * k)
	return cells


## Вода на клетке. Клетка должна быть в границах.
func is_water(cell: Vector2i) -> bool:
	return water[index_of(cell)] == 1


## Можно ли поставить здание размера span (левый верхний угол — cell): все клетки пустые и на суше.
func can_place_building(cell: Vector2i, span: Vector2i = Vector2i.ONE) -> bool:
	for dy: int in span.y:
		for dx: int in span.x:
			var c := Vector2i(cell.x + dx, cell.y + dy)
			if not is_in_bounds(c):
				return false
			var i: int = index_of(c)
			if tile_type[i] != Tile.EMPTY or water[i] != 0:
				return false
	return true


## Можно ли поставить дорогу (те же правила, что в set_road).
func can_set_road(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and tile_type[index_of(cell)] == Tile.EMPTY


## Тип дороги на клетке (RoadTypes.Type); 0 — дороги нет.
func get_road_type(cell: Vector2i) -> int:
	return road_type[index_of(cell)] if is_in_bounds(cell) else 0


## Можно ли проложить дорогу типа type: на пустой клетке — новая, на дороге другого типа — замена
## («улучшить» улицу до проспекта или обратно). Трассу у въезда не перестроить.
func can_build_road(cell: Vector2i, type: int = RoadTypes.Type.STREET) -> bool:
	if can_set_road(cell):
		return true
	return is_road(cell) and road_type[index_of(cell)] != type and not highway_cells.has(cell)


## Ставит дорогу типа type или меняет тип уже лежащей. Единственное место изменения дорог.
## Возвращает true, если клетка изменилась. Сигнал шлёт вызывающий (пакетом).
func set_road(cell: Vector2i, type: int = RoadTypes.Type.STREET) -> bool:
	if not can_build_road(cell, type):
		return false
	var i: int = index_of(cell)
	road_type[i] = type
	if tile_type[i] == Tile.ROAD:
		roads_version += 1
		return true
	tile_type[i] = Tile.ROAD
	_dissolve_lot_at(cell)
	zone[i] = Zone.NONE
	road_cells[cell] = true
	roads_version += 1
	_update_zoned_cache(cell)
	return true


## Убирает дорогу. Возвращает true, если клетка изменилась. Трассу у въезда не убрать.
func remove_road(cell: Vector2i) -> bool:
	if not is_road(cell) or highway_cells.has(cell):
		return false
	tile_type[index_of(cell)] = Tile.EMPTY
	road_type[index_of(cell)] = 0
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
	if zone[i] == zone_type:
		return false
	# Под домом можно сменить плотность той же категории (R ↔ R высокая, C ↔ C высокая):
	# дом потом перестроится (фаза 10). Офисы и промзона — разные зоны, хоть и одна категория.
	if tile_type[i] == Tile.BUILDING:
		return zone[i] != Zone.NONE and zone_type != Zone.NONE and _same_density_family(zone[i] as Zone, zone_type)
	if tile_type[i] != Tile.EMPTY:
		return false
	# На воде зон нет; снять зону с воды нечего.
	if water[i] == 1:
		return false
	# Снять зону можно всегда, поставить — только рядом с дорогой.
	return zone_type == Zone.NONE or has_road_access(cell)


static func _same_density_family(a: Zone, b: Zone) -> bool:
	var ca: Zone = zone_category(a)
	return ca == zone_category(b) and ca != Zone.INDUSTRIAL


## Ставит или снимает (Zone.NONE) зону. Единственное место изменения зон.
## Возвращает true, если клетка изменилась. Сигнал шлёт вызывающий (пакетом).
func set_zone(cell: Vector2i, zone_type: Zone) -> bool:
	if not can_zone(cell, zone_type):
		return false
	if zone_type == Zone.NONE:
		_dissolve_lot_at(cell)
	zone[index_of(cell)] = zone_type
	_update_zoned_cache(cell)
	return true


# --- Участки ---

## Участок под одно здание: прямоугольник клеток и сторона фасада (к дороге, 0..3 = N/E/S/W).
class Lot extends RefCounted:
	var id: int
	var rect: Rect2i
	var dir: int

	func _init(p_id: int, p_rect: Rect2i, p_dir: int) -> void:
		id = p_id
		rect = p_rect
		dir = p_dir

	## Размер типа здания для участка: x — вдоль фасада, y — вглубь (как BuildingData.size).
	func building_size() -> Vector2i:
		return rect.size if posmod(dir, 2) == 0 else Vector2i(rect.size.y, rect.size.x)

	func cells() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				result.append(Vector2i(x, y))
		return result


## Участок клетки или null.
func get_lot(cell: Vector2i) -> Lot:
	if not is_in_bounds(cell):
		return null
	return lots.get(lot_at[index_of(cell)])


## Новый участок (клетки, что были в других участках, сначала освобождаются от них). Номер участка.
func add_lot(rect: Rect2i, dir: int) -> int:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var old: int = lot_at[index_of(Vector2i(x, y))]
			if old != -1:
				dissolve_lot(old)
	var id: int = next_lot_id
	next_lot_id += 1
	lots[id] = Lot.new(id, rect, dir)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			lot_at[index_of(Vector2i(x, y))] = id
	return id


## Убирает участок: клетки остаются с зоной, но без участка (растут одиночными домами).
func dissolve_lot(id: int) -> void:
	var lot: Lot = lots.get(id)
	if lot == null:
		return
	for cell: Vector2i in lot.cells():
		if is_in_bounds(cell) and lot_at[index_of(cell)] == id:
			lot_at[index_of(cell)] = -1
	lots.erase(id)


func _dissolve_lot_at(cell: Vector2i) -> void:
	var id: int = lot_at[index_of(cell)]
	if id != -1:
		dissolve_lot(id)


## «Клетки нет» — для find_nearest_road.
const NO_CELL := Vector2i(-1, -1)


## Есть ли дорога на расстоянии не больше ROAD_ACCESS_RANGE клеток.
func has_road_access(cell: Vector2i) -> bool:
	return find_nearest_road(cell) != NO_CELL


## Клетка ближайшей дороги на суше не дальше ROAD_ACCESS_RANGE (по Манхэттену) или NO_CELL.
## Ищет кольцами от расстояния 1. Мост над водой доступа не даёт: к нему с берега не подъехать
## (ревью Argon 014).
func find_nearest_road(cell: Vector2i) -> Vector2i:
	for dist: int in range(1, ROAD_ACCESS_RANGE + 1):
		for dy: int in range(-dist, dist + 1):
			var dx: int = dist - absi(dy)
			if _is_land_road(cell + Vector2i(-dx, dy)):
				return cell + Vector2i(-dx, dy)
			if dx != 0 and _is_land_road(cell + Vector2i(dx, dy)):
				return cell + Vector2i(dx, dy)
	return NO_CELL


## Дорога, к которой подключается дом: на суше и не шоссе.
func is_access_road(cell: Vector2i) -> bool:
	return _is_land_road(cell)


func _is_land_road(cell: Vector2i) -> bool:
	if not road_cells.has(cell):
		return false
	var i: int = index_of(cell)
	return water[i] == 0 and RoadTypes.gives_access(road_type[i])


## Есть ли дорога рядом с построенным зданием (по фасадному краю или любой клетке участка).
func has_building_road_access(building: BuildingInstance) -> bool:
	return find_building_road(building) != NO_CELL


## Ближайшая к зданию дорога: сначала у фасадного края (вход), иначе у любой клетки участка.
func find_building_road(building: BuildingInstance) -> Vector2i:
	var best: Vector2i = _closest_road_to_cells(building.front_cells())
	if best != NO_CELL:
		return best
	if building.size == Vector2i.ONE:
		return NO_CELL
	return _closest_road_to_cells(building.cells())


func _closest_road_to_cells(cells: Array[Vector2i]) -> Vector2i:
	var best: Vector2i = NO_CELL
	var best_dist: int = ROAD_ACCESS_RANGE + 1
	for c: Vector2i in cells:
		var road: Vector2i = find_nearest_road(c)
		if road == NO_CELL:
			continue
		var d: int = absi(road.x - c.x) + absi(road.y - c.y)
		if d < best_dist:
			best_dist = d
			best = road
			if d == 1:
				return best
	return best


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

## Ставит здание на пустой участок (левая верхняя клетка — cell, габариты — из типа и orientation).
## clear_zone — стереть зону клеток (служебные здания: после их сноса дом не вырастет).
## Возвращает номер экземпляра или −1. Сигнал шлёт вызывающий (пакетом).
func place_building(type_id: StringName, cell: Vector2i, orientation: int, clear_zone: bool = false) -> int:
	var data: BuildingData = BuildingCatalog.get_type(type_id)
	var span: Vector2i = data.footprint(orientation) if data != null else Vector2i.ONE
	if not can_place_building(cell, span):
		return -1
	var id: int = next_building_id
	next_building_id += 1
	var building := BuildingInstance.new(id, type_id, cell, orientation, span)
	buildings[id] = building
	buildings_version += 1
	for c: Vector2i in building.cells():
		var i: int = index_of(c)
		if clear_zone:
			zone[i] = Zone.NONE
		tile_type[i] = Tile.BUILDING
		building_at[i] = id
		_update_zoned_cache(c)
	return id


## Убирает здание. Все его клетки снова пустые, зона остаётся. Возвращает true, если здание было.
func remove_building(instance_id: int) -> bool:
	var building: BuildingInstance = buildings.get(instance_id)
	if building == null:
		return false
	var occupied: Array[Vector2i] = building.cells()
	buildings.erase(instance_id)
	buildings_version += 1
	for c: Vector2i in occupied:
		var i: int = index_of(c)
		tile_type[i] = Tile.EMPTY
		building_at[i] = -1
		_update_zoned_cache(c)
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
			if water[i] == 1:
				# На воде зон не бывает (как в can_zone).
				zone[i] = Zone.NONE
			if tile_type[i] == Tile.ROAD:
				road_cells[Vector2i(x, y)] = true
				if road_type[i] == 0:
					road_type[i] = RoadTypes.Type.STREET
				# Под дорогой зоны не бывает (как в set_road).
				zone[i] = Zone.NONE
			elif tile_type[i] == Tile.BUILDING:
				tile_type[i] = Tile.EMPTY
	var max_id: int = -1
	for building: BuildingInstance in buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null:
			building.size = data.footprint(building.orientation)
		for c: Vector2i in building.cells():
			if is_in_bounds(c):
				var i: int = index_of(c)
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
	lot_at.fill(-1)
	var max_lot: int = -1
	for lot: Lot in lots.values():
		for cell: Vector2i in lot.cells():
			if is_in_bounds(cell):
				lot_at[index_of(cell)] = lot.id
		max_lot = maxi(max_lot, lot.id)
	next_lot_id = maxi(next_lot_id, max_lot + 1)
	roads_version += 1
