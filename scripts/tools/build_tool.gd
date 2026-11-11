class_name BuildTool
extends Node
## Инструменты строительства: дорога, снос, зоны, постановка служебных зданий.
## Меняет клетки только через CityGrid и шлёт один Events.cells_changed на операцию.
## Платные режимы списывают деньги через Economy и останавливаются, когда денег нет.
## У свободных дорог (диагональ, дуга) игрок работает не с клетками карты, а с ячейками полосы
## (FreeStrips): зона красится по ячейкам — начал с ячейки и тянешь вдоль дороги (прямоугольник
## «колонки × ряды» изгибается с дорогой и идёт через узлы на следующие отрезки той же стороны),
## начал с клетки — прямоугольник карты берёт и ячейки внутри;
## служба встаёт под углом дороги; снос и «Инфо» находят дом под углом по его участку.
## Бульдозер сносит свободную дорогу целым отрезком, от узла до узла (как в Cities: Skylines): под мышью
## её полотно подсвечено. Дорога по сетке сносится клетками, как раньше, — из неё можно вырезать кусок.

## Новые режимы — только в конец (номера режимов шлёт HUD через Events.tool_requested).
enum Mode { NONE, ROAD, BULLDOZE, ZONE_R, ZONE_C, ZONE_I, DEZONE, PLACE, ZONE_R_HIGH, ZONE_C_HIGH, ZONE_O,
		ROAD_AVENUE, ROAD_HIGHWAY }

const CURSOR_COLORS: Dictionary[Mode, Color] = {
	Mode.NONE: Color(1.0, 1.0, 1.0, 0.35),
	Mode.ROAD: Color(1.0, 0.6, 0.2, 0.55),
	Mode.BULLDOZE: Color(1.0, 0.25, 0.25, 0.55),
	Mode.ZONE_R: Color(0.25, 0.8, 0.3, 0.7),
	Mode.ZONE_C: Color(0.25, 0.5, 0.95, 0.7),
	Mode.ZONE_I: Color(0.95, 0.8, 0.2, 0.7),
	Mode.DEZONE: Color(0.75, 0.5, 1.0, 0.55),
	Mode.PLACE: Color(0.85, 0.9, 1.0, 0.6),
	Mode.ZONE_R_HIGH: Color(0.1, 0.6, 0.25, 0.75),
	Mode.ZONE_C_HIGH: Color(0.15, 0.3, 0.85, 0.75),
	Mode.ZONE_O: Color(0.6, 0.35, 0.9, 0.75),
	Mode.ROAD_AVENUE: Color(1.0, 0.45, 0.15, 0.6),
	Mode.ROAD_HIGHWAY: Color(0.95, 0.3, 0.1, 0.65),
}

## Какой тип дороги кладёт режим (фаза 11). Поверх дороги другого типа — замена типа.
const MODE_ROADS: Dictionary[Mode, int] = {
	Mode.ROAD: RoadTypes.Type.STREET,
	Mode.ROAD_AVENUE: RoadTypes.Type.AVENUE,
	Mode.ROAD_HIGHWAY: RoadTypes.Type.HIGHWAY,
}
## Цвет клетки, куда здание поставить нельзя.
const INVALID_COLOR := Color(1.0, 0.15, 0.15, 0.6)
## Здание по клеткам не встаёт, если середина клетки ближе к краю полотна кривой дороги, м
## (у дороги по сетке середина соседней клетки — в 1 м от края улицы и в 0.8 м от края проспекта).
const RIBBON_CLEARANCE: float = 0.6

## Какую зону ставит режим (DEZONE ставит NONE, т. е. снимает).
const MODE_ZONES: Dictionary[Mode, CityGrid.Zone] = {
	Mode.ZONE_R: CityGrid.Zone.RESIDENTIAL,
	Mode.ZONE_C: CityGrid.Zone.COMMERCIAL,
	Mode.ZONE_I: CityGrid.Zone.INDUSTRIAL,
	Mode.DEZONE: CityGrid.Zone.NONE,
	Mode.ZONE_R_HIGH: CityGrid.Zone.RESIDENTIAL_HIGH,
	Mode.ZONE_C_HIGH: CityGrid.Zone.COMMERCIAL_HIGH,
	Mode.ZONE_O: CityGrid.Zone.OFFICE,
}

