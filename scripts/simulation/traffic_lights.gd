class_name TrafficLights
extends RefCounted
## Светофоры на перекрёстках: правила общие для симуляции (время на перекрёсток при выборе пути)
## и для машинок (стоят на красный). Перекрёсток — клетка узла графа дорог (RoadGraph) с тремя
## и более дорогами, кроме шоссе (там развязки без светофоров). Для дорог из клеток (подхват графом)
## это то же, что клетка с тремя и более соседями-дорогами (так было до 2026-11-09).
## Фазы: зелёный по оси N–S (ось 0), жёлтый-красный, зелёный по оси E–W (ось 1), красный.
## С этапа C2 ось — у каждого подхода (отрезка графа) к узлу: approach_group — ближайшая ось,
## а если все подходы вышли в одну (косые дороги) — сквозная пара против остальных.
## Соседние перекрёстки сдвинуты по фазе на OFFSET_PER_CELL — «зелёная волна» вдоль улиц.

## Длительности фаз, секунды на ×1.
const GREEN: float = 3.5
const ALL_RED: float = 0.7
const CYCLE: float = 2.0 * (GREEN + ALL_RED)
const OFFSET_PER_CELL: float = 0.35
## Время на перекрёстке при выборе пути (Traffic): в среднем ждём часть цикла; проспект — с приоритетом.
const STREET_DELAY: float = 0.6
const AVENUE_DELAY: float = 0.3

## Часы светофоров: ведёт TrafficLightVisualizer (на паузе стоят); без него — 0 (фаза постоянна).
static var time: float = 0.0
## Оси подходов по узлам: узел → {отрезок → ось}; пересчёт при новой версии графа.
static var _groups: Dictionary[int, Dictionary] = {}
static var _groups_graph: RoadGraph = null
static var _groups_version: int = -1


static func is_junction(grid: CityGrid, cell: Vector2i) -> bool:
	return grid.roads.is_junction(grid, cell)


## Задержка на клетке при выборе пути: на перекрёстке — ожидание светофора.
static func delay_at(grid: CityGrid, cell: Vector2i) -> float:
	if not is_junction(grid, cell):
		return 0.0
	return AVENUE_DELAY if grid.get_road_type(cell) == RoadTypes.Type.AVENUE else STREET_DELAY


## Горит ли зелёный по оси (0 — движение вдоль Z, N–S; 1 — вдоль X, E–W) на перекрёстке cell.
static func is_green(cell: Vector2i, axis: int, at_time: float = time) -> bool:
	var t: float = fposmod(at_time + (cell.x + cell.y) * OFFSET_PER_CELL, CYCLE)
	if axis == 0:
		return t < GREEN
	return t >= GREEN + ALL_RED and t < 2.0 * GREEN + ALL_RED


## Ось движения по шагу между соседними клетками.
static func axis_of(step: Vector2i) -> int:
	return 1 if step.x != 0 else 0


## Ось фазы подхода segment к узлу node: 0 — как N–S, 1 — как E–W.
static func approach_group(graph: RoadGraph, node: int, segment: int) -> int:
	if graph != _groups_graph or graph.version != _groups_version:
		_groups.clear()
		_groups_graph = graph
		_groups_version = graph.version
	if not _groups.has(node):
		_groups[node] = _group_node(graph, node)
	return _groups[node].get(segment, 0)


## Горит ли зелёный подходу segment к перекрёстку node (сдвиг фазы — по клетке узла).
static func approach_green(graph: RoadGraph, node: int, segment: int, at_time: float = time) -> bool:
	return is_green(RoadGraph.cell_of(graph.nodes[node].pos), approach_group(graph, node, segment), at_time)


static func _group_node(graph: RoadGraph, node: int) -> Dictionary:
	var result: Dictionary = {}
	var ids: Array[int] = graph.nodes[node].segments
	var dirs: Array[Vector2] = []
	var counts: Array[int] = [0, 0]
	for id: int in ids:
		var dir: Vector2 = graph.direction_from(graph.segments[id], node)
		dirs.append(dir)
		var axis: int = 0 if absf(dir.y) > absf(dir.x) + 0.01 else 1
		result[id] = axis
		counts[axis] += 1
	if ids.size() < 3 or (counts[0] > 0 and counts[1] > 0):
		return result
	# Все в одной оси: самая прямая пара (сквозная дорога) — ось 0, остальные — ось 1.
	var best: float = INF
	var pair := Vector2i(0, 1)
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var d: float = dirs[i].dot(dirs[j])
			if d < best:
				best = d
				pair = Vector2i(i, j)
	for i: int in ids.size():
		result[ids[i]] = 0 if i == pair.x or i == pair.y else 1
	return result
