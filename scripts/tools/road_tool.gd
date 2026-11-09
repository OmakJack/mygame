class_name RoadTool
extends Node3D
## Строительство дорог как в Cities: Skylines (этап C1, 2026-11-09). Работает в режимах дорог BuildTool.
## Щелчок — начало, щелчок — конец: дорога строится, и цепочка тянется дальше от её конца; ПКМ —
## оборвать цепочку. Формы (Tab — следующая): прямая; дуга — начало, изгиб, конец; плавная — каждый
## кусок продолжает предыдущий по касательной; замена — щелчок по дороге меняет её тип на выбранный.
## Привязка: к узлам и к дорогам (примыкание делит дорогу), к центрам клеток (G — вкл./выкл.);
## без сетки направление липнет к шагу 15°. Перед щелчком видно полотно будущей дороги, длину
## и цену — или красным, почему нельзя (RoadGraph.plan).

enum Shape { STRAIGHT, CURVE, FREE, UPGRADE }

const SHAPE_NAMES: Array[String] = ["Прямая", "Дуга", "Плавная", "Замена"]
## Привязка к узлу, к дороге и к центру клетки на дороге, м.
const SNAP_NODE: float = 1.4
const SNAP_SEGMENT: float = 1.2
const SNAP_CENTER: float = 0.35
## Без сетки: направление липнет к шагу ANGLE_STEP, если ближе ANGLE_SNAP, градусы.
const ANGLE_STEP: float = 15.0
const ANGLE_SNAP: float = 4.0
const OK_COLOR := Color(0.45, 0.78, 1.0, 0.55)
const BAD_COLOR := Color(1.0, 0.3, 0.25, 0.55)
const UPGRADE_COLOR := Color(0.55, 1.0, 0.5, 0.5)
## Превью — чуть выше настоящих дорог.
const PREVIEW_LIFT: float = 0.03

@export var cursor: CellCursor

var shape: Shape = Shape.STRAIGHT
var grid_snap: bool = true
## Тип дороги текущего режима; 0 — инструмент выключен.
var road_type: int = 0
## Начало следующего куска (null — цепочки нет), изгиб дуги, направление конца прошлого куска.
var _start: RoadGraph.RoadPoint = null
var _control: Variant = null
var _prev_dir := Vector2.ZERO
var _hover: RoadGraph.RoadPoint = null
var _plan: RoadGraph.Plan = null
var _upgrade_id: int = -1
var _preview := MeshInstance3D.new()
var _preview_key: int = 0
var _preview_material := StandardMaterial3D.new()
var _marker := MeshInstance3D.new()
var _start_marker := MeshInstance3D.new()
var _label := Label3D.new()


func _ready() -> void:
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview.material_override = _preview_material
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.position.y = PREVIEW_LIFT
	add_child(_preview)
	for marker: MeshInstance3D in [_marker, _start_marker]:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.35
		disc.bottom_radius = 0.35
		disc.height = 0.03
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.9) if marker == _marker else Color(0.45, 0.78, 1.0, 0.95)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.material = material
		marker.mesh = disc
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 30
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.render_priority = 10
	add_child(_label)
	Events.tool_mode_changed.connect(_on_tool_mode_changed)
	Events.road_shape_requested.connect(func(requested: int) -> void: set_shape(requested as Shape))
	Events.road_grid_snap_requested.connect(set_grid_snap)
	Events.grid_reset.connect(reset_chain)
	_hide_all()


func _on_tool_mode_changed(mode: int, _type_id: StringName) -> void:
	road_type = BuildTool.MODE_ROADS.get(mode, 0)
	cursor.suppressed = road_type != 0
	reset_chain()


func set_shape(new_shape: Shape) -> void:
	shape = new_shape
	reset_chain()
	Events.road_tool_changed.emit(shape, grid_snap)


func set_grid_snap(enabled: bool) -> void:
	grid_snap = enabled
	Events.road_tool_changed.emit(shape, grid_snap)


func reset_chain() -> void:
	_start = null
	_control = null
	_prev_dir = Vector2.ZERO
	_plan = null
	_hide_all()


func _hide_all() -> void:
	_preview.visible = false
	_marker.visible = false
	_start_marker.visible = false
	_label.visible = false


func _process(_delta: float) -> void:
	if road_type == 0:
		return
	if not cursor.has_ground_hit or cursor.over_ui:
		_hide_all()
		return
	update_at(Vector2(cursor.ground_point.x, cursor.ground_point.z))


