class_name RoadGeometry
extends RefCounted
## Полотно дорог по графу (RoadGraph, этап C1): лента вдоль кривой — асфальт, тротуары с бордюром,
## разметка (улица — пунктир, проспект — газон посередине и пунктир полос, шоссе — отбойник и полосы);
## перекрёсток — асфальт со скруглёнными углами тротуаров и «зеброй» на подходах; тупик — разворотный
## круг; по воде — мост: глубокий борт и перила. Всё — вершинными цветами под одним материалом.

const ASPHALT_Y: float = 0.02
const MARK_Y: float = 0.025
const SIDEWALK_Y: float = 0.045
const ASPHALT := Color(0.24, 0.24, 0.26)
const SIDEWALK := Color(0.64, 0.64, 0.61)
const CURB := Color(0.76, 0.76, 0.73)
const MARK := Color(0.93, 0.93, 0.88)
const MEDIAN := Color(0.36, 0.56, 0.3)
const BARRIER := Color(0.76, 0.76, 0.73)
const BRIDGE := Color(0.5, 0.5, 0.49)
const RAIL := Color(0.33, 0.35, 0.38)
## Радиус скругления угла тротуара на перекрёстке, м.
const CORNER_RADIUS: float = 0.35
## Разворотный круг тупика шире асфальта на столько, м.
const CUL_DE_SAC: float = 0.3
## Шаг сечений ленты на кривой, м.
const STATION_STEP: float = 0.4
## Пунктир: штрих и промежуток, полуширина линии, м.
const DASH: float = 0.45
const DASH_GAP: float = 0.45
const MARK_HALF: float = 0.025
## «Зебра»: длина вдоль дороги, ширина полосы и шаг, м.
const ZEBRA_LENGTH: float = 0.3
const ZEBRA_STRIPE: float = 0.1
const ZEBRA_STEP: float = 0.2
## Мост: борт ниже земли и перила над тротуаром, м.
const BRIDGE_DEPTH: float = 0.3
const RAIL_HEIGHT: float = 0.12
const ARC_STEPS: int = 6
const ARC_SAMPLES: int = 32
## Полоса проспекта и шоссе: пунктир между полосами (машины — на 0.3 и 0.62 от оси).
const LANE_LINE: float = 0.46
const MEDIAN_HALF: float = 0.08
const MEDIAN_HEIGHT: float = 0.02
const BARRIER_HALF: float = 0.05
const BARRIER_HEIGHT: float = 0.1


## Полосы в одну сторону: сдвиг середины каждой вправо от оси, м — по разметке (улица — одна полоса,
## проспект — две между газоном и краем, шоссе — две между отбойником и краем). Первая — ближе к оси.
static func lane_offsets(type: int) -> PackedFloat32Array:
	match type:
		RoadTypes.Type.AVENUE:
			return PackedFloat32Array([(MEDIAN_HALF + LANE_LINE) * 0.5,
					(LANE_LINE + RoadTypes.ASPHALT_HALF[RoadTypes.Type.AVENUE]) * 0.5])
		RoadTypes.Type.HIGHWAY:
			var line: float = LANE_LINE + 0.04
			return PackedFloat32Array([(BARRIER_HALF + line) * 0.5,
					(line + RoadTypes.ASPHALT_HALF[RoadTypes.Type.HIGHWAY]) * 0.5])
	return PackedFloat32Array([RoadTypes.ASPHALT_HALF.get(type, 0.72) * 0.5])


## Узел: дороги по кругу (против часовой при виде сверху) и сколько каждой отрезать до перекрёстка.
class Junction extends RefCounted:
	var node: int = -1
	## {"id", "dir" (из узла), "angle", "a" (полуширина асфальта), "h" (с тротуаром), "type", "trim"}.
	var ends: Array[Dictionary] = []
	## Тупик: разворотный круг. У края карты (въезд трассы) тупик без круга — дорога уходит за карту.
	var cap: bool = false
	var edge: bool = false
	## Три и больше дорог — «зебры» на подходах.
	var crosswalks: bool = false

	func trim_of(id: int) -> float:
		for end: Dictionary in ends:
			if end.id == id:
				return end.trim
		return 0.0


