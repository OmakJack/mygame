class_name BuildingInstance
extends RefCounted
## Один построенный дом на карте.

## Уникальный номер экземпляра (ключ в CityGrid.buildings).
var id: int
## Тип здания — ссылка на BuildingData.id, например &"res_small_01".
var type_id: StringName
## Клетка-основание.
var cell: Vector2i
## 0/1/2/3 = 0°/90°/180°/270°, здание смотрит на дорогу.
var orientation: int


func _init(p_id: int, p_type_id: StringName, p_cell: Vector2i, p_orientation: int) -> void:
	id = p_id
	type_id = p_type_id
	cell = p_cell
	orientation = p_orientation
