class_name DemandBar
extends Control
## Полоска спроса от центра: вправо цветом зоны при спросе > 0, влево тусклым при < 0.
## Посередине — риска нуля. Пустая полоска = рост стоит.

const BACKGROUND := Color(0.0, 0.0, 0.0, 0.35)
const ZERO_MARK := Color(1.0, 1.0, 1.0, 0.8)
## Насколько тусклее рисуется нехватка спроса.
const NEGATIVE_DIM: float = 0.55

## Цвет зоны.
var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
## Спрос в [−1, 1].
var value: float = 0.0:
	set(new_value):
		value = clampf(new_value, -1.0, 1.0)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(60, 14)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BACKGROUND)
	var center: float = size.x * 0.5
	var width: float = center * absf(value)
	if value > 0.0:
		draw_rect(Rect2(center, 0.0, width, size.y), color)
	elif value < 0.0:
		draw_rect(Rect2(center - width, 0.0, width, size.y), color.darkened(NEGATIVE_DIM))
	draw_rect(Rect2(center - 1.0, 0.0, 2.0, size.y), ZERO_MARK)