static func arc_table(p0: Vector2, c: Vector2, p2: Vector2) -> PackedFloat32Array:
	var table := PackedFloat32Array([0.0])
	var prev: Vector2 = p0
	var total: float = 0.0
	for i: int in range(1, ARC_SAMPLES + 1):
		var p: Vector2 = RoadGraph.bezier(p0, c, p2, float(i) / ARC_SAMPLES)
		total += prev.distance_to(p)
		table.append(total)
		prev = p
	return table


## t кривой на расстоянии s по дуге от начала.
static func t_at(table: PackedFloat32Array, s: float) -> float:
	var count: int = table.size() - 1
	if s <= 0.0:
		return 0.0
	if s >= table[count]:
		return 1.0
	var lo: int = 0
	var hi: int = count
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if table[mid] <= s:
			lo = mid
		else:
			hi = mid
	var span: float = maxf(1e-6, table[hi] - table[lo])
	return (lo + (s - table[lo]) / span) / count


## Точка и направление (от узла) отрезка на расстоянии s по дуге от узла node.
static func frame_from(graph: RoadGraph, segment: RoadGraph.Segment, node: int, s: float) -> PackedVector2Array:
	var points: PackedVector2Array = graph.curve(segment)
	var table: PackedFloat32Array = arc_table(points[0], points[1], points[2])
	var t: float
	var dir: Vector2
	if segment.a == node:
		t = t_at(table, s)
		dir = RoadGraph.bezier_tangent(points[0], points[1], points[2], t)
	else:
		t = t_at(table, table[table.size() - 1] - s)
		dir = -RoadGraph.bezier_tangent(points[0], points[1], points[2], t)
	if dir.length_squared() < 1e-10:
		dir = graph.direction_from(segment, node)
	return PackedVector2Array([RoadGraph.bezier(points[0], points[1], points[2], t), dir.normalized()])


static func junction(graph: RoadGraph, id: int, world_size: float) -> Junction:
	var result := Junction.new()
	result.node = id
	var node: RoadGraph.RoadNode = graph.nodes[id]
	for segment_id: int in node.segments:
		var segment: RoadGraph.Segment = graph.segments[segment_id]
		var dir: Vector2 = graph.direction_from(segment, id)
		result.ends.append({"id": segment_id, "dir": dir, "angle": atan2(dir.y, dir.x), "type": segment.type,
				"a": RoadTypes.ASPHALT_HALF.get(segment.type, 0.72), "h": RoadTypes.HALF_WIDTH.get(segment.type, 1.0),
				"trim": 0.0, "max": graph.segment_length(segment) * 0.45})
	result.ends.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.angle < y.angle)
	var count: int = result.ends.size()
	if count == 1:
		var p: Vector2 = node.pos
		var margin: float = CityGrid.CELL_SIZE * 0.6
		if p.x < margin or p.y < margin or p.x > world_size - margin or p.y > world_size - margin:
			result.edge = true
		else:
			result.cap = true
			var end: Dictionary = result.ends[0]
			var radius: float = end.a + CUL_DE_SAC
			end.trim = minf(sqrt(radius * radius - end.a * end.a), end.max)
		return result
	result.crosswalks = count >= 3
	for i: int in count:
		var e: Dictionary = result.ends[i]
		var f: Dictionary = result.ends[(i + 1) % count]
		var gap: float = _gap(e.angle, f.angle, i == count - 1)
		if gap < PI - 0.05:
			var hit: Vector2 = _edge_hit(e.dir, e.h, f.dir, f.h)
			var radius: float = CORNER_RADIUS if count >= 3 or gap < 2.4 else 0.0
			e.trim = maxf(e.trim, hit.x + radius)
			f.trim = maxf(f.trim, hit.y + radius)
	for end: Dictionary in result.ends:
		end.trim = minf(end.trim, end.max)
	return result


