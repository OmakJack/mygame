class_name FreeStrips
extends RefCounted
## Полосы зон вдоль «свободных» дорог (этап C3, как в Cities: Skylines): у диагонали, дуги и дороги
## не по центрам клеток зона — не клетки сетки, а ячейки 2×2 м вдоль края полотна, по 4 ряда вглубь
## с каждой стороны. Колонки ячеек — по длине дуги отрезка (на дуге — «веером»), ряды — от края полотна.
## Клетка сетки принадлежит ячейке, в которую попал её центр (ячейка может остаться и без клеток);
## дом встаёт на ряд ячеек под углом дороги (CityGrid.place_free_building).
## Дороги по центрам клеток вдоль осей — по-прежнему полосы из клеток (CityGrid._compute_strip).
## Строится заново при каждой новой версии графа (CityGrid.ensure_strips); номера ячеек меняются,
## участки помнят себя по форме (многоугольник), не по номерам.
## Зона — у ячейки (Slot.zone), а не у клеток: на диагонали в каждую пятую ячейку не попадает ни одного
## центра клетки. Клетки ячейки зону повторяют (рост, уровни и слои считают по клеткам). При перестройке
## зоны переносятся на новые ячейки по месту (zone_marks → CityGrid.ensure_strips).

## Ячейка: шаг вдоль дороги и глубина ряда, м; рядов.
const ROW: float = 2.0
const DEPTH: int = 4
## Отступ ячеек от конца отрезка: у тупика — за разворотный круг; у узла — за край полотна узла.
const DEAD_END_MARGIN: float = 1.3
const JUNCTION_MARGIN: float = 0.3
## Ячейка меньше (сжата на внутренней стороне крутой дуги) — не ячейка, м².
const MIN_AREA: float = 2.0
## Центр клетки дальше от перпендикуляра к отрезку (за концом отрезка) — не в полосе, м.
const END_SLACK: float = 0.1
## Допуск: дом выходит за боковой край своих колонок или на полотно не больше чем на столько, м.
const FIT_SLACK: float = 0.05
## Дальше дом от полотна не отодвигается (внутренняя сторона крутой дуги — не встаёт), м.
const MAX_SETBACK: float = 1.0
## Зона переходит на новую ячейку со старой, если их середины не дальше, м (колонки сдвигаются до 1 м).
const MARK_RADIUS: float = 1.5
## Дальше стольких отрезков зона одним движением вдоль дороги не тянется.
const MAX_CHAIN: int = 12


## Ячейка зоны вдоль отрезка.
class Slot extends RefCounted:
	var id: int = -1
	var segment: int = -1
	## 1 — слева от направления a → b, −1 — справа.
	var side: int = 1
	var col: int = 0
	## Ряд от края полотна: 1 — у самой дороги.
	var row: int = 1
	## Углы: у дороги в начале и в конце колонки, вглубь в конце и в начале.
	var corners := PackedVector2Array()
	var center := Vector2.ZERO
	## Единичный вектор от ячейки к дороге (фасад дома).
	var front := Vector2.ZERO
	## Клетки сетки, чьи центры в ячейке.
	var cells: Array[Vector2i] = []
	## Ближайшая к ячейке клетка её отрезка (связь с трассой, поток машин у магазина).
	var road: Vector2i = Vector2i(-1, -1)
	## Зона ячейки (CityGrid.Zone); меняет только CityGrid.set_slot_zone.
	var zone: int = 0


## Колонки отрезка: начало первой по дуге от узла a, сколько их, полуширина полотна.
class Frame extends RefCounted:
	var curve := PackedVector2Array()
	var table := PackedFloat32Array()
	var offset: float = 0.0
	var count: int = 0
	var half: float = 1.0


