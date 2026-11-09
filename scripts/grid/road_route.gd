class_name RoadRoute
extends RefCounted
## Маршрут машинки или пешехода по графу дорог (этап C2). Путь из Traffic — клетки, а едут по кривым
## отрезков (RoadGraph) со сдвигом вправо от оси на свою полосу; в узле — дуга поворота от края
## перекрёстка до края, перед перекрёстком со светофором — стоп-линия до «зебры».
## Ломаная с шагом STEP и расстоянием по ней; участки (Leg) — для очередей: на одном отрезке,
## в одну сторону и в одной полосе машины видят друг друга по общей координате вдоль отрезка.

## Шаг ломаной вдоль отрезка, м.
const STEP: float = 0.25
## Стоп-линия: от края перекрёстка назад — «зебра» и ещё чуть-чуть, м.
const STOP_BACK: float = RoadGeometry.ZEBRA_LENGTH + 0.1


## Участок маршрута по одному отрезку графа; дуга поворота в узле перед ним — его начало.
class Leg extends RefCounted:
	## Ключ очереди: (отрезок · 2 + направление) · 2 + полоса; −1 — без очереди (переход без узла).
	var key: int = -1
	## Начало и конец на маршруте, м.
	var start: float = 0.0
	var end: float = 0.0
	## Координата вдоль отрезка (от узла, откуда едем) в начале участка, м; у дуги поворота — меньше
	## координаты края перекрёстка на длину дуги.
	var frame: float = 0.0
	## Стоп-линия перед перекрёстком со светофором, м по маршруту; −1 — нет.
	var stop: float = -1.0
	## Перекрёсток впереди и отрезок, по которому к нему подъезжаем (фаза светофора — по подходу).
	var light_node: int = -1
	var light_segment: int = -1


var points := PackedVector2Array()
## Расстояние от начала до каждой точки, м.
var dist := PackedFloat32Array()
var legs: Array[Leg] = []

## Обрезки узлов (как у полотна, RoadGeometry.junction) — общие для всех маршрутов одной версии графа.
static var _junctions: Dictionary[int, RoadGeometry.Junction] = {}
static var _junctions_graph: RoadGraph = null
static var _junctions_version: int = -1


func length() -> float:
	return dist[dist.size() - 1] if not dist.is_empty() else 0.0


## Номер отрезка ломаной, на котором расстояние d.
func _index(d: float) -> int:
	var lo: int = 0
	var hi: int = dist.size() - 1
	if hi <= 0:
		return 0
	if d >= dist[hi]:
		return hi - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if dist[mid] <= d:
			lo = mid
		else:
			hi = mid
	return lo


func point_at(d: float) -> Vector2:
	if points.size() < 2:
		return points[0] if not points.is_empty() else Vector2.ZERO
	var i: int = _index(d)
	var span: float = dist[i + 1] - dist[i]
	var f: float = clampf((d - dist[i]) / span, 0.0, 1.0) if span > 1e-6 else 0.0
	return points[i].lerp(points[i + 1], f)


## Направление движения (единичное) на расстоянии d.
func dir_at(d: float) -> Vector2:
	if points.size() < 2:
		return Vector2.UP
	var i: int = _index(d)
	var step: Vector2 = points[i + 1] - points[i]
	return step.normalized() if step.length_squared() > 1e-8 else (points[points.size() - 1] - points[0]).normalized()


## Номер участка на расстоянии d.
func leg_at(d: float) -> int:
	for i: int in range(legs.size() - 1, -1, -1):
		if legs[i].start <= d:
			return i
	return 0


## Расстояние до ближайшей к pos точки маршрута (дороги поменялись — машинка остаётся, где была).
func nearest(pos: Vector2) -> float:
	var best: float = INF
	var result: float = 0.0
	for i: int in points.size():
		var d: float = points[i].distance_squared_to(pos)
		if d < best:
			best = d
			result = dist[i]
	return result


func _add(p: Vector2) -> void:
	if points.is_empty():
		points.append(p)
		dist.append(0.0)
		return
	var step: float = points[points.size() - 1].distance_to(p)
	if step < 0.01:
		return
	points.append(p)
	dist.append(dist[dist.size() - 1] + step)


## Общий узел двух отрезков (ближе к near, если их два); −1 — нет.
static func shared_node(graph: RoadGraph, first: int, second: int, near: Vector2) -> int:
	var s1: RoadGraph.Segment = graph.segments[first]
	var s2: RoadGraph.Segment = graph.segments[second]
	var best: int = -1
	var best_d: float = INF
	for node: int in [s1.a, s1.b]:
		if node == s2.a or node == s2.b:
			var d: float = graph.nodes[node].pos.distance_squared_to(near)
			if d < best_d:
				best_d = d
				best = node
	return best