## Пересчитывает привязку, план и превью для точки мыши raw (мир x, z). Публично — для проверок.
func update_at(raw: Vector2) -> void:
	var grid: CityGrid = GameState.grid
	var graph: RoadGraph = grid.roads
	graph.sync(grid)
	var limit: float = grid.world_size() - 0.01
	raw = raw.clamp(Vector2(0.01, 0.01), Vector2(limit, limit))
	if shape == Shape.UPGRADE:
		_update_upgrade(grid, raw)
		return
	_hover = snap(grid, raw)
	_place_marker(_marker, _hover.pos)
	_start_marker.visible = _start != null
	if _start == null:
		_plan = null
		_preview.visible = false
		_label.visible = false
		return
	_place_marker(_start_marker, _start.pos)
	var ctrl: Variant = _control_for(grid)
	_plan = graph.plan(grid, _start, _hover, ctrl, road_type, GameState.money)
	var choosing_bend: bool = shape == Shape.CURVE and _control == null
	_show_curve(_plan.p0, _plan.c, _plan.p2, road_type, OK_COLOR if _plan.ok or choosing_bend else BAD_COLOR)
	_show_label(_hover.pos, _plan_text(_plan, choosing_bend), _plan.ok or choosing_bend)


## Управляющая точка куска: у дуги — указанный изгиб, у плавной — по касательной прошлого куска.
func _control_for(grid: CityGrid) -> Variant:
	match shape:
		Shape.CURVE:
			return _control
		Shape.FREE:
			return free_control(_start.pos, _start_dir(grid), _hover.pos)
	return null


## Дуга, касающаяся направления dir в начале p0 и приходящая в p2 (как в Cities: Skylines).
static func free_control(p0: Vector2, dir: Vector2, p2: Vector2) -> Variant:
	if dir == Vector2.ZERO:
		return null
	var chord: Vector2 = p2 - p0
	var length: float = chord.length()
	if length < 0.1:
		return null
	var cos_t: float = dir.dot(chord / length)
	if cos_t < 0.2:
		return null
	return p0 + dir * (length / (2.0 * cos_t))


## Направление продолжения: конец прошлого куска или тупик, от которого начали.
func _start_dir(grid: CityGrid) -> Vector2:
	if _prev_dir != Vector2.ZERO:
		return _prev_dir
	var graph: RoadGraph = grid.roads
	if _start.node != -1 and graph.nodes.has(_start.node) and graph.nodes[_start.node].segments.size() == 1:
		var segment: RoadGraph.Segment = graph.segments[graph.nodes[_start.node].segments[0]]
		return -graph.direction_from(segment, _start.node)
	return Vector2.ZERO


## Точка под мышкой с привязкой: узел, дорога (у центра клетки — к нему), центр клетки, угол 15°.
func snap(grid: CityGrid, raw: Vector2) -> RoadGraph.RoadPoint:
	var graph: RoadGraph = grid.roads
	var point := RoadGraph.RoadPoint.new(raw)
	var node: int = graph.node_near(raw, SNAP_NODE)
	if node != -1 and graph.nodes[node].segments.size() > 0:
		point.pos = graph.nodes[node].pos
		point.node = node
		return point
	var id: int = graph.segment_near(raw, SNAP_SEGMENT)
	if id != -1:
		var segment: RoadGraph.Segment = graph.segments[id]
		var points: PackedVector2Array = graph.curve(segment)
		var t: float = graph.nearest_on(segment, raw).x
		if grid_snap:
			var on_center: Vector2 = graph.nearest_on(segment, RoadGraph.cell_center(RoadGraph.cell_of(
					RoadGraph.bezier(points[0], points[1], points[2], t))))
			if on_center.y < SNAP_CENTER:
				t = on_center.x
		var pos: Vector2 = RoadGraph.bezier(points[0], points[1], points[2], t)
		for end: int in [segment.a, segment.b]:
			if graph.nodes[end].pos.distance_to(pos) < SNAP_NODE:
				point.pos = graph.nodes[end].pos
				point.node = end
				return point
		point.pos = pos
		point.segment = id
		point.t = t
		return point
	if grid_snap:
		point.pos = RoadGraph.cell_center(RoadGraph.cell_of(raw))
	elif _start != null:
		point.pos = _snap_angle(_start.pos, raw)
	return point


## Без сетки: направление от from липнет к шагу 15° от оси карты и от прошлого куска.
func _snap_angle(from: Vector2, to: Vector2) -> Vector2:
	var delta: Vector2 = to - from
	var length: float = delta.length()
	if length < 0.5:
		return to
	var refs: Array[float] = [0.0]
	if _prev_dir != Vector2.ZERO:
		refs.append(_prev_dir.angle())
	var step: float = deg_to_rad(ANGLE_STEP)
	for ref: float in refs:
		var rel: float = delta.angle() - ref
		var snapped_rel: float = roundf(rel / step) * step
		if absf(angle_difference(rel, snapped_rel)) < deg_to_rad(ANGLE_SNAP):
			return from + Vector2.from_angle(ref + snapped_rel) * length
	return to


func _plan_text(plan: RoadGraph.Plan, choosing_bend: bool) -> String:
	if choosing_bend:
		return "Укажите изгиб"
	var text: String = "%d м · $%d" % [roundi(plan.length), plan.cost]
	if not plan.ok:
		return plan.reason + ("\n" + text if plan.reason == "Не хватает денег" else "")
	if not plan.demolish.is_empty():
		text += "\nснесёт домов: %d" % plan.demolish.size()
	return text