var slots: Array[Slot] = []
var slot_of_cell: Dictionary[Vector2i, int] = {}
## (отрезок, сторона, колонка) → номера ячеек по рядам (−1 — ячейки нет).
var columns: Dictionary[Vector3i, PackedInt32Array] = {}
## Ячейка → участок (CityGrid.Lot), который её занял.
var occupied: Dictionary[int, int] = {}
var frames: Dictionary[int, Frame] = {}
var _graph: RoadGraph


## «Свободный» ли отрезок: не прямая вдоль оси по центрам клеток (те — полосы из клеток).
static func is_free(graph: RoadGraph, segment: RoadGraph.Segment) -> bool:
	var c: PackedVector2Array = graph.curve(segment)
	if c[1].distance_to((c[0] + c[2]) * 0.5) > 0.05:
		return true
	var d: Vector2 = c[2] - c[0]
	if absf(d.x) > 0.05 and absf(d.y) > 0.05:
		return true
	var across: float = c[0].y if absf(d.y) <= 0.05 else c[0].x
	return absf(fposmod(across, CityGrid.CELL_SIZE) - CityGrid.CELL_SIZE * 0.5) > 0.05


## Зонируемый ли отрезок: свободный и даёт доступ (шоссе — нет).
static func zonable(graph: RoadGraph, segment: RoadGraph.Segment) -> bool:
	return RoadTypes.gives_access(segment.type) and is_free(graph, segment)


func clear() -> void:
	slots.clear()
	slot_of_cell.clear()
	columns.clear()
	occupied.clear()
	frames.clear()


func slot_at(cell: Vector2i) -> Slot:
	var id: int = slot_of_cell.get(cell, -1)
	return slots[id] if id != -1 else null


## Ячейка колонки в ряду row или null.
func slot_in(segment: int, side: int, col: int, row: int) -> Slot:
	var ids: PackedInt32Array = columns.get(Vector3i(segment, side, col), PackedInt32Array())
	if row < 1 or row > ids.size() or ids[row - 1] == -1:
		return null
	return slots[ids[row - 1]]


## Ячейка под точкой мира (x, z) или null. Из нескольких дорог — та, чей край ближе.
func slot_at_point(p: Vector2) -> Slot:
	var best: Slot = null
	var best_e: float = INF
	for id: int in frames:
		var f: Frame = frames[id]
		var segment: RoadGraph.Segment = _graph.segments.get(id)
		if f.count == 0 or segment == null:
			continue
		if not _graph._bbox(segment).grow(f.half + DEPTH * ROW + 0.5).has_point(p):
			continue
		var near: Vector2 = _graph.nearest_on(segment, p)
		var e: float = near.y - f.half
		if e < 0.0 or e >= DEPTH * ROW or e >= best_e:
			continue
		var foot: Vector2 = RoadGraph.bezier(f.curve[0], f.curve[1], f.curve[2], near.x)
		var tangent: Vector2 = RoadGraph.bezier_tangent(f.curve[0], f.curve[1], f.curve[2], near.x).normalized()
		if absf((p - foot).dot(tangent)) > END_SLACK:
			continue
		var side: int = 1 if (p - foot).dot(Vector2(tangent.y, -tangent.x)) > 0.0 else -1
		var slot: Slot = slot_in(id, side, floori((_s_of(f.table, near.x) - f.offset) / ROW), floori(e / ROW) + 1)
		if slot != null:
			best = slot
			best_e = e
	return best


## Колонка и ряд полосы (segment, side) под точкой p; за краями полосы — ближайшие (протягивание зоны
## вдоль дороги: мышь может уйти с полосы).
func coords_at(segment: int, side: int, p: Vector2) -> Vector2i:
	var f: Frame = frames.get(segment)
	var road: RoadGraph.Segment = _graph.segments.get(segment) if _graph != null else null
	if f == null or road == null or f.count == 0:
		return Vector2i.ZERO
	var near: Vector2 = _graph.nearest_on(road, p)
	var foot: Vector2 = RoadGraph.bezier(f.curve[0], f.curve[1], f.curve[2], near.x)
	var tangent: Vector2 = RoadGraph.bezier_tangent(f.curve[0], f.curve[1], f.curve[2], near.x).normalized()
	var n: float = (p - foot).dot(Vector2(tangent.y, -tangent.x)) * side
	return Vector2i(clampi(floori((_s_of(f.table, near.x) - f.offset) / ROW), 0, f.count - 1),
			clampi(floori((n - f.half) / ROW) + 1, 1, DEPTH))


