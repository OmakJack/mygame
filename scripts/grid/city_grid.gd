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
## Глубина полосы зоны от дороги, клеток (как в Cities: Skylines).
const STRIP_DEPTH: int = 4
## «Полосы нет» в strip_dir.
const NO_STRIP: int = 255

## Сторона карты в клетках.
var size: int

# Слои, по одному значению на клетку. Индекс = y * size + x.
var tile_type: PackedByteArray
var zone: PackedByteArray
var building_at: PackedInt32Array
## Участок клетки: номер в lots или −1. Участок появляется вместе с домом (застройщик, Growth):
## от улицы вглубь полосы, дом — у улицы, остальное — двор. Снесли дом — участок распадается.
var lot_at: PackedInt32Array
var lots: Dictionary[int, Lot] = {}
var next_lot_id: int = 0
## Растёт при каждом новом и распавшемся участке — по нему перерисовываются дворы (YardVisualizer).
var lots_version: int = 0
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
## Полоса зоны (застройщик по месту, Р1): у клетки суши — своя улица, ближайшая дорога с доступом
## по прямой не дальше STRIP_DEPTH. strip_dir — сторона на улицу 0..3 = N/E/S/W (NO_STRIP — полосы нет),
## strip_depth — расстояние до неё (1 — у самой дороги). Производные от дорог: не сохраняются.
var strip_dir: PackedByteArray
var strip_depth: PackedByteArray
## Полосы вдоль свободных дорог (диагональ, дуга; этап C3): ячейки 2×2 м под углом дороги. Клетка такой
## полосы — в strip_dir (сторона, ближняя к направлению на дорогу) и strip_depth (ряд ячейки).
## Пересчитываются при новой версии графа (ensure_strips).
var free_strips := FreeStrips.new()
var _strips_graph_version: int = -1

# Кэши, чтобы не сканировать всю карту.
var buildings: Dictionary[int, BuildingInstance] = {}
var road_cells: Dictionary[Vector2i, bool] = {}
var next_building_id: int = 0
## Растёт при каждом изменении дорог — по нему RoadNetwork понимает, что пора пересчитаться.
var roads_version: int = 0
## Граф дорог (узлы и кривые, как в Cities: Skylines): дороги игры строятся через него, клетки
## road_cells — его растр. Клетки, поставленные мимо графа, он подхватывает сам (RoadGraph.sync).
var roads := RoadGraph.new()
## Растёт при каждой постройке и сносе здания — по нему пересчитывается трафик.
var buildings_version: int = 0
## Свободная земля зон: Vector2i → true. Клетка здесь ⇔ EMPTY, зона не NONE и не двор (нет участка).
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
	strip_dir.resize(count)
	strip_dir.fill(NO_STRIP)
	strip_depth.resize(count)
	strip_depth.fill(0)


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
		# Улица ↔ шоссе: доступ к дороге меняется — и полосы вокруг.
		roads_version += 1
		_update_strips_near(cell)
		return true
	tile_type[i] = Tile.ROAD
	_dissolve_lot_at(cell)
	zone[i] = Zone.NONE
	road_cells[cell] = true
	roads_version += 1
	_update_zoned_cache(cell)
	_update_strips_near(cell)
	return true


## Убирает дорогу. Возвращает true, если клетка изменилась. Трассу у въезда не убрать.
func remove_road(cell: Vector2i) -> bool:
	if not is_road(cell) or highway_cells.has(cell):
		return false
	tile_type[index_of(cell)] = Tile.EMPTY
	road_type[index_of(cell)] = 0
	road_cells.erase(cell)
	roads_version += 1
	_update_strips_near(cell)
	return true


