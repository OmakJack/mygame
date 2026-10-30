class_name DemandBar
extends Control
## Полоска спроса от центра: вправо цветом зоны при спросе > 0, влево тусклым при < 0.
## Посередине — риска нуля. Пустая полоска = рост стоит.

const BACKGROUND := Color(0.22, 0.19, 0.16, 0.28)
const BORDER := Color(0.22, 0.19, 0.16, 0.35)
const ZERO_MARK := Color(1.0, 0.98, 0.94, 0.9)
## Насколько тусклее рисуется нехватка спроса.
const NEGATIVE_DIM: float = 0.5

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
	custom_minimum_size = Vector2(56, 14)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var track := StyleBoxFlat.new()
	track.bg_color = BACKGROUND
	track.border_color = BORDER
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	draw_style_box(track, rect)
	var center: float = size.x * 0.5
	var width: float = (center - 2.0) * absf(value)
	if width > 0.5:
		var fill := StyleBoxFlat.new()
		fill.bg_color = color if value > 0.0 else color.darkened(NEGATIVE_DIM)
		fill.set_corner_radius_all(3)
		var fill_x: float = center if value > 0.0 else (center - width)
		draw_style_box(fill, Rect2(fill_x, 2.0, width, size.y - 4.0))
	draw_rect(Rect2(center - 1.0, 1.0, 2.0, size.y - 2.0), ZERO_MARK)