func _unhandled_input(event: InputEvent) -> void:
	if road_type == 0:
		return
	if event.is_action_pressed(&"road_shape_next"):
		set_shape(((shape + 1) % Shape.size()) as Shape)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"road_grid"):
		set_grid_snap(not grid_snap)
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_LEFT and cursor.has_ground_hit and not cursor.over_ui:
		update_at(Vector2(cursor.ground_point.x, cursor.ground_point.z))
		click()
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_RIGHT and (_start != null or _control != null):
		reset_chain()
		get_viewport().set_input_as_handled()


## Щелчок в текущей точке (после update_at): начало, изгиб, постройка или замена типа.
func click() -> void:
	if shape == Shape.UPGRADE:
		_apply_upgrade()
		return
	if _hover == null:
		return
	if _start == null:
		_start = _hover
		_prev_dir = Vector2.ZERO
		return
	if shape == Shape.CURVE and _control == null:
		if _hover.pos.distance_to(_start.pos) > 1.0:
			_control = _hover.pos
		return
	_build()


func _build() -> void:
	if _plan == null or not _plan.ok or not Economy.can_afford(_plan.cost):
		return
	var grid: CityGrid = GameState.grid
	var graph: RoadGraph = grid.roads
	var built: RoadGraph.Plan = _plan
	var changed: Array[Vector2i] = graph.build(grid, built)
	Economy.spend(built.cost)
	if not changed.is_empty():
		Events.cells_changed.emit(changed)
	# Цепочка тянется дальше — от конца построенного куска.
	var end_node: int = graph.node_near(built.p2, 0.35)
	_control = null
	_plan = null
	if end_node == -1:
		reset_chain()
		return
	_start = RoadGraph.RoadPoint.new(graph.nodes[end_node].pos)
	_start.node = end_node
	_prev_dir = RoadGraph.bezier_tangent(built.p0, built.c, built.p2, 1.0).normalized()


# --- Замена типа ---

func _update_upgrade(grid: CityGrid, raw: Vector2) -> void:
	var graph: RoadGraph = grid.roads
	_marker.visible = false
	_start_marker.visible = false
	_upgrade_id = graph.segment_near(raw, SNAP_SEGMENT)
	if _upgrade_id == -1:
		_preview.visible = false
		_label.visible = false
		return
	var segment: RoadGraph.Segment = graph.segments[_upgrade_id]
	var points: PackedVector2Array = graph.curve(segment)
	var reason: String = upgrade_problem(grid, _upgrade_id)
	_show_curve(points[0], points[1], points[2], road_type, UPGRADE_COLOR if reason.is_empty() else BAD_COLOR)
	var text: String = reason
	if reason.is_empty():
		text = "%s → %s · $%d" % [RoadTypes.NAMES.get(segment.type, ""), RoadTypes.NAMES.get(road_type, ""),
				graph.retype_cost(_upgrade_id, road_type)]
	_show_label(raw, text, reason.is_empty())


## Почему нельзя заменить тип дороги id на текущий (пусто — можно).
func upgrade_problem(grid: CityGrid, id: int) -> String:
	var graph: RoadGraph = grid.roads
	if not graph.segments.has(id):
		return "Нет дороги"
	if graph.is_locked(grid, id):
		return "Трассу у въезда не перестроить"
	if graph.segments[id].type == road_type:
		return "Уже " + RoadTypes.NAMES.get(road_type, "").to_lower()
	if not Economy.can_afford(graph.retype_cost(id, road_type)):
		return "Не хватает денег"
	return ""


func _apply_upgrade() -> void:
	var grid: CityGrid = GameState.grid
	if _upgrade_id == -1 or not upgrade_problem(grid, _upgrade_id).is_empty():
		return
	var cost: int = grid.roads.retype_cost(_upgrade_id, road_type)
	var changed: Array[Vector2i] = grid.roads.retype(grid, _upgrade_id, road_type)
	Economy.spend(cost)
	if not changed.is_empty():
		Events.cells_changed.emit(changed)


# --- Вид ---

func _place_marker(marker: MeshInstance3D, pos: Vector2) -> void:
	marker.visible = true
	marker.position = Vector3(pos.x, RoadGeometry.SIDEWALK_Y + PREVIEW_LIFT, pos.y)


func _show_curve(p0: Vector2, c: Vector2, p2: Vector2, type: int, color: Color) -> void:
	_preview.visible = true
	_preview_material.albedo_color = color
	var key: int = hash([p0, c, p2, type])
	if key == _preview_key and _preview.mesh != null:
		return
	_preview_key = key
	_preview.mesh = RoadGeometry.ribbon_mesh(p0, c, p2, type)


func _show_label(pos: Vector2, text: String, ok: bool) -> void:
	_label.visible = true
	_label.text = text
	_label.modulate = Color.WHITE if ok else Color(1.0, 0.55, 0.5)
	_label.position = Vector3(pos.x, 1.4, pos.y)


## Текст подписи у курсора (для проверок).
func label_text() -> String:
	return _label.text if _label.visible else ""


## План под мышкой (для проверок).
func current_plan() -> RoadGraph.Plan:
	return _plan