## Сколько отрезать от конца отрезка у узла: у перекрёстка и поворота — край полотна, у тупика — 0.
static func trim(graph: RoadGraph, grid: CityGrid, node: int, segment: int) -> float:
	if graph != _junctions_graph or graph.version != _junctions_version:
		_junctions.clear()
		_junctions_graph = graph
		_junctions_version = graph.version
	if graph.nodes[node].segments.size() < 2:
		return 0.0
	if not _junctions.has(node):
		_junctions[node] = RoadGeometry.junction(graph, node, grid.world_size())
	return _junctions[node].trim_of(segment)


## t кривой в клетке отрезка.
static func _t_of(segment: RoadGraph.Segment, cell: Vector2i) -> float:
	var i: int = segment.cells.find(cell)
	return segment.cell_t[i] if i != -1 else 0.5


## Расстояние по дуге до t (таблица RoadGeometry.arc_table).
static func _s_of(table: PackedFloat32Array, t: float) -> float:
	var count: int = table.size() - 1
	var x: float = clampf(t, 0.0, 1.0) * count
	var i: int = mini(int(x), count - 1)
	return lerpf(table[i], table[i + 1], x - i)


## Маршрут по клеткам cells (в порядке езды). offsets — сдвиг вправо от оси по типу дороги, м;
## lane — полоса для ключа очереди на дорогах с двумя полосами.
static func build(graph: RoadGraph, grid: CityGrid, cells: Array[Vector2i], offsets: Dictionary, lane: int) -> RoadRoute:
	var route := RoadRoute.new()
	var runs: Array[Dictionary] = _runs(graph, cells)
	# Узлы между соседними отрезками пути.
	for r: int in runs.size():
		runs[r]["entry"] = -1
		runs[r]["exit"] = -1
	for r: int in range(1, runs.size()):
		if runs[r - 1].seg == -1 or runs[r].seg == -1:
			continue
		var node: int = shared_node(graph, runs[r - 1].seg, runs[r].seg, graph.anchor(cells[runs[r].i0]))
		runs[r - 1]["exit"] = node
		runs[r]["entry"] = node
	var prev: Dictionary = {}
	for run: Dictionary in runs:
		var piece: Dictionary = _piece(graph, grid, cells, run, offsets)
		if piece.is_empty():
			continue
		var leg := Leg.new()
		leg.start = route.length() if not route.points.is_empty() else 0.0
		var first: Vector2 = piece.points[0]
		if not prev.is_empty():
			# Переход от конца прошлого куска: через общий узел — дуга поворота, иначе — прямо.
			var via_node: bool = prev.exit != -1 and prev.exit == piece.entry
			var last: Vector2 = route.points[route.points.size() - 1]
			for p: Vector2 in (_turn(last, prev.dir_out, first, piece.dir_in) if via_node else PackedVector2Array()):
				route._add(p)
		route._add(first)
		var turn_length: float = route.length() - leg.start
		var piece_start: float = route.length()
		for i: int in range(1, piece.points.size()):
			route._add(piece.points[i])
		leg.end = route.length()
		if piece.seg != -1:
			var segment: RoadGraph.Segment = graph.segments[piece.seg]
			var lanes: int = RoadGeometry.lane_offsets(segment.type).size()
			leg.key = ((piece.seg * 2 + (0 if piece.forward else 1)) * 2) + (mini(lane, lanes - 1) if lanes > 1 else 0)
			leg.frame = piece.frame_in - turn_length
			if piece.exit != -1 and TrafficLights.is_junction(grid, RoadGraph.cell_of(graph.nodes[piece.exit].pos)):
				leg.stop = maxf(piece_start, leg.end - STOP_BACK)
				leg.light_node = piece.exit
				leg.light_segment = piece.seg
		route.legs.append(leg)
		prev = piece
	# Ничего не вышло (клетки без отрезков) — по точкам клеток, как раньше.
	if route.points.size() < 2:
		route.points.clear()
		route.dist.clear()
		route.legs.clear()
		for cell: Vector2i in cells:
			route._add(graph.anchor(cell))
		var leg := Leg.new()
		leg.end = route.length()
		route.legs.append(leg)
	return route


