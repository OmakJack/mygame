extends Node
## Инструменты строительства: дорога и снос (фаза 3 — зоны).
## Меняет клетки только через CityGrid и шлёт один Events.cells_changed на операцию.

enum Mode { NONE, ROAD, BULLDOZE }

const CURSOR_COLORS: Dictionary[Mode, Color] = {
	Mode.NONE: Color(1.0, 0.85, 0.2, 0.45),
	Mode.ROAD: Color(0.3, 0.6, 1.0, 0.55),
	Mode.BULLDOZE: Color(1.0, 0.3, 0.25, 0.55),
}

@export var cursor: CellCursor
@export var preview: ToolPreview

var mode: Mode = Mode.NONE

var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
## Конечная клетка протягивания (всегда внутри карты).
var _drag_end: Vector2i = Vector2i.ZERO
## Клетки текущей операции (пересчитываются, когда меняется _drag_end).
var _drag_cells: Array[Vector2i] = []


func _ready() -> void:
	cursor.set_color(CURSOR_COLORS[mode])


func _process(_delta: float) -> void:
	if not _dragging or not cursor.has_ground_hit:
		return
	# Мышь за картой — прижимаем конец протягивания к краю.
	var end: Vector2i = GameState.grid.clamp_to_bounds(cursor.ground_cell)
	if end != _drag_end:
		_update_drag(end)


## Начало протягивания — здесь, чтобы клик по UI не начинал стройку.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tool_road"):
		_set_mode(Mode.ROAD)
	elif event.is_action_pressed(&"tool_bulldoze"):
		_set_mode(Mode.BULLDOZE)
	elif event.is_action_pressed(&"tool_cancel"):
		_set_mode(Mode.NONE)

	var button := event as InputEventMouseButton
	if button == null or mode == Mode.NONE:
		return
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and cursor.has_cell:
		_dragging = true
		_drag_start = cursor.hovered_cell
		_update_drag(_drag_start)


## Отпускание и отмена — здесь, чтобы UI не «съел» их и протягивание не залипло.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not _dragging:
		return
	if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_apply()
		_end_drag()
	elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		_end_drag()
		get_viewport().set_input_as_handled()


func _set_mode(new_mode: Mode) -> void:
	# Повторное нажатие той же клавиши не сбрасывает протягивание.
	if new_mode == mode:
		return
	mode = new_mode
	_end_drag()
	cursor.set_color(CURSOR_COLORS[mode])


func _update_drag(end: Vector2i) -> void:
	_drag_end = end
	match mode:
		Mode.ROAD:
			_drag_cells = _l_path(_drag_start, _drag_end)
		Mode.BULLDOZE:
			_drag_cells = _rect_cells(_drag_start, _drag_end)
	preview.show_cells(_drag_cells, CURSOR_COLORS[mode])


func _end_drag() -> void:
	_dragging = false
	_drag_cells.clear()
	preview.clear()


func _apply() -> void:
	var grid: CityGrid = GameState.grid
	var changed: Array[Vector2i] = []
	for cell: Vector2i in _drag_cells:
		var did_change: bool = false
		match mode:
			Mode.ROAD:
				did_change = grid.set_road(cell)
			Mode.BULLDOZE:
				did_change = grid.bulldoze(cell)
		if did_change:
			changed.append(cell)
	if not changed.is_empty():
		Events.cells_changed.emit(changed)


## Путь буквой «Г»: сначала по длинной оси, потом по короткой.
static func _l_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var delta: Vector2i = to - from
	var corner: Vector2i
	if absi(delta.x) >= absi(delta.y):
		corner = Vector2i(to.x, from.y)
	else:
		corner = Vector2i(from.x, to.y)
	var cells: Array[Vector2i] = _line(from, corner)
	var tail: Array[Vector2i] = _line(corner, to)
	tail.remove_at(0)  # угол уже есть в первом отрезке
	cells.append_array(tail)
	return cells


## Прямой отрезок по одной оси, включая оба конца.
static func _line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [from]
	var step: Vector2i = (to - from).sign()
	var cell: Vector2i = from
	while cell != to:
		cell += step
		cells.append(cell)
	return cells


static func _rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x: int in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			cells.append(Vector2i(x, y))
	return cells