## Угол от дороги к следующей против часовой (0, 2π]; last — переход через ±π.
static func _gap(from_angle: float, to_angle: float, last: bool) -> float:
	var gap: float = to_angle - from_angle
	if last or gap <= 0.0:
		gap += TAU
	return gap


## Где левый край дороги i (полуширина h_i) пересекает правый край следующей j: Vector2(s_i, s_j) от узла.
static func _edge_hit(d_i: Vector2, h_i: float, d_j: Vector2, h_j: float) -> Vector2:
	var n_i := Vector2(-d_i.y, d_i.x)
	var n_j := Vector2(-d_j.y, d_j.x)
	var rhs: Vector2 = -(n_i * h_i + n_j * h_j)
	var det: float = -(d_i.x * d_j.y - d_i.y * d_j.x)
	if absf(det) < 1e-4:
		return Vector2.ZERO
	var s: float = (rhs.x * -d_j.y - rhs.y * -d_j.x) / det
	var u: float = (d_i.x * rhs.y - d_i.y * rhs.x) / det
	return Vector2(maxf(s, 0.0), maxf(u, 0.0))


# --- Меш узла ---

## Перекрёсток или тупик узла (у края карты и у одиночной клетки — ничего).
static func add_junction(st: SurfaceTool, graph: RoadGraph, j: Junction) -> void:
	if j.edge or j.ends.is_empty():
		return
	var center: Vector2 = graph.nodes[j.node].pos
	if j.cap:
		_add_cap(st, center, j.ends[0])
		return
	var count: int = j.ends.size()
	var frames: Array[PackedVector2Array] = []
	for end: Dictionary in j.ends:
		frames.append(frame_from(graph, graph.segments[end.id], j.node, end.trim))
	var asphalt := PackedVector2Array()
	for i: int in count:
		var k: int = (i + 1) % count
		var e: Dictionary = j.ends[i]
		var f: Dictionary = j.ends[k]
		var gap: float = _gap(e.angle, f.angle, i == count - 1)
		var p_i: Vector2 = frames[i][0]
		var t_i: Vector2 = frames[i][1]
		var n_i := Vector2(-t_i.y, t_i.x)
		var p_k: Vector2 = frames[k][0]
		var t_k: Vector2 = frames[k][1]
		var n_k := Vector2(-t_k.y, t_k.x)
		asphalt.append(p_i - n_i * e.a)
		var inner: PackedVector2Array = _corner(center, p_i + n_i * e.a, t_i, p_k - n_k * f.a, t_k, gap)
		for m: int in range(0, inner.size() - 1):
			asphalt.append(inner[m])
		if e.h > e.a + 0.01 or f.h > f.a + 0.01:
			var outer: PackedVector2Array = _corner(center, p_i + n_i * e.h, t_i, p_k - n_k * f.h, t_k, gap)
			_ring(st, inner, outer)
	_fill(st, asphalt, ASPHALT_Y, ASPHALT, center)


