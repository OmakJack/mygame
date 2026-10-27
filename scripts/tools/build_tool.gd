class_name BuildTool
extends Node
## Инструменты строительства: дорога, снос, зоны, постановка служебных зданий.
## Меняет клетки только через CityGrid и шлёт один Events.cells_changed на операцию.
## Платные режимы списывают деньги через Economy и останавливаются, когда денег нет.

enum Mode { NONE, ROAD, BULLDOZE, ZONE_R, ZONE_C, ZONE_I, DEZONE, PLACE }

const CURSOR_COLORS: Dictionary[Mode, Color] = {
	Mode.NONE: Color(1.0, 1.0, 1.0, 0.35),
	Mode.ROAD: Color(1.0, 0.6, 0.2, 0.55),
	Mode.BULLDOZE: Color(1.0, 0.25, 0.25, 0.55),
	Mode.ZONE_R: Color(0.25, 0.8, 0.3, 0.7),
	Mode.ZONE_C: Color(0.25, 0.5, 0.95, 0.7),
	Mode.ZONE_I: Color(0.95, 0.8, 0.2, 0.7),
	Mode.DEZONE: Color(0.75, 0.5, 1.0, 0.55),
	Mode.PLACE: Color(0.85, 0.9, 1.0, 0.6),
}
## Цвет клетки, куда здание поставить нельзя.
const INVALID_COLOR := Color(1.0, 0.15, 0.15, 0.6)

## Какую зону ставит режим (DEZONE ставит NONE, т. е. снимает).
const MODE_ZONES: Dictionary[Mode, CityGrid.Zone] = {
	Mode.ZONE_R: CityGrid.Zone.RESIDENTIAL,
	Mode.ZONE_C: CityGrid.Zone.COMMERCIAL,
	Mode.ZONE_I: CityGrid.Zone.INDUSTRIAL,
	Mode.DEZONE: CityGrid.Zone.NONE,
}

## Цена за реально изменённую клетку. Чего нет в словаре — бесплатно.
const MODE_COSTS: Dictionary[Mode, int] = {
	Mode.ROAD: Economy.ROAD_COST,
	Mode.ZONE_R: Economy.ZONE_COST,
	Mode.ZONE_C: Economy.ZONE_COST,
	Mode.ZONE_I: Economy.ZONE_COST,
}

## Горячие клавиши режимов (действия из project.godot).
const MODE_ACTIONS: Dictionary[StringName, Mode] = {
	&"tool_road": Mode.ROAD,
	&"tool_bulldoze": Mode.BULLDOZE,
	&"tool_zone_r": Mode.ZONE_R,
	&"tool_zone_c": Mode.ZONE_C,
	&"tool_zone_i": Mode.ZONE_I,
	&"tool_dezone": Mode.DEZONE,
	&"tool_cancel": Mode.NONE,
}

@export var cursor: CellCursor
@export var preview: ToolPreview

var mode: Mode = Mode.NONE
## Тип служебного здания для режима PLACE.
var place_type: StringName = &""

var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
## Конечная клетка протягивания (всегда внутри карты).
var _drag_end: Vector2i = Vector2i.ZERO
## Клетки текущей операции (пересчитываются, когда меняется _drag_end).
var _drag_cells: Array[Vector2i] = []


func _ready() -> void:
	cursor.set_color(CURSOR_COLORS[mode])
	Events.tool_requested.connect(func(requested: int) -> void: _set_mode(requested as Mode))
	Events.building_place_requested.connect(func(type_id: StringName) -> void: _set_mode(Mode.PLACE, type_id))
	# Деньги могли измениться на тике, пока мышь стоит, — обновляем превью.
	Events.stats_changed.connect(func() -> void:
		if _dragging:
			_update_drag(_drag_end))
	Events.grid_reset.connect(_end_drag)


static func cost_of(tool_mode: Mode) -> int:
	return MODE_COSTS.get(tool_mode, 0)


## Цена клетки: дорога по воде — мост.
func _cell_cost(cell: Vector2i) -> int:
	if mode == Mode.ROAD and GameState.grid.is_in_bounds(cell) and GameState.grid.is_water(cell):
		return Economy.BRIDGE_COST
	return cost_of(mode)


func _process(_delta: float) -> void:
	# В режиме постановки курсор краснеет там, куда поставить нельзя.
	if mode == Mode.PLACE and cursor.has_cell:
		cursor.set_color(CURSOR_COLORS[mode] if _can_place(cursor.hovered_cell) else INVALID_COLOR)
	if not _dragging or not cursor.has_ground_hit:
		return
	# Мышь за картой — прижимаем конец протягивания к краю.
	var end: Vector2i = GameState.grid.clamp_to_bounds(cursor.ground_cell)
	if end != _drag_end:
		_update_drag(end)