## Снос клетки. Единственное место правил сноса: убирает здание или дорогу.
## Зону не трогает. Возвращает true, если клетка изменилась.
func bulldoze(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var building_id: int = building_at[index_of(cell)]
	if building_id != -1:
		return remove_building(building_id)
	# Двор сносится вместе с домом.
	var owner: BuildingInstance = get_building_or_yard(cell)
	if owner != null:
		return remove_building(owner.id)
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
	# Снять зону можно всегда, поставить — только на полосу у дороги.
	return zone_type == Zone.NONE or in_strip(cell)


static func _same_density_family(a: Zone, b: Zone) -> bool:
	var ca: Zone = zone_category(a)
	return ca == zone_category(b) and ca != Zone.INDUSTRIAL


## Ставит или снимает (Zone.NONE) зону. Единственное место изменения зон.
## Возвращает true, если клетка изменилась. Сигнал шлёт вызывающий (пакетом).
func set_zone(cell: Vector2i, zone_type: Zone) -> bool:
	if not can_zone(cell, zone_type):
		return false
	var i: int = index_of(cell)
	# Двор перекрасили в другую зону (или сняли) — участок распадается, дом остаётся без двора.
	# Смена плотности (R ↔ R высокая) двор не трогает: дом перестроится на том же участке.
	if lot_at[i] != -1 and tile_type[i] == Tile.EMPTY and (zone_type == Zone.NONE or zone[i] == Zone.NONE
			or not _same_density_family(zone[i] as Zone, zone_type)):
		_dissolve_lot_at(cell)
	zone[i] = zone_type
	_update_zoned_cache(cell)
	return true


# --- Полосы зон ---

## Есть ли у клетки полоса зоны (можно размечать, может вырасти дом).
func in_strip(cell: Vector2i) -> bool:
	ensure_strips()
	return is_in_bounds(cell) and strip_dir[index_of(cell)] != NO_STRIP


## Сторона на улицу полосы клетки 0..3 = N/E/S/W или −1 — полосы нет.
func get_strip_dir(cell: Vector2i) -> int:
	ensure_strips()
	if not is_in_bounds(cell):
		return -1
	var dir: int = strip_dir[index_of(cell)]
	return -1 if dir == NO_STRIP else dir


## Расстояние клетки до её улицы (1 — у самой дороги) или 0 — полосы нет.
func get_strip_depth(cell: Vector2i) -> int:
	ensure_strips()
	return strip_depth[index_of(cell)] if is_in_bounds(cell) else 0


## Ячейка полосы свободной дороги у клетки или null (клетка — в полосе из клеток или вне полос).
func free_slot(cell: Vector2i) -> FreeStrips.Slot:
	ensure_strips()
	return free_strips.slot_at(cell)


## Клетка дороги, к которой выходит полоса клетки (для связи с трассой); NO_CELL — полосы нет.
func strip_road(cell: Vector2i) -> Vector2i:
	var slot: FreeStrips.Slot = free_slot(cell)
	if slot != null:
		return slot.road
	var dir: int = get_strip_dir(cell)
	return cell + NEIGHBORS[dir] * get_strip_depth(cell) if dir >= 0 else NO_CELL


## Полосы по графу дорог: при новой версии графа — заново полосы из клеток (дороги по сетке) и ячейки
## вдоль свободных дорог (FreeStrips); клетка — к той дороге, чей край ближе (поровну — полоса из клеток).
func ensure_strips() -> void:
	roads.sync(self)
	if roads.version == _strips_graph_version:
		return
	_strips_graph_version = roads.version
	var candidates: Dictionary[Vector2i, Array] = free_strips.candidates(self)
	rebuild_strips()
	var owners: Dictionary[Vector2i, Array] = {}
	for cell: Vector2i in candidates:
		var i: int = index_of(cell)
		# Край дороги по сетке от центра клетки ряда k — 2k − 1 м.
		if strip_dir[i] != NO_STRIP and strip_depth[i] * CELL_SIZE - CELL_SIZE * 0.5 <= candidates[cell][0] + 0.001:
			continue
		owners[cell] = candidates[cell]
		strip_dir[i] = NO_STRIP
		strip_depth[i] = 0
	free_strips.build(self, owners)
	for cell: Vector2i in free_strips.slot_of_cell:
		var slot: FreeStrips.Slot = free_strips.slot_at(cell)
		var i: int = index_of(cell)
		strip_dir[i] = _dir_of_vector(slot.front)
		strip_depth[i] = slot.row
	_mark_free_lots()


## Сторона 0..3 = N/E/S/W, ближайшая к направлению dir (мир x, z).
static func _dir_of_vector(dir: Vector2) -> int:
	if absf(dir.x) >= absf(dir.y):
		return 1 if dir.x > 0.0 else 3
	return 2 if dir.y > 0.0 else 0


## Какие ячейки свободных полос заняты участками (по форме участка — номера ячеек новые).
func _mark_free_lots() -> void:
	free_strips.occupied.clear()
	for lot: Lot in lots.values():
		if lot.poly.is_empty():
			continue
		_occupy_slots(lot)


func _occupy_slots(lot: Lot) -> void:
	var seen: Dictionary[Vector3i, bool] = {}
	for cell: Vector2i in lot.shape:
		var slot: FreeStrips.Slot = free_strips.slot_at(cell)
		if slot == null:
			continue
		var key := Vector3i(slot.segment, slot.side, slot.col)
		if seen.has(key):
			continue
		# Соседние колонки — там могут быть ячейки участка без клеток.
		for dc: int in [-1, 0, 1]:
			seen[Vector3i(slot.segment, slot.side, slot.col + dc)] = true
			for row: int in range(1, FreeStrips.DEPTH + 1):
				var other: FreeStrips.Slot = free_strips.slot_in(slot.segment, slot.side, slot.col + dc, row)
				if other != null and Geometry2D.is_point_in_polygon(other.center, lot.poly):
					free_strips.occupied[other.id] = lot.id


## Пересчитывает полосы всей карты (загрузка).
func rebuild_strips() -> void:
	for y: int in size:
		for x: int in size:
			_compute_strip(Vector2i(x, y))


## Дорога на cell появилась или исчезла: пересчёт клеток, до которых от неё ≤ STRIP_DEPTH по прямой.
func _update_strips_near(cell: Vector2i) -> void:
	_compute_strip(cell)
	for dir: int in 4:
		for k: int in range(1, STRIP_DEPTH + 1):
			var c: Vector2i = cell + NEIGHBORS[dir] * k
			if not is_in_bounds(c):
				break
			_compute_strip(c)


## Полоса клетки: ближайшая дорога с доступом по прямой в 4 стороны, не дальше STRIP_DEPTH.
## Луч обрывается на любой дороге (шоссе загораживает), воде и краю карты. При равном расстоянии —
## меньшая сторона (N, E, S, W): углы кварталов делятся «лесенкой».
func _compute_strip(cell: Vector2i) -> void:
	var i: int = index_of(cell)
	var best_dir: int = NO_STRIP
	var best_depth: int = 0
	if tile_type[i] != Tile.ROAD and water[i] == 0:
		for dir: int in 4:
			var limit: int = STRIP_DEPTH if best_dir == NO_STRIP else best_depth - 1
			for k: int in range(1, limit + 1):
				var c: Vector2i = cell + NEIGHBORS[dir] * k
				if not is_in_bounds(c) or water[index_of(c)] == 1:
					break
				if road_cells.has(c):
					if _is_land_road(c) and not _is_free_road(c):
						best_dir = dir
						best_depth = k
					break
	strip_dir[i] = best_dir
	strip_depth[i] = best_depth


## Клетка только свободных дорог (их полосы — ячейки FreeStrips, не клетки).
func _is_free_road(cell: Vector2i) -> bool:
	var owners: Array[int] = roads.owners_of(cell)
	if owners.is_empty():
		return false
	for id: int in owners:
		if not free_strips.frames.has(id):
			return false
	return true


# --- Участки ---

## Участок под одно здание: прямоугольник клеток и сторона фасада (к дороге, 0..3 = N/E/S/W).
## Дом стоит у фасада, остальные клетки участка — его двор.
class Lot extends RefCounted:
	var id: int
	var rect: Rect2i
	var dir: int
	## Участок вдоль свободной дороги (этап C3): углы (многоугольник в мире) и клетки сетки, чьи центры
	## в нём; rect — их охват. Пусто — обычный участок-прямоугольник клеток.
	var poly := PackedVector2Array()
	var shape: Array[Vector2i] = []

	func _init(p_id: int, p_rect: Rect2i, p_dir: int) -> void:
		id = p_id
		rect = p_rect
		dir = p_dir

	## Размер типа здания для участка: x — вдоль фасада, y — вглубь (как BuildingData.size).
	func building_size() -> Vector2i:
		return rect.size if posmod(dir, 2) == 0 else Vector2i(rect.size.y, rect.size.x)

	func cells() -> Array[Vector2i]:
		if not shape.is_empty():
			return shape.duplicate()
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
	lots_version += 1
	lots[id] = Lot.new(id, rect, dir)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			lot_at[index_of(Vector2i(x, y))] = id
			_update_zoned_cache(Vector2i(x, y))
	return id


## Новый участок вдоль свободной дороги: клетки cells, углы poly, сторона фасада dir. Номер участка.
func add_free_lot(cells: Array[Vector2i], poly: PackedVector2Array, dir: int) -> int:
	for cell: Vector2i in cells:
		var old: int = lot_at[index_of(cell)]
		if old != -1:
			dissolve_lot(old)
	var id: int = next_lot_id
	next_lot_id += 1
	lots_version += 1
	var lot := Lot.new(id, _bounds(cells), dir)
	lot.poly = poly
	lot.shape = cells.duplicate()
	lots[id] = lot
	for cell: Vector2i in cells:
		lot_at[index_of(cell)] = id
		_update_zoned_cache(cell)
	if _strips_graph_version == roads.version:
		_occupy_slots(lot)
	return id


## Охват клеток прямоугольником.
static func _bounds(cells: Array[Vector2i]) -> Rect2i:
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for cell: Vector2i in cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Убирает участок: клетки двора снова свободная земля зоны.
func dissolve_lot(id: int) -> void:
	var lot: Lot = lots.get(id)
	if lot == null:
		return
	lots.erase(id)
	lots_version += 1
	if not lot.poly.is_empty():
		for slot: int in free_strips.occupied.keys():
			if free_strips.occupied[slot] == id:
				free_strips.occupied.erase(slot)
	for cell: Vector2i in lot.cells():
		if is_in_bounds(cell) and lot_at[index_of(cell)] == id:
			lot_at[index_of(cell)] = -1
			_update_zoned_cache(cell)


## Дом участка или null (участок без дома бывает только между постановкой дома и add_lot).
func building_on_lot(lot: Lot) -> BuildingInstance:
	for cell: Vector2i in lot.cells():
		if is_in_bounds(cell) and building_at[index_of(cell)] != -1:
			return buildings.get(building_at[index_of(cell)])
	return null


## Участок здания или null.
func lot_of(building: BuildingInstance) -> Lot:
	return get_lot(building.shape[0] if building.is_free() else building.cell)


## Здание на клетке или дом, чей это двор; null — ни того, ни другого.
func get_building_or_yard(cell: Vector2i) -> BuildingInstance:
	if not is_in_bounds(cell):
		return null
	var building: BuildingInstance = buildings.get(building_at[index_of(cell)])
	if building != null:
		return building
	var lot: Lot = get_lot(cell)
	return building_on_lot(lot) if lot != null else null


## Двор ли это: клетка участка без здания.
func is_yard(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and lot_at[index_of(cell)] != -1 and building_at[index_of(cell)] == -1


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
	if tile_type[i] == Tile.EMPTY and zone[i] != Zone.NONE and lot_at[i] == -1:
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
		# Служба на чужом дворе: участок того дома распадается (застройщик ставит дом до участка).
		_dissolve_lot_at(c)
		var i: int = index_of(c)
		if clear_zone:
			zone[i] = Zone.NONE
		tile_type[i] = Tile.BUILDING
		building_at[i] = id
		_update_zoned_cache(c)
	return id


## Ставит дом под углом дороги (полоса свободной дороги): клетки shape, середина center (мир x, z),
## поворот yaw (Basis(UP, yaw)), сторона фасада dir (ближайшая из 0..3). Номер экземпляра или −1.
func place_free_building(type_id: StringName, shape: Array[Vector2i], center: Vector2, yaw: float, dir: int) -> int:
	if shape.is_empty():
		return -1
	for c: Vector2i in shape:
		if not is_in_bounds(c) or tile_type[index_of(c)] != Tile.EMPTY or water[index_of(c)] != 0:
			return -1
	var id: int = next_building_id
	next_building_id += 1
	var bounds: Rect2i = _bounds(shape)
	var building := BuildingInstance.new(id, type_id, bounds.position, dir, bounds.size)
	building.shape = shape.duplicate()
	building.center = center
	building.yaw = yaw
	buildings[id] = building
	buildings_version += 1
	for c: Vector2i in shape:
		_dissolve_lot_at(c)
		var i: int = index_of(c)
		tile_type[i] = Tile.BUILDING
		building_at[i] = id
		_update_zoned_cache(c)
	return id


## Прямоугольник дома под углом дороги в мире (x, z), чуть ужатый — соседям можно касаться.
func free_footprint(building: BuildingInstance) -> PackedVector2Array:
	var data: BuildingData = BuildingCatalog.get_type(building.type_id)
	var size: Vector2 = Vector2(data.size) * CELL_SIZE * 0.5 - Vector2.ONE * 0.05 if data != null else Vector2.ONE
	var front := Vector2(-sin(building.yaw), -cos(building.yaw))
	var along := Vector2(front.y, -front.x)
	var c: Vector2 = building.center
	return PackedVector2Array([c + along * size.x + front * size.y, c - along * size.x + front * size.y,
			c - along * size.x - front * size.y, c + along * size.x - front * size.y])


## Где и как стоит здание в мире: по клеткам (поворот на 90°) или под углом дороги.
func building_transform(building: BuildingInstance) -> Transform3D:
	if building.is_free():
		return Transform3D(Basis(Vector3.UP, building.yaw), Vector3(building.center.x, 0.0, building.center.y))
	return Transform3D(Basis(Vector3.UP, -building.orientation * PI * 0.5), footprint_center(building.cell, building.size))


## Убирает здание вместе с его участком (двор снова свободен — застройщик решит заново).
## Клетки снова пустые, зона остаётся. Возвращает true, если здание было.
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
	_dissolve_lot_at(occupied[0] if building.is_free() else building.cell)
	for c: Vector2i in occupied:
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
		if data != null and not building.is_free():
			building.size = data.footprint(building.orientation)
		for c: Vector2i in building.cells():
			if is_in_bounds(c):
				var i: int = index_of(c)
				tile_type[i] = Tile.BUILDING
				building_at[i] = building.id
		max_id = maxi(max_id, building.id)
	next_building_id = maxi(next_building_id, max_id + 1)
	buildings_version += 1
	# Участок живёт только с домом: без дома — прочь (двор снова свободная земля).
	lot_at.fill(-1)
	var max_lot: int = -1
	for lot: Lot in lots.values():
		max_lot = maxi(max_lot, lot.id)
		if building_on_lot(lot) == null:
			lots.erase(lot.id)
			continue
		for cell: Vector2i in lot.cells():
			if is_in_bounds(cell):
				lot_at[index_of(cell)] = lot.id
	next_lot_id = maxi(next_lot_id, max_lot + 1)
	lots_version += 1
	for cells: Dictionary in zoned_empty_cells.values():
		cells.clear()
	for y: int in size:
		for x: int in size:
			_update_zoned_cache(Vector2i(x, y))
	rebuild_strips()
	_strips_graph_version = -1
	roads_version += 1
