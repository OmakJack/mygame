class_name BuildingInstance
extends RefCounted
## Один построенный дом на карте.

## Уникальный номер экземпляра (ключ в CityGrid.buildings).
var id: int
## Тип здания — ссылка на BuildingData.id, например &"res_small_01".
var type_id: StringName
## Левая верхняя клетка участка здания (min_x, min_y).
var cell: Vector2i
## Габариты участка на сетке (ширина по X, глубина по Y) уже с учётом поворота orientation.
var size: Vector2i = Vector2i.ONE
## Направление на дорогу 0/1/2/3 = N/E/S/W (поворот по часовой 0°/90°/180°/270°).
var orientation: int
# Состояние симуляции.
## Сколько тиков подряд нет дороги / света / воды (Decay: по сроку здание пустеет).
var no_road_ticks: int = 0
var no_power_ticks: int = 0
var no_water_ticks: int = 0
## Сколько тиков подряд жителям плохо (фаза 10): после Levels.DECLINE_TICKS дом пустеет.
var unhappy_ticks: int = 0
## Сколько тиков ещё стоит стройплощадкой (сохраняется с 2026-11-01; в старых сохранениях — 0, сразу дом).
var construction_ticks: int = 0
## Сколько тиков длится вся стройка (Levels.start_construction) — для анимации стройки.
var construction_total: int = 0
## Сколько тиков здание стоит готовым (Levels.tick_construction): укрупняют только обжитые дома (Consolidation).
var age_ticks: int = 0
## Здание брошено (Decay): жителей и работы нет, налогов и света с водой не берёт, темнеет.
var abandoned: bool = false
## Сколько тиков подряд причина упадка исправлена — после Decay.RECOVER_TICKS въезжают снова.
var recover_ticks: int = 0
## Результат последнего распределения света и воды (у брошенного — хватило бы ему запаса).
var powered: bool = false
var has_water: bool = false


func _init(p_id: int, p_type_id: StringName, p_cell: Vector2i, p_orientation: int,
		p_size: Vector2i = Vector2i.ONE) -> void:
	id = p_id
	type_id = p_type_id
	cell = p_cell
	orientation = p_orientation
	size = p_size


## Все клетки, которые занимает здание на карте.
func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy: int in size.y:
		for dx: int in size.x:
			result.append(Vector2i(cell.x + dx, cell.y + dy))
	return result


## Клетки фасадного края здания (со стороны orientation: 0=N, 1=E, 2=S, 3=W).
func front_cells() -> Array[Vector2i]:
	return BuildingInstance.edge_cells(cell, size, orientation)


## Клетки края прямоугольника (top_left, span) со стороны dir (0=N, 1=E, 2=S, 3=W).
static func edge_cells(top_left: Vector2i, span: Vector2i, dir: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	match posmod(dir, 4):
		0:
			for dx: int in span.x:
				result.append(Vector2i(top_left.x + dx, top_left.y))
		1:
			for dy: int in span.y:
				result.append(Vector2i(top_left.x + span.x - 1, top_left.y + dy))
		2:
			for dx: int in span.x:
				result.append(Vector2i(top_left.x + dx, top_left.y + span.y - 1))
		_:
			for dy: int in span.y:
				result.append(Vector2i(top_left.x, top_left.y + dy))
	return result