## Путь по дорогам от отрезка from до отрезка to через общие узлы (кратчайший по числу отрезков):
## [[отрезок, вперёд ли — от узла a к b], …]; пусто — не связаны ближе MAX_CHAIN отрезков.
## Дорога, проложенная в несколько щелчков, — цепочка отрезков: зона тянется вдоль неё через узлы.
func chain(from: int, to: int) -> Array[Array]:
	var none: Array[Array] = []
	if _graph == null or not _graph.segments.has(from) or not _graph.segments.has(to):
		return none
	if from == to:
		return [[from, true]]
	# Состояние обхода в ширину — (отрезок, 1 — идём от a к b).
	var queue: Array[Vector2i] = [Vector2i(from, 1), Vector2i(from, 0)]
	var depth: Dictionary[Vector2i, int] = {queue[0]: 0, queue[1]: 0}
	var prev: Dictionary[Vector2i, Vector2i] = {}
	var head: int = 0
	while head < queue.size():
		var state: Vector2i = queue[head]
		head += 1
		if depth[state] >= MAX_CHAIN:
			continue
		var segment: RoadGraph.Segment = _graph.segments[state.x]
		var exit: int = segment.b if state.y == 1 else segment.a
		for id: int in _graph.nodes[exit].segments:
			if id == state.x:
				continue
			var next := Vector2i(id, 1 if _graph.segments[id].a == exit else 0)
			if depth.has(next):
				continue
			depth[next] = depth[state] + 1
			prev[next] = state
			if id == to:
				var path: Array[Array] = []
				var at: Vector2i = next
				while true:
					path.push_front([at.x, at.y == 1])
					if not prev.has(at):
						break
					at = prev[at]
				return path
			queue.append(next)
	return none


## Ячейки, чья середина в прямоугольнике мира.
func slots_in(rect: Rect2) -> Array[Slot]:
	var result: Array[Slot] = []
	for slot: Slot in slots:
		if rect.has_point(slot.center):
			result.append(slot)
	return result


## Зоны ячеек для переноса на новые ячейки: [середина, зона] у каждой ячейки с зоной.
func zone_marks() -> Array[Array]:
	var marks: Array[Array] = []
	for slot: Slot in slots:
		if slot.zone != 0:
			marks.append([slot.center, slot.zone])
	return marks


## Точка и касательная (единичная, a → b) отрезка на расстоянии s по дуге от a.
func frame_at(segment: int, s: float) -> PackedVector2Array:
	var f: Frame = frames[segment]
	var t: float = RoadGeometry.t_at(f.table, s)
	var tangent: Vector2 = RoadGraph.bezier_tangent(f.curve[0], f.curve[1], f.curve[2], t)
	if tangent.length_squared() < 1e-10:
		tangent = f.curve[2] - f.curve[0]
	return PackedVector2Array([RoadGraph.bezier(f.curve[0], f.curve[1], f.curve[2], t), tangent.normalized()])


## Точка полосы: s по дуге от a, n от оси дороги в сторону side.
func point(segment: int, side: int, s: float, n: float) -> Vector2:
	var fr: PackedVector2Array = frame_at(segment, s)
	return fr[0] + Vector2(fr[1].y, -fr[1].x) * side * n