## Цена за реально изменённую клетку. Чего нет в словаре — бесплатно.
const MODE_COSTS: Dictionary[Mode, int] = {
	Mode.ROAD: RoadTypes.BUILD_COST[RoadTypes.Type.STREET],
	Mode.ROAD_AVENUE: RoadTypes.BUILD_COST[RoadTypes.Type.AVENUE],
	Mode.ROAD_HIGHWAY: RoadTypes.BUILD_COST[RoadTypes.Type.HIGHWAY],
	Mode.ZONE_R: Economy.ZONE_COST,
	Mode.ZONE_C: Economy.ZONE_COST,
	Mode.ZONE_I: Economy.ZONE_COST,
	Mode.ZONE_R_HIGH: Economy.ZONE_COST,
	Mode.ZONE_C_HIGH: Economy.ZONE_COST,
	Mode.ZONE_O: Economy.ZONE_COST,
}

## Горячие клавиши режимов (действия из project.godot).
const MODE_ACTIONS: Dictionary[StringName, Mode] = {
	&"tool_road": Mode.ROAD,
	&"tool_road_avenue": Mode.ROAD_AVENUE,
	&"tool_road_highway": Mode.ROAD_HIGHWAY,
	&"tool_bulldoze": Mode.BULLDOZE,
	&"tool_zone_r": Mode.ZONE_R,
	&"tool_zone_c": Mode.ZONE_C,
	&"tool_zone_i": Mode.ZONE_I,
	&"tool_dezone": Mode.DEZONE,
	&"tool_zone_rh": Mode.ZONE_R_HIGH,
	&"tool_zone_ch": Mode.ZONE_C_HIGH,
	&"tool_zone_o": Mode.ZONE_O,
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
## Зона вдоль свободной дороги: с какой ячейки начали — [отрезок, сторона, колонка, ряд]; пусто —
## протягивание прямоугольником клеток.
var _drag_anchor: Array[int] = []
## Полоса под мышью (отрезок, сторона) — своя или дальше по той же дороге — и колонка с рядом на ней.
var _drag_strip := Vector2i.ZERO
var _drag_coords := Vector2i.ZERO
## Ячейки свободных полос текущей операции (зоны).
var _drag_slots: Array[FreeStrips.Slot] = []
## Свободные отрезки дорог текущей операции (снос — целиком).
var _drag_segments: Array[int] = []
## Бульдозер без нажатия: отрезок под мышью (его полотно подсвечено) или −1, и версия графа подсветки.
var _hover_segment: int = -1
var _hover_version: int = -1


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


## Цена клетки: дорога по воде — мост (дороже на разницу мост − улица).
func _cell_cost(cell: Vector2i) -> int:
	if MODE_ROADS.has(mode) and GameState.grid.is_in_bounds(cell) and GameState.grid.is_water(cell):
		return cost_of(mode) + Economy.BRIDGE_COST - RoadTypes.BUILD_COST[RoadTypes.Type.STREET]
	return cost_of(mode)


func _process(_delta: float) -> void:
	# В режиме постановки курсор краснеет там, куда поставить нельзя.
	if mode == Mode.PLACE and cursor.has_cell:
		cursor.set_color(CURSOR_COLORS[mode] if _can_place(cursor.hovered_cell) else INVALID_COLOR)
	if mode == Mode.BULLDOZE and not _dragging:
		_hover_road()
	if not _dragging or not cursor.has_ground_hit:
		return
	# Мышь за картой — прижимаем конец протягивания к краю.
	var end: Vector2i = GameState.grid.clamp_to_bounds(cursor.ground_cell)
	var moved: bool = end != _drag_end
	if not _drag_anchor.is_empty():
		# Вдоль свободной дороги — по ячейке под мышью: на своей полосе или дальше по той же стороне
		# дороги; мышь ушла с полос — колонка и ряд последней полосы, ближайшие к мыши.
		var over: FreeStrips.Slot = cursor.hovered_slot
		var strip: Vector2i = _drag_strip
		var coords: Vector2i
		if over != null and not _chain_to(over.segment, over.side).is_empty():
			strip = Vector2i(over.segment, over.side)
			coords = Vector2i(over.col, over.row)
		else:
			coords = GameState.grid.free_strips.coords_at(strip.x, strip.y,
					Vector2(cursor.ground_point.x, cursor.ground_point.z))
		moved = moved or strip != _drag_strip or coords != _drag_coords
		_drag_strip = strip
		_drag_coords = coords
	if moved:
		_update_drag(end)


## Свободный отрезок дороги под точкой мира, который можно снести, или −1 (не дорога, дорога по сетке —
## та сносится клетками, трасса у въезда).
func _free_segment_at(point: Vector2) -> int:
	var grid: CityGrid = GameState.grid
	var graph: RoadGraph = grid.roads
	graph.sync(grid)
	var id: int = graph.segment_at(point)
	if id == -1 or not FreeStrips.is_free(graph, graph.segments[id]) or graph.is_locked(grid, id):
		return -1
	return id


## Бульдозер над свободной дорогой: подсветка всего отрезка вместо клетки.
func _hover_road() -> void:
	var id: int = -1
	if cursor.has_cell and cursor.has_ground_hit:
		id = _free_segment_at(Vector2(cursor.ground_point.x, cursor.ground_point.z))
	var version: int = GameState.grid.roads.version
	if id == _hover_segment and version == _hover_version:
		return
	_hover_segment = id
	_hover_version = version
	cursor.suppressed = id != -1
	if id == -1:
		preview.clear()
	else:
		preview.show_selection([], [], CURSOR_COLORS[mode], GameState.grid.roads.ribbon_quads(id))


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
			Events.cell_inspected.emit(_inspect_cell())
		return
	# Дороги мышью строит RoadTool (по точкам, как в Cities: Skylines). Протягивание по клеткам
	# (_update_drag / _apply) осталось для тестов и сценариев.
	if MODE_ROADS.has(mode):
		return
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and cursor.has_cell:
		_dragging = true
		_drag_start = cursor.hovered_cell
		_drag_anchor.clear()
		# Зону начали с ячейки свободной полосы — тянем вдоль дороги.
		var slot: FreeStrips.Slot = cursor.hovered_slot
		if MODE_ZONES.has(mode) and slot != null:
			_drag_anchor = [slot.segment, slot.side, slot.col, slot.row]
			_drag_strip = Vector2i(slot.segment, slot.side)
			_drag_coords = Vector2i(slot.col, slot.row)
		_update_drag(_drag_start)


## Клетка для карточки «Инфо»: под мышью; над участком дома под углом дороги — клетка этого участка
## (центр клетки под мышью может лежать уже у соседа).
func _inspect_cell() -> Vector2i:
	var slot: FreeStrips.Slot = cursor.hovered_slot
	var lot: CityGrid.Lot = _lot_of_slot(slot)
	if lot != null:
		return lot.shape[0]
	# Пустая ячейка — её клетка: зона и причины «почему не строят» — те же.
	if slot != null and not slot.cells.is_empty():
		return slot.cells[0]
	return cursor.hovered_cell


## Участок, занявший ячейку свободной полосы, или null.
func _lot_of_slot(slot: FreeStrips.Slot) -> CityGrid.Lot:
	if slot == null:
		return null
	var grid: CityGrid = GameState.grid
	return grid.lots.get(grid.free_strips.occupied.get(slot.id, -1))


## Путь вдоль дороги от полосы начала (_drag_anchor) до полосы (segment, side): [[отрезок, сторона,
## вперёд ли], …]. Сторона — та же по ходу движения: слева осталось слева. Пусто — не та сторона
## дороги или отрезки не связаны.
func _chain_to(segment: int, side: int) -> Array[Array]:
	var none: Array[Array] = []
	if _drag_anchor.is_empty():
		return none
	var path: Array[Array] = GameState.grid.free_strips.chain(_drag_anchor[0], segment)
	if path.is_empty():
		return none
	# Сторона по ходу: у отрезка, пройденного от b к a, она с обратным знаком.
	var travel: int = _drag_anchor[1] * (1 if path[0][1] else -1)
	var result: Array[Array] = []
	for step: Array in path:
		result.append([step[0], travel * (1 if step[1] else -1), step[1]])
	return result if result.back()[1] == side else none


## Ячейки зоны под протягивание: вдоль дороги от ячейки начала (_drag_anchor) до колонки и ряда под
## мышью (_drag_strip, _drag_coords) — через узлы по той же стороне дороги; а если начали с клетки —
## все ячейки с серединой в прямоугольнике клеток.
func _zone_slots(zone_type: CityGrid.Zone) -> Array[FreeStrips.Slot]:
	var grid: CityGrid = GameState.grid
	grid.ensure_strips()
	var strips: FreeStrips = grid.free_strips
	var result: Array[FreeStrips.Slot] = []
	if not _drag_anchor.is_empty():
		var path: Array[Array] = _chain_to(_drag_strip.x, _drag_strip.y)
		var row_from: int = mini(_drag_anchor[3], _drag_coords.y)
		var row_to: int = maxi(_drag_anchor[3], _drag_coords.y)
		for k: int in path.size():
			var frame: FreeStrips.Frame = strips.frames.get(path[k][0])
			if frame == null or frame.count == 0:
				continue
			var forward: bool = path[k][2]
			var col_from: int = 0
			var col_to: int = frame.count - 1
			if path.size() == 1:
				col_from = mini(_drag_anchor[2], _drag_coords.x)
				col_to = maxi(_drag_anchor[2], _drag_coords.x)
			elif k == 0:
				# От ячейки начала — до конца отрезка, куда ушли.
				if forward:
					col_from = _drag_anchor[2]
				else:
					col_to = _drag_anchor[2]
			elif k == path.size() - 1:
				# От узла, откуда пришли, — до ячейки под мышью.
				if forward:
					col_to = _drag_coords.x
				else:
					col_from = _drag_coords.x
			for col: int in range(col_from, col_to + 1):
				for row: int in range(row_from, row_to + 1):
					var slot: FreeStrips.Slot = strips.slot_in(path[k][0], path[k][1], col, row)
					if slot != null and grid.can_zone_slot(slot, zone_type):
						result.append(slot)
		return result
	for slot: FreeStrips.Slot in strips.slots_in(_drag_rect()):
		if grid.can_zone_slot(slot, zone_type):
			result.append(slot)
	return result


## Прямоугольник протягивания в мире (x, z).
func _drag_rect() -> Rect2:
	var from: Vector2i = _drag_start.min(_drag_end)
	var to: Vector2i = _drag_start.max(_drag_end)
	return Rect2(Vector2(from) * CityGrid.CELL_SIZE, Vector2(to - from + Vector2i.ONE) * CityGrid.CELL_SIZE)


## Углы ячеек — для превью.
static func _quads_of(slots: Array[FreeStrips.Slot]) -> Array[PackedVector2Array]:
	var quads: Array[PackedVector2Array] = []
	for slot: FreeStrips.Slot in slots:
		quads.append(slot.corners)
	return quads


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


## Закрыт ли режим званием города (фаза 10): высокая плотность — с «городка», офисы — с «города».
static func is_locked(tool_mode: Mode) -> bool:
	if MODE_ROADS.has(tool_mode):
		return not RoadTypes.is_unlocked(MODE_ROADS[tool_mode], GameState.rank)
	return MODE_ZONES.has(tool_mode) and not Ranks.is_unlocked(MODE_ZONES[tool_mode], GameState.rank)


func _set_mode(new_mode: Mode, type_id: StringName = &"") -> void:
	if is_locked(new_mode):
		return
	# Повторное нажатие той же клавиши не сбрасывает протягивание.
	if new_mode == mode and type_id == place_type:
		return
	if mode == Mode.BULLDOZE:
		cursor.suppressed = false
	mode = new_mode
	place_type = type_id
	_end_drag()
	cursor.set_color(CURSOR_COLORS[mode])
	Events.tool_mode_changed.emit(mode, place_type)


func _update_drag(end: Vector2i) -> void:
	_drag_end = end
	_drag_slots.clear()
	_drag_segments.clear()
	var quads: Array[PackedVector2Array] = []
	var ribbon: Array[PackedVector2Array] = []
	match mode:
		Mode.ROAD, Mode.ROAD_AVENUE, Mode.ROAD_HIGHWAY:
			_drag_cells = _l_path(_drag_start, _drag_end)
		Mode.BULLDOZE:
			var grid: CityGrid = GameState.grid
			grid.ensure_strips()
			# Свободные дороги — целыми отрезками: тот, что под мышью, и те, чьи клетки в прямоугольнике.
			# Их клетки уйдут вместе с отрезком.
			var graph: RoadGraph = grid.roads
			var taken: Dictionary[int, bool] = {}
			var pointed: int = -1
			if cursor.has_cell and cursor.has_ground_hit and cursor.hovered_cell == _drag_end:
				pointed = _free_segment_at(Vector2(cursor.ground_point.x, cursor.ground_point.z))
			if pointed != -1:
				taken[pointed] = true
			# Щелчок по полотну — это дорога, а не клетка или участок, чья середина рядом.
			var road_click: bool = pointed != -1 and _drag_start == _drag_end
			_drag_cells.clear()
			for cell: Vector2i in _rect_cells(_drag_start, _drag_end):
				var owners: Array[int] = graph.owners_of(cell) if grid.is_road(cell) else ([] as Array[int])
				var free_only: bool = not owners.is_empty()
				for id: int in owners:
					free_only = free_only and FreeStrips.is_free(graph, graph.segments[id])
				if free_only:
					for id: int in owners:
						if not graph.is_locked(grid, id):
							taken[id] = true
				elif not road_click:
					_drag_cells.append(cell)
			_drag_segments.assign(taken.keys())
			for id: int in _drag_segments:
				ribbon.append_array(graph.ribbon_quads(id))
			# Дома под углом дороги — по участкам: ячейки в прямоугольнике и ячейка под мышью.
			var hit: Array[FreeStrips.Slot] = []
			if not road_click:
				hit = grid.free_strips.slots_in(_drag_rect())
			if cursor.hovered_slot != null and cursor.has_cell and cursor.hovered_cell == _drag_end:
				hit.append(cursor.hovered_slot)
			var lots: Dictionary[int, bool] = {}
			for slot: FreeStrips.Slot in hit:
				var lot: CityGrid.Lot = _lot_of_slot(slot)
				if lot == null or lots.has(lot.id):
					continue
				lots[lot.id] = true
				quads.append(lot.poly)
				if not _drag_cells.has(lot.shape[0]):
					_drag_cells.append(lot.shape[0])
		Mode.ZONE_R, Mode.ZONE_C, Mode.ZONE_I, Mode.DEZONE, Mode.ZONE_R_HIGH, Mode.ZONE_C_HIGH, Mode.ZONE_O:
			# Показываем только клетки и ячейки, где зона реально изменится.
			var grid: CityGrid = GameState.grid
			var zone_type: CityGrid.Zone = MODE_ZONES[mode]
			_drag_cells.clear()
			if _drag_anchor.is_empty():
				# Красить можно только полосу у дороги (CityGrid.in_strip) — остальное отсеивает can_zone.
				# Клетки свободных полос идут ячейками.
				_drag_cells = _rect_cells(_drag_start, _drag_end).filter(
					func(cell: Vector2i) -> bool: return grid.free_slot(cell) == null and grid.can_zone(cell, zone_type))
			_drag_slots = _zone_slots(zone_type)
		Mode.PLACE:
			# Здание ставится на участок с углом в клетке, где отпустили мышь.
			var valid: bool = _can_place(_drag_end)
			var plan: Dictionary = _free_place(_drag_end)
			var target: Array[Vector2i] = _place_cells(_drag_end) if plan.is_empty() else ([] as Array[Vector2i])
			if not plan.is_empty():
				quads.append(plan.corners)
			_drag_cells.clear()
			if valid:
				_drag_cells.append(_drag_end)
			preview.show_selection(target, quads, CURSOR_COLORS[mode] if valid else INVALID_COLOR)
			return
	_trim_to_budget()
	quads.append_array(_quads_of(_drag_slots))
	preview.show_selection(_drag_cells, quads, CURSOR_COLORS[mode], ribbon)


## Можно ли поставить выбранное служебное здание: пустой участок, дорога рядом, хватает денег.
## У свободной дороги — на ячейки её полосы под углом дороги (_free_place).
func _can_place(cell: Vector2i) -> bool:
	var data: BuildingData = BuildingCatalog.get_type(place_type)
	if data == null or not Economy.can_afford(data.cost):
		return false
	var plan: Dictionary = _free_place(cell)
	if not plan.is_empty():
		return plan.ok
	var grid: CityGrid = GameState.grid
	var dir: int = maxi(0, grid.find_nearest_road_dir(cell))
	var span: Vector2i = data.footprint(dir)
	if not grid.can_place_building(cell, span):
		return false
	var access: bool = false
	for dy: int in span.y:
		for dx: int in span.x:
			var c := Vector2i(cell.x + dx, cell.y + dy)
			# Клетку может задевать полотно кривой дороги, хотя клетка — не дорога.
			if grid.roads.on_ribbon(RoadGraph.cell_center(c), RIBBON_CLEARANCE):
				return false
			access = access or grid.has_road_access(c)
	return access


## Служба у свободной дороги: под мышью (или у клетки cell) — ячейка полосы. Здание встаёт на колонки
## от этой ячейки под углом дороги, фасадом к ней. Пусто — здесь не свободная полоса (ставим по клеткам).
## {ok, corners — прямоугольник здания, center, yaw, dir, cells — клетки под зданием, lot — клетки участка,
## poly — углы участка, slots — его ячейки}.
func _free_place(cell: Vector2i) -> Dictionary:
	var data: BuildingData = BuildingCatalog.get_type(place_type)
	var grid: CityGrid = GameState.grid
	var slot: FreeStrips.Slot = cursor.hovered_slot if cursor.has_cell and cursor.hovered_cell == cell else null
	if slot == null:
		slot = grid.free_slot(cell)
	if data == null or slot == null:
		return {}
	var strips: FreeStrips = grid.free_strips
	var count: int = strips.frames[slot.segment].count
	var best: Dictionary = {}
	# На внутренней стороне дуги здание в свои колонки не влезает — участок на колонку-две шире
	# (станция 4×3 — на две).
	for extra: int in [0, 1, 2]:
		var columns: int = data.size.x + extra
		var col: int = clampi(slot.col - (columns - 1) / 2, 0, maxi(0, count - columns))
		var pose: Dictionary = strips.house_pose(slot.segment, slot.side, col, columns,
				data.size.x * CityGrid.CELL_SIZE, data.size.y * CityGrid.CELL_SIZE)
		var plan: Dictionary = {"ok": pose.ok and columns <= count, "corners": pose.corners, "center": pose.center,
				"yaw": pose.yaw, "dir": CityGrid._dir_of_vector(slot.front), "slots": [], "lot": [] as Array[Vector2i],
				"cells": [] as Array[Vector2i],
				"poly": strips.lot_shape(slot.segment, slot.side, col, columns, data.size.y).corners}
		for c: int in range(col, col + columns):
			for row: int in range(1, data.size.y + 1):
				var part: FreeStrips.Slot = strips.slot_in(slot.segment, slot.side, c, row)
				if part == null or strips.occupied.has(part.id):
					plan.ok = false
					continue
				plan.slots.append(part)
				for own: Vector2i in part.cells:
					if grid.tile_type[grid.index_of(own)] != CityGrid.Tile.EMPTY:
						plan.ok = false
					plan.lot.append(own)
		var under: PackedVector2Array = Geometry2D.offset_polygon(pose.corners, Growth.HOUSE_CELL_MARGIN)[0]
		for own: Vector2i in plan.lot:
			if Geometry2D.is_point_in_polygon(RoadGraph.cell_center(own), under):
				plan.cells.append(own)
		if plan.cells.is_empty():
			# Под зданием нет ни одной клетки (ячейки диагонали бывают без клеток) — берём ближайшую
			# свободную клетку соседних ячеек: без клетки здания для сетки нет.
			var spare: Vector2i = _spare_cell(slot.segment, slot.side, col, columns, data.size.y, pose.center)
			if spare == CityGrid.NO_CELL:
				plan.ok = false
			else:
				plan.cells.append(spare)
				if not plan.lot.has(spare):
					plan.lot.append(spare)
		if best.is_empty() or plan.ok:
			best = plan
		if plan.ok:
			break
	return best


## Ближайшая к center свободная клетка (пусто, без участка) в ячейках колонок [col − 1, col + columns]
## и рядов 1..rows + 1 полосы; NO_CELL — нет.
func _spare_cell(segment: int, side: int, col: int, columns: int, rows: int, center: Vector2) -> Vector2i:
	var grid: CityGrid = GameState.grid
	var best: Vector2i = CityGrid.NO_CELL
	var best_d: float = INF
	for c: int in range(col - 1, col + columns + 1):
		for row: int in range(1, rows + 2):
			var slot: FreeStrips.Slot = grid.free_strips.slot_in(segment, side, c, row)
			if slot == null or grid.free_strips.occupied.has(slot.id):
				continue
			for cell: Vector2i in slot.cells:
				var d: float = RoadGraph.cell_center(cell).distance_squared_to(center)
				if d < best_d and grid.tile_type[grid.index_of(cell)] == CityGrid.Tile.EMPTY and grid.get_lot(cell) == null:
					best_d = d
					best = cell
	return best


func _place_cells(cell: Vector2i) -> Array[Vector2i]:
	var data: BuildingData = BuildingCatalog.get_type(place_type)
	var grid: CityGrid = GameState.grid
	var dir: int = maxi(0, grid.find_nearest_road_dir(cell))
	var span: Vector2i = data.footprint(dir) if data != null else Vector2i.ONE
	var result: Array[Vector2i] = []
	for dy: int in span.y:
		for dx: int in span.x:
			var c := Vector2i(cell.x + dx, cell.y + dy)
			if grid.is_in_bounds(c):
				result.append(c)
	return result


## Обрезает клетки и ячейки операции там, где кончаются деньги. Клетки, которые не изменятся
## (например, уже есть дорога), бесплатны и не обрезаются. Ячейка зоны стоит как клетка.
func _trim_to_budget() -> void:
	if cost_of(mode) == 0:
		return
	var budget: int = GameState.money
	var cells: Array[Vector2i] = []
	var enough: bool = true
	for cell: Vector2i in _drag_cells:
		if _would_change(cell):
			var cost: int = _cell_cost(cell)
			if budget < cost:
				enough = false
				break
			budget -= cost
		cells.append(cell)
	_drag_cells = cells
	var slots: Array[FreeStrips.Slot] = []
	for slot: FreeStrips.Slot in _drag_slots:
		if not enough or budget < cost_of(mode):
			break
		budget -= cost_of(mode)
		slots.append(slot)
	_drag_slots = slots


func _would_change(cell: Vector2i) -> bool:
	var grid: CityGrid = GameState.grid
	match mode:
		Mode.ROAD, Mode.ROAD_AVENUE, Mode.ROAD_HIGHWAY:
			return grid.can_build_road(cell, MODE_ROADS[mode])
		Mode.ZONE_R, Mode.ZONE_C, Mode.ZONE_I, Mode.DEZONE, Mode.ZONE_R_HIGH, Mode.ZONE_C_HIGH, Mode.ZONE_O:
			return grid.can_zone(cell, MODE_ZONES[mode])
	return true


func _end_drag() -> void:
	_dragging = false
	_drag_cells.clear()
	_drag_slots.clear()
	_drag_segments.clear()
	_drag_anchor.clear()
	_hover_segment = -1
	_hover_version = -1
	preview.clear()


func _apply() -> void:
	var grid: CityGrid = GameState.grid
	if mode == Mode.PLACE:
		_apply_place(grid)
		return
	var changed: Array[Vector2i] = []
	# Свободные дороги — целыми отрезками; до клеток: снос клетки перекрёстка режет отрезки и меняет номера.
	if mode == Mode.BULLDOZE and not _drag_segments.is_empty():
		changed.append_array(grid.roads.remove_segments(grid, _drag_segments))
	for cell: Vector2i in _drag_cells:
		var cost: int = _cell_cost(cell)
		# Деньги могли измениться с момента превью — проверяем ещё раз.
		if cost > 0 and _would_change(cell) and not Economy.can_afford(cost):
			break
		var did_change: bool = false
		var freed_cells: Array[Vector2i] = []
		match mode:
			Mode.ROAD, Mode.ROAD_AVENUE, Mode.ROAD_HIGHWAY:
				did_change = grid.set_road(cell, MODE_ROADS[mode])
			Mode.BULLDOZE:
				# Клик по двору сносит дом участка — перерисовать надо и дом, и двор.
				var existing: BuildingInstance = grid.get_building_or_yard(cell)
				if existing != null:
					freed_cells = existing.cells()
					var lot: CityGrid.Lot = grid.lot_of(existing)
					if lot != null:
						freed_cells.append_array(lot.cells())
				did_change = grid.bulldoze(cell)
			Mode.ZONE_R, Mode.ZONE_C, Mode.ZONE_I, Mode.DEZONE, Mode.ZONE_R_HIGH, Mode.ZONE_C_HIGH, Mode.ZONE_O:
				did_change = grid.set_zone(cell, MODE_ZONES[mode])
		if did_change:
			Economy.spend(cost)
			if not freed_cells.is_empty():
				changed.append_array(freed_cells)
			else:
				changed.append(cell)
	# Зоны ячеек свободных полос.
	if MODE_ZONES.has(mode):
		var strips: FreeStrips = grid.free_strips
		for slot: FreeStrips.Slot in _drag_slots:
			if cost_of(mode) > 0 and not Economy.can_afford(cost_of(mode)):
				break
			# Ячейка могла устареть, если полосы пересобрались с момента превью.
			if slot.id >= strips.slots.size() or strips.slots[slot.id] != slot:
				continue
			if grid.set_slot_zone(slot, MODE_ZONES[mode]):
				Economy.spend(cost_of(mode))
				changed.append_array(grid.slot_redraw_cells(slot))
	if not changed.is_empty():
		Events.cells_changed.emit(changed)


## Ставит служебное здание: стирает зону участка, фасад к дороге, списывает цену.
func _apply_place(grid: CityGrid) -> void:
	# Одно здание ставим только туда, где виден курсор: отпускание над панелью UI — отмена.
	if not cursor.has_cell or _drag_cells.is_empty() or not _can_place(_drag_cells[0]):
		return
	var cell: Vector2i = _drag_cells[0]
	var data: BuildingData = BuildingCatalog.get_type(place_type)
	var plan: Dictionary = _free_place(cell)
	if not plan.is_empty():
		_apply_free_place(grid, data, plan)
		return
	var dir: int = maxi(0, grid.find_nearest_road_dir(cell))
	Economy.spend(data.cost)
	var id: int = grid.place_building(data.id, cell, dir, true)
	if id != -1:
		Events.cells_changed.emit(grid.buildings[id].cells())


## Служба у свободной дороги — под углом дороги: зона её ячеек снимается, ячейки занимает участок здания.
func _apply_free_place(grid: CityGrid, data: BuildingData, plan: Dictionary) -> void:
	var changed: Array[Vector2i] = []
	for slot: FreeStrips.Slot in plan.slots:
		grid.set_slot_zone(slot, CityGrid.Zone.NONE)
		changed.append_array(grid.slot_redraw_cells(slot))
	var id: int = grid.place_free_building(data.id, plan.cells, plan.center, plan.yaw, plan.dir, true)
	if id == -1:
		return
	Economy.spend(data.cost)
	grid.add_free_lot(plan.lot, plan.poly, plan.dir)
	changed.append_array(plan.lot)
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
