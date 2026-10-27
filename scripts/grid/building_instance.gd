class_name BuildingInstance
extends RefCounted
## Один построенный дом на карте.

## Уникальный номер экземпляра (ключ в CityGrid.buildings).
var id: int
## Тип здания — ссылка на BuildingData.id, например &"res_small_01".
var type_id: StringName
## Клетка-основание.
var cell: Vector2i
## Направление на дорогу 0/1/2/3 = N/E/S/W (поворот по часовой 0°/90°/180°/270°).
var orientation: int
# Состояние симуляции.
## Сколько тиков подряд нет дороги / света / воды.
var no_road_ticks: int = 0
var no_power_ticks: int = 0
var no_water_ticks: int = 0
## Сколько дней подряд жителям плохо (фаза 10): после Levels.DECLINE_TICKS дом пустеет.
var unhappy_ticks: int = 0
## Сколько дней ещё стоит стройплощадкой (не сохраняется: после загрузки — сразу дом).
var construction_ticks: int = 0
## Результат последнего распределения света и воды.
var powered: bool = false
var has_water: bool = false


func _init(p_id: int, p_type_id: StringName, p_cell: Vector2i, p_orientation: int) -> void:
	id = p_id
	type_id = p_type_id
	cell = p_cell
	orientation = p_orientation