## Участок из колонок [col, col + width) и рядов 1..rows: углы, середина, фасад (к дороге), угол поворота
## дома (как Basis(UP, yaw): «вперёд» −Z смотрит на дорогу) и размеры вдоль дороги и вглубь, м.
func lot_shape(segment: int, side: int, col: int, width: int, rows: int) -> Dictionary:
	var f: Frame = frames[segment]
	var s0: float = f.offset + col * ROW
	var s1: float = s0 + width * ROW
	var n0: float = f.half
	var n1: float = n0 + rows * ROW
	var corners := PackedVector2Array([point(segment, side, s0, n0), point(segment, side, s1, n0),
			point(segment, side, s1, n1), point(segment, side, s0, n1)])
	var mid: PackedVector2Array = frame_at(segment, (s0 + s1) * 0.5)
	var front: Vector2 = -Vector2(mid[1].y, -mid[1].x) * side
	return {"corners": corners, "center": mid[0] - front * (n0 + n1) * 0.5, "front": front,
			"yaw": atan2(-front.x, -front.y), "size": Vector2(width * ROW, rows * ROW)}


## Дом width × depth м на колонках [col, col + columns) ряда у дороги: посередине колонок, фасадом к дороге;
## на внутренней стороне дуги прямой фасад задевал бы полотно — дом отодвигается, пока углы не сойдут.
## {center, yaw — как в lot_shape, corners — фасад слева, справа, зад справа, слева, setback — отступ, м,
## ok — дом в боковых краях колонок (вглубь веер внутренней стороны сужается) и отступ не больше MAX_SETBACK}.
func house_pose(segment: int, side: int, col: int, columns: int, width: float, depth: float) -> Dictionary:
	var f: Frame = frames[segment]
	var mid: PackedVector2Array = frame_at(segment, f.offset + (col + columns * 0.5) * ROW)
	var along: Vector2 = mid[1]
	var outward: Vector2 = Vector2(along.y, -along.x) * side
	var road: RoadGraph.Segment = _graph.segments[segment]
	var n: float = f.half
	var corners := PackedVector2Array()
	for attempt: int in 4:
		var base: Vector2 = mid[0] + outward * n
		corners = PackedVector2Array([base - along * width * 0.5, base + along * width * 0.5,
				base + along * width * 0.5 + outward * depth, base - along * width * 0.5 + outward * depth])
		var into: float = 0.0
		for k: int in 5:
			into = maxf(into, f.half - _graph.nearest_on(road, corners[0].lerp(corners[1], k * 0.25)).y)
		if into <= FIT_SLACK * 0.5:
			break
		n += into + 0.01
	# Боковые края колонок — перпендикуляры к дороге: угол дома между ними, пока его место по дуге
	# (s ближайшей точки дороги) — в пределах колонок.
	var ok: bool = n - f.half <= MAX_SETBACK
	var s0: float = f.offset + col * ROW
	for p: Vector2 in corners:
		var s: float = _s_of(f.table, _graph.nearest_on(road, p).x)
		ok = ok and s >= s0 - FIT_SLACK and s <= s0 + columns * ROW + FIT_SLACK
	var front: Vector2 = -outward
	return {"center": mid[0] + outward * (n + depth * 0.5), "yaw": atan2(-front.x, -front.y), "corners": corners,
			"setback": n - f.half, "ok": ok}


