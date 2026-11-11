class_name RoadGraph
extends RefCounted
## Граф дорог (как в Cities: Skylines, этап C1 — 2026-11-09): узлы и отрезки-кривые (квадратичные
## Безье) на плоскости земли. Координаты — метры мира: Vector2(x, z). Дорогу можно вести под любым
## углом и дугой; пересечения сами становятся перекрёстками.
##
## Сетка CityGrid — «растр» графа: клетки под полотном — дорожные, на них по-прежнему держатся зоны,
## рост, трафик и сохранение. Дороги игры меняет граф (plan → build, remove_segments, retype) и сам
## ставит и убирает клетки. Клетки, поставленные мимо графа (старые сохранения, въезд трассы, снос
## клеток, тесты), граф подхватывает в sync — прямыми отрезками между центрами клеток; если клетку
## отрезка снесли или сменили ей тип мимо графа — отрезок разрезается там, кривая остальных кусков та же.

const CELL: float = CityGrid.CELL_SIZE
## Короче — не строим, м.
const MIN_LENGTH: float = 1.5
## Самый острый угол между дорогами в узле и на пересечении, градусы.
const MIN_ANGLE: float = 30.0
## Самый крутой поворот кривой: угол между касательными в начале и в конце, градусы.
const MAX_TURN: float = 150.0
## Шаг выборки кривой: растр и ломаная для пересечений, м.
const RASTER_STEP: float = 0.3
const POLY_STEP: float = 0.5
## Пересечение ближе этого к узлу — через узел, м.
const NODE_MERGE: float = 1.2
## Новая дорога, проходящая так близко от узла, проходит через него, м.
const NODE_PASS: float = 0.8
## Возле узлов-соединений (клеток по Чебышёву) растр новой дороги может касаться чужих клеток.
const JOIN_RADIUS: int = 3
## «Толстый» растр: соседняя клетка тоже дорожная, если дом на ней (полуширина ~0.8 м) залез бы
## на полотно глубже CLEARANCE. На прямой по центрам клеток соседи не попадают, на диагонали — да.
const HOUSE_HALF: float = 0.8
const CLEARANCE: float = 0.15

enum Claim { SET, EXISTING }


class RoadNode extends RefCounted:
	var id: int = 0
	var pos := Vector2.ZERO
	var segments: Array[int] = []

	func _init(p_id: int, p_pos: Vector2) -> void:
		id = p_id
		pos = p_pos


class Segment extends RefCounted:
	var id: int = 0
	var a: int = 0
	var b: int = 0
	## Управляющая точка кривой; у прямой — середина.
	var ctrl := Vector2.ZERO
	var type: int = RoadTypes.Type.STREET
	## Клетки растра и t ближайшей к центру клетки точки кривой (по тем же номерам).
	var cells: Array[Vector2i] = []
	var cell_t := PackedFloat32Array()
	## Ломаная кривой для пересечений и привязки (лениво).
	var poly := PackedVector2Array()


## Точка начала или конца новой дороги: узел, точка на отрезке или свободное место.
class RoadPoint extends RefCounted:
	var pos := Vector2.ZERO
	var node: int = -1
	var segment: int = -1
	var t: float = 0.0

	func _init(p_pos: Vector2 = Vector2.ZERO) -> void:
		pos = p_pos


## План постройки одной кривой: проверка, куски между перекрёстками, новые клетки, цена.
class Plan extends RefCounted:
	var ok: bool = false
	var reason: String = ""
	var type: int = RoadTypes.Type.STREET
	var from_point: RoadPoint
	var to_point: RoadPoint
	var p0 := Vector2.ZERO
	var c := Vector2.ZERO
	var p2 := Vector2.ZERO
	var length: float = 0.0
	## Пересечения по ходу кривой: {"t", "pos", "node", "segment"}.
	var crossings: Array[Dictionary] = []
	## Куски между перекрёстками: [начало, управляющая, конец].
	var pieces: Array[PackedVector2Array] = []
	## Клетки, которые станут дорогой (сейчас не дорога).
	var cells: Array[Vector2i] = []
	## Дома зон на пути — снесутся (как в Cities: Skylines).
	var demolish: Array[int] = []
	var cost: int = 0


var nodes: Dictionary[int, RoadNode] = {}
var segments: Dictionary[int, Segment] = {}
var next_node_id: int = 0
var next_segment_id: int = 0
## Растёт при каждом изменении графа — по нему перерисовывается полотно.
var version: int = 0

## Клетка → номера отрезков, чьи растры её занимают.
var _owners: Dictionary[Vector2i, Array] = {}
## Одиночные клетки дороги без соседей: клетка → узел без отрезков.
var _lone: Dictionary[Vector2i, int] = {}
## Точка дороги в клетке (ближайшая к центру точка кривой, в клетке узла — сам узел) — для машинок.
var _anchors: Dictionary[Vector2i, Vector2] = {}
## Клетки узлов с тремя и более дорогами — перекрёстки со светофорами.
var _junctions: Dictionary[Vector2i, bool] = {}
var _synced_roads_version: int = -1


# --- Кривые ---

