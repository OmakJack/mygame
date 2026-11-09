class_name TrafficLights
extends RefCounted
## Светофоры на перекрёстках: правила общие для симуляции (время на перекрёсток при выборе пути)
## и для машинок (стоят на красный). Перекрёсток — клетка узла графа дорог (RoadGraph) с тремя
## и более дорогами, кроме шоссе (там развязки без светофоров). Для дорог из клеток (подхват графом)
## это то же, что клетка с тремя и более соседями-дорогами (так было до 2026-11-09).
## Фазы: зелёный по оси N–S (ось 0), жёлтый-красный, зелёный по оси E–W (ось 1), красный.
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