## Угол перекрёстка от точки a (левый край дороги) до b (правый край следующей): выпуклый — дуга
## Безье через пересечение краёв, вогнутый (больше 180°) — дуга вокруг узла, почти прямой — отрезок.
static func _corner(center: Vector2, a: Vector2, dir_a: Vector2, b: Vector2, dir_b: Vector2, gap: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if gap > PI + 0.05:
		var from_angle: float = (a - center).angle()
		var sweep: float = fposmod((b - center).angle() - from_angle, TAU)
		var r0: float = a.distance_to(center)
		var r1: float = b.distance_to(center)
		for m: int in ARC_STEPS + 1:
			var u: float = float(m) / ARC_STEPS
			points.append(center + Vector2.from_angle(from_angle + sweep * u) * lerpf(r0, r1, u))
		points[0] = a
		points[ARC_STEPS] = b
		return points
	var control: Vector2 = (a + b) * 0.5
	if gap < PI - 0.05:
		var det: float = dir_a.x * -dir_b.y - dir_a.y * -dir_b.x
		if absf(det) > 1e-4:
			var rhs: Vector2 = b - a
			var s: float = (rhs.x * -dir_b.y - rhs.y * -dir_b.x) / det
			if absf(s) < 3.0:
				control = a + dir_a * s
	for m: int in ARC_STEPS + 1:
		points.append(RoadGraph.bezier(a, control, b, float(m) / ARC_STEPS))
	return points


## Тротуар между кромкой асфальта inner и внешним краем outer: верх, бордюр и внешний борт.
static func _ring(st: SurfaceTool, inner: PackedVector2Array, outer: PackedVector2Array) -> void:
	for m: int in inner.size() - 1:
		_quad(st, _v(inner[m], SIDEWALK_Y), _v(inner[m + 1], SIDEWALK_Y), _v(outer[m + 1], SIDEWALK_Y),
				_v(outer[m], SIDEWALK_Y), Vector3.UP, SIDEWALK)
		var to_road: Vector2 = (inner[m] + inner[m + 1] - outer[m] - outer[m + 1])
		if to_road.length_squared() < 1e-8:
			continue
		var normal := Vector3(to_road.x, 0.0, to_road.y).normalized()
		_quad(st, _v(inner[m], ASPHALT_Y), _v(inner[m + 1], ASPHALT_Y), _v(inner[m + 1], SIDEWALK_Y),
				_v(inner[m], SIDEWALK_Y), normal, CURB)
		_quad(st, _v(outer[m], 0.0), _v(outer[m + 1], 0.0), _v(outer[m + 1], SIDEWALK_Y),
				_v(outer[m], SIDEWALK_Y), -normal, CURB)


## Разворотный круг: асфальтовый круг и тротуар вокруг, кроме стороны дороги.
static func _add_cap(st: SurfaceTool, center: Vector2, end: Dictionary) -> void:
	var radius: float = end.a + CUL_DE_SAC
	var disc := PackedVector2Array()
	for m: int in 24:
		disc.append(center + Vector2.from_angle(TAU * m / 24.0) * radius)
	_fill(st, disc, ASPHALT_Y, ASPHALT, center)
	if end.h <= end.a + 0.01:
		return
	var outer_radius: float = radius + end.h - end.a
	var alpha: float = asin(clampf(end.a / radius, 0.0, 1.0))
	var beta: float = asin(clampf(end.h / outer_radius, 0.0, 1.0))
	var steps: int = 20
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for m: int in steps + 1:
		var u: float = float(m) / steps
		inner.append(center + Vector2.from_angle(end.angle + alpha + (TAU - 2.0 * alpha) * u) * radius)
		outer.append(center + Vector2.from_angle(end.angle + beta + (TAU - 2.0 * beta) * u) * outer_radius)
	_ring(st, inner, outer)


## Заливка многоугольника (если не вышло — веером от центра).
static func _fill(st: SurfaceTool, polygon: PackedVector2Array, y: float, color: Color, center: Vector2) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		for m: int in polygon.size():
			_tri(st, _v(center, y), _v(polygon[m], y), _v(polygon[(m + 1) % polygon.size()], y), Vector3.UP, color)
		return
	for m: int in range(0, indices.size(), 3):
		_tri(st, _v(polygon[indices[m]], y), _v(polygon[indices[m + 1]], y), _v(polygon[indices[m + 2]], y), Vector3.UP, color)


# --- Меш отрезка ---

## Сечения ленты от s0 до s1 по дуге: [точка, касательная, нормаль влево] и «над водой».
class Stations extends RefCounted:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var water := PackedByteArray()


static func _stations(p0: Vector2, c: Vector2, p2: Vector2, s0: float, s1: float, step_all: bool,
		grid: CityGrid) -> Stations:
	var table: PackedFloat32Array = arc_table(p0, c, p2)
	var straight: bool = c.distance_to((p0 + p2) * 0.5) < 0.01 and not step_all
	var count: int = 1 if straight else maxi(1, ceili((s1 - s0) / STATION_STEP))
	var result := Stations.new()
	for i: int in count + 1:
		var t: float = t_at(table, lerpf(s0, s1, float(i) / count))
		var p: Vector2 = RoadGraph.bezier(p0, c, p2, t)
		var tangent: Vector2 = RoadGraph.bezier_tangent(p0, c, p2, t)
		if tangent.length_squared() < 1e-10:
			tangent = p2 - p0
		tangent = tangent.normalized()
		result.points.append(p)
		result.normals.append(Vector2(-tangent.y, tangent.x))
		var cell: Vector2i = RoadGraph.cell_of(p)
		result.water.append(1 if grid != null and grid.is_in_bounds(cell) and grid.is_water(cell) else 0)
	return result


## Лента отрезка между обрезками у узлов. zebra_a / zebra_b — «зебра» у начала / конца.
static func add_segment(st: SurfaceTool, graph: RoadGraph, segment: RoadGraph.Segment, trim_a: float, trim_b: float,
		zebra_a: bool, zebra_b: bool, grid: CityGrid) -> void:
	var points: PackedVector2Array = graph.curve(segment)
	var length: float = arc_table(points[0], points[1], points[2])[ARC_SAMPLES]
	var s0: float = trim_a
	var s1: float = length - trim_b
	if s1 - s0 < 0.02:
		return
	var on_water: bool = false
	if grid != null:
		for cell: Vector2i in segment.cells:
			if grid.is_water(cell):
				on_water = true
				break
	var stations: Stations = _stations(points[0], points[1], points[2], s0, s1, on_water, grid)
	add_ribbon(st, stations, segment.type)
	var a: float = RoadTypes.ASPHALT_HALF.get(segment.type, 0.72)
	match segment.type:
		RoadTypes.Type.STREET:
			_dashes(st, points, s0, s1, 0.0)
		RoadTypes.Type.AVENUE:
			_dashes(st, points, s0, s1, LANE_LINE)
			_dashes(st, points, s0, s1, -LANE_LINE)
		RoadTypes.Type.HIGHWAY:
			_dashes(st, points, s0, s1, LANE_LINE + 0.04)
			_dashes(st, points, s0, s1, -LANE_LINE - 0.04)
	if segment.type != RoadTypes.Type.HIGHWAY:
		if zebra_a:
			_zebra(st, points, s0, a)
		if zebra_b:
			_zebra(st, points, s1 - ZEBRA_LENGTH, a)


## Лента по сечениям: асфальт, тротуары с бордюрами (или отбойник шоссе), газон проспекта, мост.
static func add_ribbon(st: SurfaceTool, stations: Stations, type: int) -> void:
	var a: float = RoadTypes.ASPHALT_HALF.get(type, 0.72)
	var h: float = RoadTypes.HALF_WIDTH.get(type, 1.0)
	_band(st, stations, -a, a, ASPHALT_Y, ASPHALT)
	var edge_top: float = ASPHALT_Y
	if h > a + 0.01:
		edge_top = SIDEWALK_Y
		_band(st, stations, a, h, SIDEWALK_Y, SIDEWALK)
		_band(st, stations, -h, -a, SIDEWALK_Y, SIDEWALK)
		_wall(st, stations, a, ASPHALT_Y, SIDEWALK_Y, -1.0, CURB)
		_wall(st, stations, -a, ASPHALT_Y, SIDEWALK_Y, 1.0, CURB)
	_wall(st, stations, h, 0.0, edge_top, 1.0, CURB)
	_wall(st, stations, -h, 0.0, edge_top, -1.0, CURB)
	match type:
		RoadTypes.Type.AVENUE:
			var top: float = ASPHALT_Y + MEDIAN_HEIGHT
			_band(st, stations, -MEDIAN_HALF, MEDIAN_HALF, top, MEDIAN)
			_wall(st, stations, MEDIAN_HALF, ASPHALT_Y, top, 1.0, CURB)
			_wall(st, stations, -MEDIAN_HALF, ASPHALT_Y, top, -1.0, CURB)
		RoadTypes.Type.HIGHWAY:
			var top: float = ASPHALT_Y + BARRIER_HEIGHT
			_band(st, stations, -BARRIER_HALF, BARRIER_HALF, top, BARRIER)
			_wall(st, stations, BARRIER_HALF, ASPHALT_Y, top, 1.0, BARRIER)
			_wall(st, stations, -BARRIER_HALF, ASPHALT_Y, top, -1.0, BARRIER)
			_band(st, stations, a - 0.1, a - 0.06, MARK_Y, MARK)
			_band(st, stations, -a + 0.06, -a + 0.1, MARK_Y, MARK)
	# Мост: глубокий борт под водой и перила по краю.
	for i: int in stations.points.size() - 1:
		if stations.water[i] == 0 and stations.water[i + 1] == 0:
			continue
		for side: float in [1.0, -1.0]:
			var p: Vector2 = stations.points[i] + stations.normals[i] * h * side
			var q: Vector2 = stations.points[i + 1] + stations.normals[i + 1] * h * side
			var out := Vector3(stations.normals[i].x, 0.0, stations.normals[i].y) * side
			_quad(st, _v(p, -BRIDGE_DEPTH), _v(q, -BRIDGE_DEPTH), _v(q, 0.0), _v(p, 0.0), out, BRIDGE)
			var r: Vector2 = stations.points[i] + stations.normals[i] * (h - 0.04) * side
			var w: Vector2 = stations.points[i + 1] + stations.normals[i + 1] * (h - 0.04) * side
			_quad(st, _v(r, edge_top), _v(w, edge_top), _v(w, edge_top + RAIL_HEIGHT), _v(r, edge_top + RAIL_HEIGHT), out, RAIL)
			_quad(st, _v(r, edge_top), _v(w, edge_top), _v(w, edge_top + RAIL_HEIGHT), _v(r, edge_top + RAIL_HEIGHT), -out, RAIL)


## Полоса вдоль ленты от смещения x0 до x1 (влево от оси) на высоте y.
static func _band(st: SurfaceTool, stations: Stations, x0: float, x1: float, y: float, color: Color) -> void:
	for i: int in stations.points.size() - 1:
		var p: Vector2 = stations.points[i]
		var q: Vector2 = stations.points[i + 1]
		var n: Vector2 = stations.normals[i]
		var m: Vector2 = stations.normals[i + 1]
		_quad(st, _v(p + n * x0, y), _v(p + n * x1, y), _v(q + m * x1, y), _v(q + m * x0, y), Vector3.UP, color)


## Вертикальная стенка вдоль ленты на смещении x от y0 до y1; side — куда смотрит (+ влево).
static func _wall(st: SurfaceTool, stations: Stations, x: float, y0: float, y1: float, side: float, color: Color) -> void:
	for i: int in stations.points.size() - 1:
		var p: Vector2 = stations.points[i] + stations.normals[i] * x
		var q: Vector2 = stations.points[i + 1] + stations.normals[i + 1] * x
		var n: Vector2 = (stations.normals[i] + stations.normals[i + 1]).normalized() * side
		_quad(st, _v(p, y0), _v(q, y0), _v(q, y1), _v(p, y1), Vector3(n.x, 0.0, n.y), color)


## Пунктир вдоль кривой на смещении x от оси.
static func _dashes(st: SurfaceTool, points: PackedVector2Array, s0: float, s1: float, x: float) -> void:
	var table: PackedFloat32Array = arc_table(points[0], points[1], points[2])
	var s: float = s0 + DASH_GAP * 0.5
	while s < s1 - 0.05:
		var e: float = minf(s + DASH, s1 - 0.05)
		var strip := PackedVector2Array()
		var normals := PackedVector2Array()
		for u: float in [0.0, 0.5, 1.0]:
			var t: float = t_at(table, lerpf(s, e, u))
			var tangent: Vector2 = RoadGraph.bezier_tangent(points[0], points[1], points[2], t).normalized()
			strip.append(RoadGraph.bezier(points[0], points[1], points[2], t))
			normals.append(Vector2(-tangent.y, tangent.x))
		for k: int in 2:
			var p: Vector2 = strip[k] + normals[k] * x
			var q: Vector2 = strip[k + 1] + normals[k + 1] * x
			_quad(st, _v(p - normals[k] * MARK_HALF, MARK_Y), _v(p + normals[k] * MARK_HALF, MARK_Y),
					_v(q + normals[k + 1] * MARK_HALF, MARK_Y), _v(q - normals[k + 1] * MARK_HALF, MARK_Y), Vector3.UP, MARK)
		s += DASH + DASH_GAP


## «Зебра» поперёк асфальта на участке [s, s + ZEBRA_LENGTH].
static func _zebra(st: SurfaceTool, points: PackedVector2Array, s: float, a: float) -> void:
	var table: PackedFloat32Array = arc_table(points[0], points[1], points[2])
	var t0: float = t_at(table, maxf(0.0, s))
	var t1: float = t_at(table, s + ZEBRA_LENGTH)
	var p: Vector2 = RoadGraph.bezier(points[0], points[1], points[2], t0)
	var q: Vector2 = RoadGraph.bezier(points[0], points[1], points[2], t1)
	var tangent: Vector2 = (q - p).normalized()
	var n := Vector2(-tangent.y, tangent.x)
	var x: float = -a + ZEBRA_STEP * 0.5
	while x + ZEBRA_STRIPE < a - 0.04:
		_quad(st, _v(p + n * x, MARK_Y), _v(p + n * (x + ZEBRA_STRIPE), MARK_Y), _v(q + n * (x + ZEBRA_STRIPE), MARK_Y),
				_v(q + n * x, MARK_Y), Vector3.UP, MARK)
		x += ZEBRA_STEP


## Лента всей кривой без обрезок и разметки (превью инструмента дорог).
static func ribbon_mesh(p0: Vector2, c: Vector2, p2: Vector2, type: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length: float = arc_table(p0, c, p2)[ARC_SAMPLES]
	if length > 0.01:
		add_ribbon(st, _stations(p0, c, p2, 0.0, length, false, null), type)
	return st.commit()


## Прямой кусок дороги длиной length вдоль оси Z, с центром в нуле (трасса за картой).
static func straight_piece(type: int, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p0 := Vector2(0.0, -length * 0.5)
	var p2 := Vector2(0.0, length * 0.5)
	add_ribbon(st, _stations(p0, (p0 + p2) * 0.5, p2, 0.0, length, false, null), type)
	var points := PackedVector2Array([p0, (p0 + p2) * 0.5, p2])
	_dashes(st, points, 0.0, length, LANE_LINE + 0.04)
	_dashes(st, points, 0.0, length, -LANE_LINE - 0.04)
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, material())
	return mesh


static var _material: StandardMaterial3D = null


## Общий материал полотна: цвет — из вершин.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.92
	return _material


# --- Треугольники ---

static func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Треугольник лицом к normal (у Godot лицевая сторона — обход по часовой стрелке).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	_tri(st, a, b, c, normal, color)
	_tri(st, a, c, d, normal, color)