static func bezier(p0: Vector2, c: Vector2, p2: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return p0 * (u * u) + c * (2.0 * u * t) + p2 * (t * t)


static func bezier_tangent(p0: Vector2, c: Vector2, p2: Vector2, t: float) -> Vector2:
	return (c - p0) * (2.0 * (1.0 - t)) + (p2 - c) * (2.0 * t)


## Управляющая точка куска кривой от t0 до t1 (полярная форма квадратичной Безье).
static func sub_control(p0: Vector2, c: Vector2, p2: Vector2, t0: float, t1: float) -> Vector2:
	return p0 * ((1.0 - t0) * (1.0 - t1)) + c * ((1.0 - t0) * t1 + t0 * (1.0 - t1)) + p2 * (t0 * t1)


static func curve_length(p0: Vector2, c: Vector2, p2: Vector2) -> float:
	var length: float = 0.0
	var prev: Vector2 = p0
	for i: int in range(1, 17):
		var p: Vector2 = bezier(p0, c, p2, i / 16.0)
		length += prev.distance_to(p)
		prev = p
	return length


static func polyline(p0: Vector2, c: Vector2, p2: Vector2, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in count + 1:
		points.append(bezier(p0, c, p2, float(i) / count))
	return points


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


static func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## Клетки под кривой: через которые она идёт, и соседние, куда полотно заходит так, что дом на
## клетке залез бы на дорогу. Клетка → t ближайшей к её центру точки кривой.
static func rasterize(p0: Vector2, c: Vector2, p2: Vector2, type: int) -> Dictionary:
	var steps: int = maxi(2, ceili(curve_length(p0, c, p2) / RASTER_STEP))
	var best: Dictionary = {}
	for i: int in steps + 1:
		var t: float = float(i) / steps
		var p: Vector2 = bezier(p0, c, p2, t)
		var home: Vector2i = cell_of(p)
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var cell := Vector2i(home.x + dx, home.y + dy)
				var d: float = p.distance_to(cell_center(cell))
				var inside: float = 1.0 if dx == 0 and dy == 0 else 0.0
				if not best.has(cell):
					best[cell] = Vector3(d, t, inside)
					continue
				var v: Vector3 = best[cell]
				if d < v.x:
					v.x = d
					v.y = t
				v.z = maxf(v.z, inside)
				best[cell] = v
	var half: float = RoadTypes.HALF_WIDTH.get(type, 1.0)
	var result: Dictionary = {}
	for cell: Vector2i in best:
		var v: Vector3 = best[cell]
		var keep: bool = v.z > 0.5
		if not keep:
			var tangent: Vector2 = bezier_tangent(p0, c, p2, v.y).normalized()
			keep = v.x < half - CLEARANCE + HOUSE_HALF * (absf(tangent.x) + absf(tangent.y))
		if keep:
			result[cell] = v.y
	return result


## Концы и управляющая точка отрезка.
func curve(segment: Segment) -> PackedVector2Array:
	return PackedVector2Array([nodes[segment.a].pos, segment.ctrl, nodes[segment.b].pos])


func segment_length(segment: Segment) -> float:
	var points: PackedVector2Array = curve(segment)
	return curve_length(points[0], points[1], points[2])


func _poly(segment: Segment) -> PackedVector2Array:
	if segment.poly.is_empty():
		var points: PackedVector2Array = curve(segment)
		var count: int = maxi(2, ceili(curve_length(points[0], points[1], points[2]) / POLY_STEP))
		segment.poly = polyline(points[0], points[1], points[2], count)
	return segment.poly


## Ближайшая к pos точка отрезка: Vector2(t, расстояние).
func nearest_on(segment: Segment, pos: Vector2) -> Vector2:
	var poly: PackedVector2Array = _poly(segment)
	var count: int = poly.size() - 1
	var best_i: int = 0
	var best_d: float = INF
	for i: int in poly.size():
		var d: float = poly[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	var points: PackedVector2Array = curve(segment)
	var lo: float = maxf(0.0, (best_i - 1.0) / count)
	var hi: float = minf(1.0, (best_i + 1.0) / count)
	for _k: int in 24:
		var m1: float = lerpf(lo, hi, 1.0 / 3.0)
		var m2: float = lerpf(lo, hi, 2.0 / 3.0)
		if bezier(points[0], points[1], points[2], m1).distance_squared_to(pos) \
				< bezier(points[0], points[1], points[2], m2).distance_squared_to(pos):
			hi = m2
		else:
			lo = m1
	var t: float = (lo + hi) * 0.5
	return Vector2(t, bezier(points[0], points[1], points[2], t).distance_to(pos))


## Отрезок, на чьё полотно попала точка (из нескольких — чья ось ближе), или −1.
func segment_at(pos: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	for segment: Segment in segments.values():
		var half: float = RoadTypes.HALF_WIDTH.get(segment.type, 1.0)
		if not _bbox(segment).grow(half).has_point(pos):
			continue
		var d: float = nearest_on(segment, pos).y
		if d < half and d < best_d:
			best_d = d
			best = segment.id
	return best


## Полотно отрезка четырёхугольниками вдоль кривой (углы в мире x, z) — для подсветки.
func ribbon_quads(id: int, step: float = 1.0) -> Array[PackedVector2Array]:
	var quads: Array[PackedVector2Array] = []
	var segment: Segment = segments.get(id)
	if segment == null:
		return quads
	var points: PackedVector2Array = curve(segment)
	var half: float = RoadTypes.HALF_WIDTH.get(segment.type, 1.0)
	var count: int = maxi(1, ceili(curve_length(points[0], points[1], points[2]) / step))
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	for i: int in count + 1:
		var t: float = float(i) / count
		var p: Vector2 = bezier(points[0], points[1], points[2], t)
		var tangent: Vector2 = bezier_tangent(points[0], points[1], points[2], t)
		if tangent.length_squared() < 1e-10:
			tangent = points[2] - points[0]
		var across: Vector2 = Vector2(tangent.y, -tangent.x).normalized() * half
		if i > 0:
			quads.append(PackedVector2Array([left, p + across, p - across, right]))
		left = p + across
		right = p - across
	return quads


## Лежит ли точка на полотне дороги (или не дальше margin от его края).
func on_ribbon(pos: Vector2, margin: float = 0.0) -> bool:
	for segment: Segment in segments.values():
		var half: float = RoadTypes.HALF_WIDTH.get(segment.type, 1.0) + margin
		if _bbox(segment).grow(half).has_point(pos) and nearest_on(segment, pos).y < half:
			return true
	return false


## Направление отрезка из узла node (касательная, единичная).
func direction_from(segment: Segment, node: int) -> Vector2:
	var points: PackedVector2Array = curve(segment)
	if segment.a == node:
		var d: Vector2 = bezier_tangent(points[0], points[1], points[2], 0.0)
		return (d if d.length_squared() > 1e-8 else points[2] - points[0]).normalized()
	var back: Vector2 = -bezier_tangent(points[0], points[1], points[2], 1.0)
	return (back if back.length_squared() > 1e-8 else points[0] - points[2]).normalized()


## Отрезок у точки не дальше radius (−1 — нет).
func segment_near(pos: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius
	for segment: Segment in segments.values():
		if not _bbox(segment).grow(radius).has_point(pos):
			continue
		var d: float = nearest_on(segment, pos).y
		if d < best_d:
			best_d = d
			best = segment.id
	return best


## Узел у точки не дальше radius (−1 — нет).
func node_near(pos: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius
	for node: RoadNode in nodes.values():
		var d: float = node.pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = node.id
	return best


func _bbox(segment: Segment) -> Rect2:
	var points: PackedVector2Array = curve(segment)
	var rect := Rect2(points[0], Vector2.ZERO)
	rect = rect.expand(points[1])
	return rect.expand(points[2])


## Отрезок у въезда трассы: снести и перестроить нельзя.
func is_locked(grid: CityGrid, id: int) -> bool:
	if not segments.has(id):
		return false
	for cell: Vector2i in segments[id].cells:
		if grid.highway_cells.has(cell):
			return true
	return false


# --- Клетки ---

func _owned(cell: Vector2i) -> bool:
	return _owners.has(cell) or _lone.has(cell)


## Отрезки, чьи растры занимают клетку.
func owners_of(cell: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for id: int in _owners.get(cell, []):
		result.append(id)
	return result


## Точка дороги в клетке (мир, высота 0) — по ней едут машинки; не дорога — центр клетки.
func anchor(cell: Vector2i) -> Vector2:
	return _anchors.get(cell, cell_center(cell))


func has_anchor(cell: Vector2i) -> bool:
	return _anchors.has(cell)


## Перекрёсток со светофором: в клетке узел с тремя и более дорогами, не шоссе.
func is_junction(grid: CityGrid, cell: Vector2i) -> bool:
	sync(grid)
	return _junctions.has(cell) and grid.get_road_type(cell) != RoadTypes.Type.HIGHWAY


# --- Изменения ---

func _add_node(pos: Vector2) -> int:
	var node := RoadNode.new(next_node_id, pos)
	nodes[node.id] = node
	next_node_id += 1
	return node.id


## Новый отрезок a–b. claim: SET — ставит недостающие клетки (и повышает тип на пересечении),
## EXISTING — берёт только уже дорожные (подхват, деление, загрузка). Изменённые клетки — в changed.
func _add_segment(grid: CityGrid, a: int, b: int, ctrl: Vector2, type: int, claim: Claim,
		changed: Array[Vector2i] = [], id: int = -1) -> int:
	var segment := Segment.new()
	segment.id = id if id >= 0 else next_segment_id
	next_segment_id = maxi(next_segment_id, segment.id + 1)
	segment.a = a
	segment.b = b
	segment.ctrl = ctrl
	segment.type = type
	var raster: Dictionary = rasterize(nodes[a].pos, ctrl, nodes[b].pos, type)
	for cell: Vector2i in raster:
		if not grid.is_in_bounds(cell):
			continue
		if not grid.is_road(cell):
			if claim != Claim.SET or not grid.set_road(cell, type):
				continue
			changed.append(cell)
		elif claim == Claim.SET and grid.get_road_type(cell) < type and not grid.highway_cells.has(cell):
			grid.set_road(cell, type)
			changed.append(cell)
		segment.cells.append(cell)
		segment.cell_t.append(raster[cell])
		if not _owners.has(cell):
			_owners[cell] = []
		_owners[cell].append(segment.id)
	segments[segment.id] = segment
	for end: int in [a, b]:
		nodes[end].segments.append(segment.id)
		_lone.erase(cell_of(nodes[end].pos))
	return segment.id


## Убирает отрезок из графа, клетки не трогает.
func _detach(segment: Segment) -> void:
	for cell: Vector2i in segment.cells:
		if _owners.has(cell):
			_owners[cell].erase(segment.id)
			if _owners[cell].is_empty():
				_owners.erase(cell)
	for end: int in [segment.a, segment.b]:
		if nodes.has(end):
			nodes[end].segments.erase(segment.id)
	segments.erase(segment.id)


## Тип клетки — самый «большой» из типов её отрезков (перекрёсток улицы и проспекта — проспект).
func _retype_cell(grid: CityGrid, cell: Vector2i) -> bool:
	var top: int = 0
	for id: int in _owners.get(cell, []):
		top = maxi(top, segments[id].type)
	if top == 0 or top == grid.get_road_type(cell) or grid.highway_cells.has(cell):
		return false
	return grid.set_road(cell, top)


## Делит отрезок в точке t: новый узел и два отрезка по той же кривой.
func split(grid: CityGrid, id: int, t: float) -> int:
	var segment: Segment = segments[id]
	var points: PackedVector2Array = curve(segment)
	var node: int = _add_node(bezier(points[0], points[1], points[2], t))
	var old_cells: Array[Vector2i] = segment.cells.duplicate()
	_detach(segment)
	_add_segment(grid, segment.a, node, sub_control(points[0], points[1], points[2], 0.0, t), segment.type, Claim.EXISTING)
	_add_segment(grid, node, segment.b, sub_control(points[0], points[1], points[2], t, 1.0), segment.type, Claim.EXISTING)
	for cell: Vector2i in old_cells:
		if not _owned(cell):
			grid.remove_road(cell)
	return node


## Узел в точке: уже есть рядом — он; на дороге — дорога делится; иначе новый.
func _node_at(grid: CityGrid, pos: Vector2) -> int:
	var near: int = node_near(pos, 0.3)
	if near != -1:
		return near
	var on: int = segment_near(pos, 0.3)
	if on != -1:
		var hit: Vector2 = nearest_on(segments[on], pos)
		var points: PackedVector2Array = curve(segments[on])
		var length: float = curve_length(points[0], points[1], points[2])
		# У самого конца отрезка — его узел.
		if hit.x * length < 0.3:
			return segments[on].a
		if (1.0 - hit.x) * length < 0.3:
			return segments[on].b
		return split(grid, on, hit.x)
	return _add_node(pos)


func _finish(grid: CityGrid) -> void:
	_synced_roads_version = grid.roads_version
	version += 1
	_rebuild_caches()


func _rebuild_caches() -> void:
	_anchors.clear()
	_junctions.clear()
	for segment: Segment in segments.values():
		var points: PackedVector2Array = curve(segment)
		for i: int in segment.cells.size():
			_anchors[segment.cells[i]] = bezier(points[0], points[1], points[2], segment.cell_t[i])
	for node: RoadNode in nodes.values():
		var cell: Vector2i = cell_of(node.pos)
		if node.segments.is_empty() and not _lone.has(cell):
			continue
		_anchors[cell] = node.pos
		if node.segments.size() >= 3:
			_junctions[cell] = true


# --- Постройка ---

## Проверяет кривую from → to (ctrl — управляющая точка; null — прямая) и считает цену.
## Ничего не меняет. plan.ok — можно строить; иначе plan.reason — почему нельзя.
func plan(grid: CityGrid, from: RoadPoint, to: RoadPoint, ctrl: Variant, type: int, money: int) -> Plan:
	sync(grid)
	var result := Plan.new()
	result.type = type
	result.from_point = from
	result.to_point = to
	result.p0 = from.pos
	result.p2 = to.pos
	result.c = ctrl if ctrl is Vector2 else (from.pos + to.pos) * 0.5
	result.length = curve_length(result.p0, result.c, result.p2)
	if result.length < MIN_LENGTH or (from.node != -1 and from.node == to.node):
		return _reject(result, "Слишком коротко")
	var start_dir: Vector2 = bezier_tangent(result.p0, result.c, result.p2, 0.0).normalized()
	var end_dir: Vector2 = bezier_tangent(result.p0, result.c, result.p2, 1.0).normalized()
	if rad_to_deg(start_dir.angle_to(end_dir)) > MAX_TURN or rad_to_deg(start_dir.angle_to(end_dir)) < -MAX_TURN:
		return _reject(result, "Слишком крутой поворот")
	var count: int = maxi(4, ceili(result.length / POLY_STEP))
	var poly: PackedVector2Array = polyline(result.p0, result.c, result.p2, count)
	var world: float = grid.size * CELL
	for p: Vector2 in poly:
		if p.x < 0.0 or p.y < 0.0 or p.x >= world or p.y >= world:
			return _reject(result, "За краем карты")

	result.crossings = _crossings(poly, from, to)
	for crossing: Dictionary in result.crossings:
		if crossing.node != -1 and (crossing.node == from.node or crossing.node == to.node):
			return _reject(result, "Дорога пересекает сама себя")
	# Углы: в начале, в конце и на каждом пересечении — не острее MIN_ANGLE.
	if not _angle_ok(from, start_dir) or not _angle_ok(to, -end_dir):
		return _reject(result, "Слишком острый угол")
	for crossing: Dictionary in result.crossings:
		var dir: Vector2 = bezier_tangent(result.p0, result.c, result.p2, crossing.t).normalized()
		var point := RoadPoint.new(crossing.pos)
		point.node = crossing.node
		point.segment = crossing.segment
		if not _angle_ok(point, dir) or not _angle_ok(point, -dir):
			return _reject(result, "Слишком острый угол пересечения")

	# Куски между перекрёстками.
	var cuts: Array[float] = [0.0]
	var ends: Array[Vector2] = [result.p0]
	for crossing: Dictionary in result.crossings:
		cuts.append(crossing.t)
		ends.append(crossing.pos)
	cuts.append(1.0)
	ends.append(result.p2)
	var raster: Dictionary = {}
	for k: int in cuts.size() - 1:
		var piece := PackedVector2Array([ends[k],
				sub_control(result.p0, result.c, result.p2, cuts[k], cuts[k + 1]), ends[k + 1]])
		if curve_length(piece[0], piece[1], piece[2]) < MIN_LENGTH:
			return _reject(result, "Слишком близко к перекрёстку")
		result.pieces.append(piece)
		raster.merge(rasterize(piece[0], piece[1], piece[2], type))
	if from.node != -1 and to.node != -1 and result.crossings.is_empty():
		for id: int in nodes[from.node].segments:
			var other: Segment = segments[id]
			if other.a == to.node or other.b == to.node:
				return _reject(result, "Дорога уже есть")

	# Новая дорога не должна лечь на чужую или вплотную к ней. Касаться можно только дорог,
	# к которым она примыкает или которые пересекает, и только возле этих мест.
	var joins: Array[Dictionary] = [_join(cell_of(result.p0), from.node != -1 or from.segment != -1, from.node),
			_join(cell_of(result.p2), to.node != -1 or to.segment != -1, to.node)]
	for crossing: Dictionary in result.crossings:
		joins.append(_join(cell_of(crossing.pos), true, crossing.node))
	for cell: Vector2i in raster:
		if not grid.is_in_bounds(cell):
			continue
		if _owned(cell) and not _touch_ok(cell, cell, joins):
			return _reject(result, "Ложится на другую дорогу")
		for offset: Vector2i in CityGrid.NEIGHBORS:
			var next: Vector2i = cell + offset
			if _owned(next) and not raster.has(next) and not _touch_ok(cell, next, joins):
				return _reject(result, "Слишком близко к другой дороге")

	# Новые клетки, цена, дома на пути.
	var demolish: Dictionary[int, bool] = {}
	for cell: Vector2i in raster:
		if not grid.is_in_bounds(cell) or grid.is_road(cell):
			continue
		var building_id: int = grid.building_at[grid.index_of(cell)]
		if building_id != -1:
			var building: BuildingInstance = grid.buildings[building_id]
			var data: BuildingData = BuildingCatalog.get_type(building.type_id)
			if data == null or data.zone == CityGrid.Zone.NONE:
				return _reject(result, "Мешает здание")
			demolish[building_id] = true
		result.cells.append(cell)
		result.cost += cell_cost(grid, cell, type)
	# Дом под углом дороги (этап C3) полотно может задеть и мимо его клеток.
	var ribbon: Array[PackedVector2Array] = Geometry2D.offset_polyline(
			polyline(result.p0, result.c, result.p2, maxi(4, ceili(result.length))), RoadTypes.HALF_WIDTH.get(type, 1.0))
	var reach: Rect2 = Rect2(result.p0, Vector2.ZERO).expand(result.c).expand(result.p2).grow(
			RoadTypes.HALF_WIDTH.get(type, 1.0) + CityGrid.CELL_SIZE * 5.0)
	for building: BuildingInstance in grid.buildings.values():
		if not building.is_free() or demolish.has(building.id) or not reach.has_point(building.center):
			continue
		var footprint: PackedVector2Array = grid.free_footprint(building)
		for part: PackedVector2Array in ribbon:
			if not Geometry2D.intersect_polygons(part, footprint).is_empty():
				demolish[building.id] = true
				break
	result.demolish.assign(demolish.keys())
	if result.cost > money:
		return _reject(result, "Не хватает денег")
	result.ok = true
	return result


## Цена клетки дороги: по воде — мост (дороже на разницу мост − улица).
static func cell_cost(grid: CityGrid, cell: Vector2i, type: int) -> int:
	var cost: int = RoadTypes.BUILD_COST.get(type, 0)
	if grid.is_water(cell):
		cost += RoadTypes.BRIDGE_COST - RoadTypes.BUILD_COST[RoadTypes.Type.STREET]
	return cost


func _reject(result: Plan, reason: String) -> Plan:
	result.ok = false
	result.reason = reason
	return result


## Место соединения новой дороги: клетка и дороги, которых там можно касаться (отрезки клеток
## вокруг и узла). У свободного конца касаться нечего.
func _join(cell: Vector2i, snapped: bool, node: int) -> Dictionary:
	var allowed: Dictionary[int, bool] = {}
	if snapped:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				for id: int in _owners.get(cell + Vector2i(dx, dy), []):
					allowed[id] = true
		if node != -1 and nodes.has(node):
			for id: int in nodes[node].segments:
				allowed[id] = true
	return {"cell": cell, "allowed": allowed, "lone": snapped}


## Можно ли клетке новой дороги cell касаться дорожной клетки touched: все её отрезки — из
## разрешённых у соединения не дальше JOIN_RADIUS.
func _touch_ok(cell: Vector2i, touched: Vector2i, joins: Array[Dictionary]) -> bool:
	var near: Array[Dictionary] = []
	for join: Dictionary in joins:
		var at: Vector2i = join.cell
		if maxi(absi(cell.x - at.x), absi(cell.y - at.y)) <= JOIN_RADIUS:
			near.append(join)
	if near.is_empty():
		return false
	if _lone.has(touched):
		for join: Dictionary in near:
			if join.lone:
				return true
		return false
	for id: int in _owners.get(touched, []):
		var ok: bool = false
		for join: Dictionary in near:
			if join.allowed.has(id):
				ok = true
				break
		if not ok:
			return false
	return true


## Угол между новой дорогой (dir — из точки) и дорогами в точке — не острее MIN_ANGLE.
func _angle_ok(point: RoadPoint, dir: Vector2) -> bool:
	var limit: float = cos(deg_to_rad(MIN_ANGLE))
	if point.node != -1 and nodes.has(point.node):
		for id: int in nodes[point.node].segments:
			if direction_from(segments[id], point.node).dot(dir) > limit:
				return false
	elif point.segment != -1 and segments.has(point.segment):
		var segment: Segment = segments[point.segment]
		var points: PackedVector2Array = curve(segment)
		var t: float = nearest_on(segment, point.pos).x
		var along: Vector2 = bezier_tangent(points[0], points[1], points[2], t).normalized()
		if absf(along.dot(dir)) > limit:
			return false
	return true


## Пересечения новой ломаной с дорогами и проходы через узлы, по ходу кривой.
## Пересечения у начала и конца, привязанных к дороге, не считаются — это само соединение.
func _crossings(poly: PackedVector2Array, from: RoadPoint, to: RoadPoint) -> Array[Dictionary]:
	var count: int = poly.size() - 1
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		bounds = bounds.expand(p)
	bounds = bounds.grow(NODE_MERGE)
	var found: Array[Dictionary] = []
	for segment: Segment in segments.values():
		if not _bbox(segment).intersects(bounds):
			continue
		var other: PackedVector2Array = _poly(segment)
		for i: int in count:
			for j: int in other.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(poly[i], poly[i + 1], other[j], other[j + 1])
				if hit == null:
					continue
				var pos: Vector2 = hit
				var u: float = (pos - poly[i]).length() / maxf(1e-6, (poly[i + 1] - poly[i]).length())
				found.append({"t": (i + u) / count, "pos": pos, "node": -1, "segment": segment.id})
	for node: RoadNode in nodes.values():
		if node.segments.is_empty() or not bounds.has_point(node.pos):
			continue
		var best_d: float = NODE_PASS
		var best_t: float = -1.0
		for i: int in count:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(node.pos, poly[i], poly[i + 1])
			var d: float = closest.distance_to(node.pos)
			if d < best_d:
				best_d = d
				best_t = (i + (closest - poly[i]).length() / maxf(1e-6, (poly[i + 1] - poly[i]).length())) / count
		if best_t >= 0.0:
			found.append({"t": best_t, "pos": node.pos, "node": node.id, "segment": -1})
	# Пересечение у узла дороги — через сам узел.
	for crossing: Dictionary in found:
		if crossing.node != -1:
			continue
		var segment: Segment = segments[crossing.segment]
		for end: int in [segment.a, segment.b]:
			if nodes[end].pos.distance_to(crossing.pos) < NODE_MERGE:
				crossing.node = end
				crossing.pos = nodes[end].pos
				crossing.segment = -1
				break
	var snapped_start: bool = from.node != -1 or from.segment != -1
	var snapped_end: bool = to.node != -1 or to.segment != -1
	var result: Array[Dictionary] = []
	found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.t < y.t)
	var length: float = 0.0
	for i: int in count:
		length += poly[i].distance_to(poly[i + 1])
	for crossing: Dictionary in found:
		if snapped_start and crossing.pos.distance_to(poly[0]) < NODE_MERGE:
			continue
		if snapped_end and crossing.pos.distance_to(poly[count]) < NODE_MERGE:
			continue
		var duplicate: bool = false
		for kept: Dictionary in result:
			if (crossing.node != -1 and crossing.node == kept.node) or absf(crossing.t - kept.t) * length < 0.5:
				duplicate = true
				break
		if not duplicate:
			result.append(crossing)
	return result


## Строит по плану: сносит дома на пути, делит дороги на пересечениях, кладёт куски.
## Деньги не трогает (их списывает инструмент). Возвращает изменённые клетки.
func build(grid: CityGrid, built: Plan) -> Array[Vector2i]:
	sync(grid)
	var changed: Array[Vector2i] = []
	for building_id: int in built.demolish:
		if not grid.buildings.has(building_id):
			continue
		var building: BuildingInstance = grid.buildings[building_id]
		changed.append_array(building.cells())
		var lot: CityGrid.Lot = grid.lot_of(building)
		if lot != null:
			changed.append_array(lot.cells())
		grid.remove_building(building_id)
	var ends: Array[int] = [_resolve(grid, built.from_point)]
	for crossing: Dictionary in built.crossings:
		ends.append(crossing.node if crossing.node != -1 and nodes.has(crossing.node) else _node_at(grid, crossing.pos))
	ends.append(_resolve(grid, built.to_point))
	for k: int in built.pieces.size():
		var piece: PackedVector2Array = built.pieces[k]
		_add_segment(grid, ends[k], ends[k + 1], piece[1], built.type, Claim.SET, changed)
	_finish(grid)
	return changed


func _resolve(grid: CityGrid, point: RoadPoint) -> int:
	if point.node != -1 and nodes.has(point.node):
		return point.node
	return _node_at(grid, point.pos)


## Сносит отрезки (кроме трассы у въезда). Возвращает изменённые клетки.
func remove_segments(grid: CityGrid, ids: Array[int]) -> Array[Vector2i]:
	sync(grid)
	var changed: Array[Vector2i] = []
	for id: int in ids:
		if not segments.has(id) or is_locked(grid, id):
			continue
		var segment: Segment = segments[id]
		_detach(segment)
		for cell: Vector2i in segment.cells:
			if not _owned(cell):
				if grid.remove_road(cell):
					changed.append(cell)
			elif _retype_cell(grid, cell):
				changed.append(cell)
		for end: int in [segment.a, segment.b]:
			if nodes.has(end) and nodes[end].segments.is_empty():
				nodes.erase(end)
	_finish(grid)
	return changed


## Меняет тип отрезка (улица ↔ проспект ↔ шоссе). Возвращает изменённые клетки.
func retype(grid: CityGrid, id: int, type: int) -> Array[Vector2i]:
	sync(grid)
	var changed: Array[Vector2i] = []
	if not segments.has(id) or is_locked(grid, id) or segments[id].type == type:
		return changed
	var segment: Segment = segments[id]
	segment.type = type
	for cell: Vector2i in segment.cells:
		var top: int = 0
		for owner: int in _owners.get(cell, []):
			top = maxi(top, segments[owner].type)
		if top != grid.get_road_type(cell) and not grid.highway_cells.has(cell) and grid.set_road(cell, top):
			changed.append(cell)
	_finish(grid)
	return changed


## Цена смены типа: разница цен клеток (вниз — бесплатно).
func retype_cost(id: int, type: int) -> int:
	if not segments.has(id):
		return 0
	var segment: Segment = segments[id]
	var step: int = RoadTypes.BUILD_COST.get(type, 0) - RoadTypes.BUILD_COST.get(segment.type, 0)
	return maxi(0, step) * segment.cells.size()


# --- Согласование с сеткой ---

## Подтягивает граф к клеткам сетки, если их меняли мимо графа. Дёшево, если ничего не менялось.
func sync(grid: CityGrid) -> void:
	if grid.roads_version == _synced_roads_version:
		return
	var changed: bool = false
	# Клетку отрезка снесли или сменили ей тип мимо графа — отрезок разрезается у этой клетки.
	var broken: Dictionary[int, Array] = {}
	for cell: Vector2i in _owners:
		var owners: Array = _owners[cell]
		var lost: bool = not grid.is_in_bounds(cell) or not grid.is_road(cell)
		if not lost:
			lost = true
			for id: int in owners:
				if segments[id].type == grid.get_road_type(cell):
					lost = false
					break
		if lost:
			for id: int in owners:
				if not broken.has(id):
					broken[id] = []
				broken[id].append(segments[id].cell_t[segments[id].cells.find(cell)])
	for id: int in broken:
		_cut(grid, id, broken[id])
		changed = true
	for cell: Vector2i in _lone.keys():
		if not grid.is_road(cell):
			nodes.erase(_lone[cell])
			_lone.erase(cell)
			changed = true
	var orphans: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in grid.road_cells:
		if not _owned(cell):
			orphans[cell] = true
	if not orphans.is_empty():
		_adopt(grid, orphans)
		changed = true
	_synced_roads_version = grid.roads_version
	if changed:
		version += 1
		_rebuild_caches()


## Разрезает отрезок у клеток с параметрами cuts: куски между ними — та же кривая, на концах — тупики.
## Сетку не меняет (оставшиеся клетки уже дорожные).
func _cut(grid: CityGrid, id: int, cuts: Array) -> void:
	var segment: Segment = segments[id]
	var points: PackedVector2Array = curve(segment)
	var length: float = maxf(0.01, curve_length(points[0], points[1], points[2]))
	var half: float = CELL * 0.55 / length
	cuts.sort()
	var keep: Array[Vector2] = []
	var from_t: float = 0.0
	for t: float in cuts:
		if t - half > from_t:
			keep.append(Vector2(from_t, t - half))
		from_t = maxf(from_t, t + half)
	if from_t < 1.0:
		keep.append(Vector2(from_t, 1.0))
	_detach(segment)
	for span: Vector2 in keep:
		if (span.y - span.x) * length < CELL * 0.5:
			continue
		var a: int = segment.a if span.x <= 0.0 else _add_node(bezier(points[0], points[1], points[2], span.x))
		var b: int = segment.b if span.y >= 1.0 else _add_node(bezier(points[0], points[1], points[2], span.y))
		_add_segment(grid, a, b, sub_control(points[0], points[1], points[2], span.x, span.y), segment.type, Claim.EXISTING)
	for end: int in [segment.a, segment.b]:
		if nodes.has(end) and nodes[end].segments.is_empty():
			nodes.erase(end)


## Направления (0..3 = N/E/S/W) на соседей-дороги.
static func _road_dirs(grid: CityGrid, cell: Vector2i) -> Array[int]:
	var dirs: Array[int] = []
	for k: int in CityGrid.NEIGHBORS.size():
		if grid.is_road(cell + CityGrid.NEIGHBORS[k]):
			dirs.append(k)
	return dirs


## Клетки дороги без отрезков → отрезки: узлы — на концах, поворотах, развилках, смене типа и у
## клеток графа; между узлами — прямые по центрам клеток. Сетку не меняет.
func _adopt(grid: CityGrid, orphans: Dictionary[Vector2i, bool]) -> void:
	var node_of: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in orphans:
		for offset: Vector2i in CityGrid.NEIGHBORS:
			var next: Vector2i = cell + offset
			if grid.is_road(next) and not orphans.has(next) and not node_of.has(next):
				node_of[next] = _node_in_cell(grid, next)
	for cell: Vector2i in orphans:
		var dirs: Array[int] = _road_dirs(grid, cell)
		var key: bool = dirs.size() != 2 or dirs[1] - dirs[0] != 2
		if not key:
			for k: int in dirs:
				var next: Vector2i = cell + CityGrid.NEIGHBORS[k]
				if not orphans.has(next) or grid.get_road_type(next) != grid.get_road_type(cell):
					key = true
		if key:
			node_of[cell] = _add_node(cell_center(cell))
	var done: Dictionary[Vector3i, bool] = {}
	for cell: Vector2i in orphans:
		if not node_of.has(cell):
			continue
		for k: int in _road_dirs(grid, cell):
			if done.has(Vector3i(cell.x, cell.y, k)):
				continue
			var step: Vector2i = CityGrid.NEIGHBORS[k]
			var end: Vector2i = cell + step
			while orphans.has(end) and not node_of.has(end):
				end += step
			if not node_of.has(end):
				continue
			done[Vector3i(cell.x, cell.y, k)] = true
			done[Vector3i(end.x, end.y, (k + 2) % 4)] = true
			var a: int = node_of[cell]
			var b: int = node_of[end]
			if a == b:
				continue
			_add_segment(grid, a, b, (nodes[a].pos + nodes[b].pos) * 0.5, grid.get_road_type(cell), Claim.EXISTING)
	for cell: Vector2i in orphans:
		if not _owned(cell) and node_of.has(cell) and nodes[node_of[cell]].segments.is_empty():
			_lone[cell] = node_of[cell]


## Узел в дорожной клетке графа: есть — он, иначе дорога клетки делится у её центра.
func _node_in_cell(grid: CityGrid, cell: Vector2i) -> int:
	if _lone.has(cell):
		return _lone[cell]
	var best_node: int = -1
	var best_d: float = INF
	for node: RoadNode in nodes.values():
		if cell_of(node.pos) == cell and node.pos.distance_to(cell_center(cell)) < best_d:
			best_d = node.pos.distance_to(cell_center(cell))
			best_node = node.id
	if best_node != -1:
		return best_node
	var best_segment: int = -1
	var best_t: float = 0.5
	best_d = INF
	for id: int in _owners.get(cell, []):
		var hit: Vector2 = nearest_on(segments[id], cell_center(cell))
		if hit.y < best_d:
			best_d = hit.y
			best_t = hit.x
			best_segment = id
	if best_segment == -1:
		return _add_node(cell_center(cell))
	var segment: Segment = segments[best_segment]
	if best_t < 0.02:
		return segment.a
	if best_t > 0.98:
		return segment.b
	return split(grid, best_segment, best_t)


# --- Сохранение ---

func to_dict() -> Dictionary:
	var node_list: Array = []
	for node: RoadNode in nodes.values():
		# Без округления: тот же растр после загрузки (float32 → JSON → float32 без потерь).
		node_list.append([node.id, node.pos.x, node.pos.y])
	var segment_list: Array = []
	for segment: Segment in segments.values():
		segment_list.append([segment.id, segment.a, segment.b, segment.ctrl.x, segment.ctrl.y, segment.type])
	return {"nodes": node_list, "segments": segment_list}


## Граф из сохранения: клетки уже лежат в сетке, граф их только разбирает. Возвращает предупреждения.
func load_dict(grid: CityGrid, data: Variant) -> Array[String]:
	var warnings: Array[String] = []
	nodes.clear()
	segments.clear()
	_owners.clear()
	_lone.clear()
	next_node_id = 0
	next_segment_id = 0
	if data is Dictionary:
		var skipped: int = 0
		for entry: Variant in data.get("nodes", []):
			if entry is Array and entry.size() >= 3:
				var id: int = int(entry[0])
				nodes[id] = RoadNode.new(id, Vector2(float(entry[1]), float(entry[2])))
				next_node_id = maxi(next_node_id, id + 1)
		for entry: Variant in data.get("segments", []):
			if not entry is Array or entry.size() < 6:
				skipped += 1
				continue
			var a: int = int(entry[1])
			var b: int = int(entry[2])
			var type: int = int(entry[5])
			if not nodes.has(a) or not nodes.has(b) or a == b or type <= 0 or type >= RoadTypes.Type.size():
				skipped += 1
				continue
			_add_segment(grid, a, b, Vector2(float(entry[3]), float(entry[4])), type, Claim.EXISTING, [], int(entry[0]))
		for id: int in nodes.keys():
			if nodes[id].segments.is_empty():
				nodes.erase(id)
		if skipped > 0:
			warnings.append("пропущено %d отрезков дорог" % skipped)
	_synced_roads_version = -1
	sync(grid)
	version += 1
	_rebuild_caches()
	return warnings