## Клетки пути → куски по отрезкам: держимся отрезка, пока он владеет клетками; дальше — тот,
## что идёт дольше (при равенстве — с общим узлом с прошлым). Клетка без отрезка — кусок seg = −1.
static func _runs(graph: RoadGraph, cells: Array[Vector2i]) -> Array[Dictionary]:
	var owners: Array[Array] = []
	for cell: Vector2i in cells:
		owners.append(graph.owners_of(cell))
	var runs: Array[Dictionary] = []
	var count: int = cells.size()
	var i: int = 0
	while i < count:
		var prev: int = runs[runs.size() - 1].seg if not runs.is_empty() else -1
		var best: int = -1
		var best_end: int = i
		var best_score: int = -1
		for id: int in owners[i]:
			var j: int = i
			while j + 1 < count and owners[j + 1].has(id):
				j += 1
			var score: int = (j - i) * 4
			if prev != -1 and shared_node(graph, prev, id, graph.anchor(cells[i])) != -1:
				score += 2
			if score > best_score:
				best_score = score
				best = id
				best_end = j
		runs.append({"seg": best, "i0": i, "i1": best_end})
		i = best_end + 1
	return runs


## Точки куска пути по отрезку (со сдвигом на полосу) и его концы; пустой — кусок вырожден
## (въехали в узел и выехали из него же).
static func _piece(graph: RoadGraph, grid: CityGrid, cells: Array[Vector2i], run: Dictionary,
		offsets: Dictionary) -> Dictionary:
	if run.seg == -1:
		var p: Vector2 = graph.anchor(cells[run.i0])
		return {"seg": -1, "points": PackedVector2Array([p]), "entry": -1, "exit": -1, "forward": true,
				"dir_in": Vector2.ZERO, "dir_out": Vector2.ZERO, "frame_in": 0.0}
	if run.entry != -1 and run.entry == run.exit:
		return {}
	var segment: RoadGraph.Segment = graph.segments[run.seg]
	var c: PackedVector2Array = graph.curve(segment)
	var table: PackedFloat32Array = RoadGeometry.arc_table(c[0], c[1], c[2])
	var total: float = table[table.size() - 1]
	var t_in: float = _t_of(segment, cells[run.i0])
	var t_out: float = _t_of(segment, cells[run.i1])
	var forward: bool
	if run.entry != -1:
		forward = run.entry == segment.a
	elif run.exit != -1:
		forward = run.exit == segment.b
	else:
		forward = t_out >= t_in
	var lo: float = trim(graph, grid, segment.a, run.seg)
	var hi: float = total - trim(graph, grid, segment.b, run.seg)
	if hi < lo:
		lo = total * 0.5
		hi = lo
	var s_in: float = (lo if forward else hi) if run.entry != -1 else clampf(_s_of(table, t_in), lo, hi)
	var s_out: float = (hi if forward else lo) if run.exit != -1 else clampf(_s_of(table, t_out), lo, hi)
	if (s_out < s_in) == forward and not is_equal_approx(s_out, s_in):
		s_out = s_in
	var offset: float = offsets.get(segment.type, offsets.get(RoadTypes.Type.STREET, 0.0))
	var sign: float = 1.0 if forward else -1.0
	var count: int = maxi(1, ceili(absf(s_out - s_in) / STEP))
	var result := PackedVector2Array()
	var dir_in := Vector2.ZERO
	var dir_out := Vector2.ZERO
	for k: int in count + 1:
		var t: float = RoadGeometry.t_at(table, lerpf(s_in, s_out, float(k) / count))
		var tangent: Vector2 = RoadGraph.bezier_tangent(c[0], c[1], c[2], t)
		if tangent.length_squared() < 1e-8:
			tangent = c[2] - c[0]
		tangent = tangent.normalized() * sign
		if k == 0:
			dir_in = tangent
		dir_out = tangent
		result.append(RoadGraph.bezier(c[0], c[1], c[2], t) + Vector2(-tangent.y, tangent.x) * offset)
	return {"seg": run.seg, "points": result, "entry": run.entry, "exit": run.exit, "forward": forward,
			"dir_in": dir_in, "dir_out": dir_out, "frame_in": s_in if forward else total - s_in}


## Дуга поворота от p0 (едем по d0) к p2 (дальше по d2) без концов: изгиб — там, где сходятся
## продолжения полос; прямо (или пересечение сзади) — прямая.
static func _turn(p0: Vector2, d0: Vector2, p2: Vector2, d2: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	var gap: float = p0.distance_to(p2)
	if gap < 0.02:
		return result
	var ctrl: Vector2 = (p0 + p2) * 0.5
	var cross: float = d0.cross(d2)
	if absf(cross) > 0.05:
		# p0 + d0·u = p2 − d2·w: пересечение впереди нас и позади выезда.
		var u: float = (p2 - p0).cross(d2) / cross
		var w: float = -(p2 - p0).cross(d0) / cross
		if u > 0.0 and w > 0.0 and u < gap * 2.0 and w < gap * 2.0:
			ctrl = p0 + d0 * u
	var count: int = maxi(2, ceili(RoadGraph.curve_length(p0, ctrl, p2) / STEP))
	for k: int in range(1, count):
		result.append(RoadGraph.bezier(p0, ctrl, p2, float(k) / count))
	return result