## Начало протягивания — здесь, чтобы клик по UI не начинал стройку.
func _unhandled_input(event: InputEvent) -> void:
	for action: StringName in MODE_ACTIONS:
		if event.is_action_pressed(action):
			_set_mode(MODE_ACTIONS[action])
			break

	var button := event as InputEventMouseButton
	if button == null:
		return
	if mode == Mode.NONE:
		# Без инструмента клик показывает, что на клетке (карточка «Инфо»).
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and cursor.has_cell:
			Events.cell_inspected.emit(cursor.hovered_cell)
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


func _set_mode(new_mode: Mode, type_id: StringName = &"") -> void:
	# Повторное нажатие той же клавиши не сбрасывает протягивание.
	if new_mode == mode and type_id == place_type:
		return
	mode = new_mode
	place_type = type_id
	_end_drag()
	cursor.set_color(CURSOR_COLORS[mode])
	Events.tool_mode_changed.emit(mode, place_type)


func _update_drag(end: Vector2i) -> void:
	_drag_end = end
	match mode:
		Mode.ROAD:
			_drag_cells = _l_path(_drag_start, _drag_end)
		Mode.BULLDOZE:
			_drag_cells = _rect_cells(_drag_start, _drag_end)
		Mode.ZONE_R, Mode.ZONE_C, Mode.ZONE_I, Mode.DEZONE:
			# Показываем только клетки, где зона реально изменится.
			var grid: CityGrid = GameState.grid
			var zone_type: CityGrid.Zone = MODE_ZONES[mode]
			_drag_cells = _rect_cells(_drag_start, _drag_end).filter(
				func(cell: Vector2i) -> bool: return grid.can_zone(cell, zone_type))
		Mode.PLACE:
			# Здание ставится на клетку, где отпустили мышь.
			var valid: bool = _can_place(_drag_end)
			_drag_cells.clear()
			if valid:
				_drag_cells.append(_drag_end)
			var target: Array[Vector2i] = [_drag_end]
			preview.show_cells(target, CURSOR_COLORS[mode] if valid else INVALID_COLOR)
			return
	_drag_cells = _affordable(_drag_cells)
	preview.show_cells(_drag_cells, CURSOR_COLORS[mode])


## Можно ли поставить выбранное служебное здание: пустая клетка, дорога рядом, хватает денег.
func _can_place(cell: Vector2i) -> bool:
	var data: BuildingData = BuildingCatalog.get_type(place_type)
	var grid: CityGrid = GameState.grid
	return data != null and grid.can_place_building(cell) and grid.has_road_access(cell) 			and Economy.can_afford(data.cost)


## Обрезает клетки операции там, где кончаются деньги. Клетки, которые не изменятся
## (например, уже есть дорога), бесплатны и не обрезаются.
func _affordable(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cost_of(mode) == 0:
		return cells
	var budget: int = GameState.money
	var result: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if _would_change(cell):
			var cost: int = _cell_cost(cell)
			if budget < cost:
				break
			budget -= cost
		result.append(cell)
	return result


func _would_change(cell: Vector2i) -> bool:
	var grid: CityGrid = GameState.grid
	match mode:
		Mode.ROAD:
			return grid.can_set_road(cell)
		Mode.ZONE_R, Mode.ZONE_C, Mode.ZONE_I, Mode.DEZONE:
			return grid.can_zone(cell, MODE_ZONES[mode])
	return true


func _end_drag() -> void:
	_dragging = false
	_drag_cells.clear()
	preview.clear()


func _apply() -> void:
	var grid: CityGrid = GameState.grid
	if mode == Mode.PLACE:
		_apply_place(grid)
		return
	var changed: Array[Vector2i] = []
	for cell: Vector2i in _drag_cells:
		var cost: int = _cell_cost(cell)
		# Деньги могли измениться с момента превью — проверяем ещё раз.
		if cost > 0 and _would_change(cell) and not Economy.can_afford(cost):
			break
		var did_change: bool = false
		match mode:
			Mode.ROAD:
				did_change = grid.set_road(cell)
			Mode.BULLDOZE:
				did_change = grid.bulldoze(cell)
			Mode.ZONE_R, Mode.ZONE_C, Mode.ZONE_I, Mode.DEZONE:
				did_change = grid.set_zone(cell, MODE_ZONES[mode])
		if did_change:
			Economy.spend(cost)
			changed.append(cell)
	if not changed.is_empty():
		Events.cells_changed.emit(changed)


## Ставит служебное здание: стирает зону клетки, фасад к дороге, списывает цену.
func _apply_place(grid: CityGrid) -> void:
	# Одно здание ставим только туда, где виден курсор: отпускание над панелью UI — отмена.
	if not cursor.has_cell or _drag_cells.is_empty() or not _can_place(_drag_cells[0]):
		return
	var cell: Vector2i = _drag_cells[0]
	var data: BuildingData = BuildingCatalog.get_type(place_type)
	Economy.spend(data.cost)
	grid.place_building(data.id, cell, grid.find_nearest_road_dir(cell), true)
	var changed: Array[Vector2i] = [cell]
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