## Кандидаты в полосы: клетка суши → [расстояние от края полотна, отрезок, сторона, s по дуге].
## Ближайший свободный отрезок; к нему по прямой не мешают вода и чужие дороги.
func candidates(grid: CityGrid) -> Dictionary[Vector2i, Array]:
	var result: Dictionary[Vector2i, Array] = {}
	var graph: RoadGraph = grid.roads
	_graph = graph
	frames.clear()
	for segment: RoadGraph.Segment in graph.segments.values():
		if not zonable(graph, segment):
			continue
		var f := Frame.new()
		f.curve = graph.curve(segment)
		f.table = RoadGeometry.arc_table(f.curve[0], f.curve[1], f.curve[2])
		f.half = RoadTypes.HALF_WIDTH.get(segment.type, 1.0)
		frames[segment.id] = f
		var reach: float = f.half + DEPTH * ROW + 1.0
		var lo: Vector2 = f.curve[0].min(f.curve[1]).min(f.curve[2]) - Vector2.ONE * reach
		var hi: Vector2 = f.curve[0].max(f.curve[1]).max(f.curve[2]) + Vector2.ONE * reach
		var from: Vector2i = grid.clamp_to_bounds(RoadGraph.cell_of(lo))
		var to: Vector2i = grid.clamp_to_bounds(RoadGraph.cell_of(hi))
		for y: int in range(from.y, to.y + 1):
			for x: int in range(from.x, to.x + 1):
				var cell := Vector2i(x, y)
				var i: int = grid.index_of(cell)
				if grid.tile_type[i] == CityGrid.Tile.ROAD or grid.water[i] == 1:
					continue
				var p: Vector2 = RoadGraph.cell_center(cell)
				var near: Vector2 = graph.nearest_on(segment, p)
				var e: float = near.y - f.half
				if e < 0.0 or e >= DEPTH * ROW:
					continue
				var foot: Vector2 = RoadGraph.bezier(f.curve[0], f.curve[1], f.curve[2], near.x)
				var tangent: Vector2 = RoadGraph.bezier_tangent(f.curve[0], f.curve[1], f.curve[2], near.x).normalized()
				if absf((p - foot).dot(tangent)) > END_SLACK:
					continue
				if result.has(cell) and result[cell][0] <= e:
					continue
				if _blocked(grid, segment.id, p, foot):
					continue
				var side: int = 1 if (p - foot).dot(Vector2(tangent.y, -tangent.x)) > 0.0 else -1
				result[cell] = [e, segment.id, side, _s_of(f.table, near.x)]
	return result


## Ячейки по клеткам owners (клетка → [e, отрезок, сторона, s]), отданным полосам свободных дорог.
## Ячейка есть, если не сжата и не заходит на воду, чужие дороги, чужие полосы и полосы из клеток.
func build(grid: CityGrid, owners: Dictionary[Vector2i, Array]) -> void:
	slots.clear()
	slot_of_cell.clear()
	columns.clear()
	occupied.clear()
	var graph: RoadGraph = grid.roads
	for id: int in frames:
		var f: Frame = frames[id]
		var segment: RoadGraph.Segment = graph.segments[id]
		var length: float = f.table[f.table.size() - 1]
		var lo: float = _margin(graph, grid, segment.a, id)
		var hi: float = length - _margin(graph, grid, segment.b, id)
		if hi - lo < ROW:
			continue
		f.count = floori((hi - lo) / ROW)
		f.offset = lo + ((hi - lo) - f.count * ROW) * 0.5
		for side: int in [1, -1]:
			for col: int in f.count:
				var ids := PackedInt32Array([-1, -1, -1, -1])
				for row: int in range(1, DEPTH + 1):
					var slot: Slot = _make_slot(grid, owners, id, side, col, row)
					if slot == null:
						break
					slot.id = slots.size()
					slots.append(slot)
					ids[row - 1] = slot.id
				columns[Vector3i(id, side, col)] = ids
	for cell: Vector2i in owners:
		var owner: Array = owners[cell]
		var f: Frame = frames[owner[1]]
		if f.count == 0:
			continue
		var col: int = floori((owner[3] - f.offset) / ROW)
		var row: int = floori(owner[0] / ROW) + 1
		var slot: Slot = slot_in(owner[1], owner[2], col, row)
		if slot != null:
			slot.cells.append(cell)
			slot_of_cell[cell] = slot.id


func _make_slot(grid: CityGrid, owners: Dictionary[Vector2i, Array], segment: int, side: int, col: int,
		row: int) -> Slot:
	var f: Frame = frames[segment]
	var s0: float = f.offset + col * ROW
	var s1: float = s0 + ROW
	var n0: float = f.half + (row - 1) * ROW
	var n1: float = n0 + ROW
	var corners := PackedVector2Array([point(segment, side, s0, n0), point(segment, side, s1, n0),
			point(segment, side, s1, n1), point(segment, side, s0, n1)])
	# Сжатая (внутренняя сторона крутой дуги) или вывернутая ячейка — нет.
	var area: float = 0.0
	for i: int in 4:
		area += corners[i].cross(corners[(i + 1) % 4])
	if absf(area) * 0.5 < MIN_AREA or signf(area) != -side:
		return null
	var center: Vector2 = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	for i: int in 5:
		var p: Vector2 = center if i == 4 else corners[i].lerp(center, 0.08)
		if not _clear(grid, owners, segment, side, p):
			return null
	var slot := Slot.new()
	slot.segment = segment
	slot.side = side
	slot.col = col
	slot.row = row
	slot.corners = corners
	slot.center = center
	var best: float = INF
	for cell: Vector2i in grid.roads.segments[segment].cells:
		var d: float = RoadGraph.cell_center(cell).distance_squared_to(center)
		if d < best:
			best = d
			slot.road = cell
	var mid: PackedVector2Array = frame_at(segment, (s0 + s1) * 0.5)
	slot.front = -Vector2(mid[1].y, -mid[1].x) * side
	return slot


## Точка ячейки свободна: на карте, не на воде, не на полотне чужой дороги, клетка — своей полосы
## (или ничья), не полоса из клеток.
func _clear(grid: CityGrid, owners: Dictionary[Vector2i, Array], segment: int, side: int, p: Vector2) -> bool:
	var cell: Vector2i = RoadGraph.cell_of(p)
	if not grid.is_in_bounds(cell):
		return false
	var i: int = grid.index_of(cell)
	if grid.water[i] == 1:
		return false
	var graph: RoadGraph = grid.roads
	for other: RoadGraph.Segment in graph.segments.values():
		if other.id == segment:
			continue
		var half: float = RoadTypes.HALF_WIDTH.get(other.type, 1.0)
		if graph._bbox(other).grow(half).has_point(p) and graph.nearest_on(other, p).y < half:
			return false
	if grid.tile_type[i] == CityGrid.Tile.ROAD:
		return graph.owners_of(cell).has(segment)
	if owners.has(cell):
		return owners[cell][1] == segment and owners[cell][2] == side
	return grid.strip_dir[i] == CityGrid.NO_STRIP


## По прямой от клетки p к дороге foot — вода или чужая дорога.
func _blocked(grid: CityGrid, segment: int, p: Vector2, foot: Vector2) -> bool:
	var steps: int = maxi(1, ceili(p.distance_to(foot) / 0.7))
	for k: int in range(1, steps):
		var cell: Vector2i = RoadGraph.cell_of(p.lerp(foot, float(k) / steps))
		if not grid.is_in_bounds(cell):
			return true
		var i: int = grid.index_of(cell)
		if grid.water[i] == 1:
			return true
		if grid.tile_type[i] == CityGrid.Tile.ROAD and not grid.roads.owners_of(cell).has(segment):
			return true
	return false


## Отступ ячеек от узла node на отрезке segment.
func _margin(graph: RoadGraph, grid: CityGrid, node: int, segment: int) -> float:
	var degree: int = graph.nodes[node].segments.size()
	if degree <= 1:
		var p: Vector2 = graph.nodes[node].pos
		var edge: float = CityGrid.CELL_SIZE * 0.6
		var size: float = grid.world_size()
		# У края карты (въезд) дорога уходит за карту — круга нет.
		if p.x < edge or p.y < edge or p.x > size - edge or p.y > size - edge:
			return 0.0
		return DEAD_END_MARGIN
	return RoadRoute.trim(graph, grid, node, segment) + JUNCTION_MARGIN


static func _s_of(table: PackedFloat32Array, t: float) -> float:
	var count: int = table.size() - 1
	var x: float = clampf(t, 0.0, 1.0) * count
	var i: int = mini(int(x), count - 1)
	return lerpf(table[i], table[i + 1], x - i)
