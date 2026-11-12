class_name CitizenCard
extends PanelContainer
## Карточка жителя прямо над фигуркой (как в Cities: Skylines): щелчок без инструмента по пешеходу,
## велосипедисту или машинке (BuildTool.pick_citizen → Events.citizen_selected). Имя, возраст, кем
## и где работает, где живёт, семья, питомец, увлечение, дорога до работы и настроение дома.
## Житель выводится из дома и зерна агента (Citizens) — ничего не сохраняется. Пока карточка открыта,
## агент «закреплён» (followed): доехав, едет обратно тем же путём. Под ним — кольцо выделения.
## Закрывается крестиком, Esc, щелчком по карте или если агент пропал (снесли дорогу, новый город).

const WIDTH: float = 300.0
## Хвостик карточки (треугольник к фигурке), пикселей.
const TAIL: float = 10.0
## Над какой точкой агента висит карточка, м над дорогой.
const ANCHOR_HEIGHT: float = 0.55
## Отступ от краёв экрана, пикселей.
const MARGIN: float = 8.0
## Кольцо выделения под агентом, м.
const RING_RADIUS: float = 0.24
## Жалоба в карточке — если фактор счастья дома хуже этого.
const COMPLAINT_LEVEL: int = -4

var citizen: Citizens.Citizen = null

var _agents: Node = null
var _agent: RefCounted = null
var _title := Label.new()
var _subtitle := Label.new()
var _rows := GridContainer.new()
var _home_button := Button.new()
var _work_button := Button.new()
var _ring := MeshInstance3D.new()
## Карточка сама открыла «Инфо» дома или работы — такой cell_inspected её не закрывает.
var _own_inspect: bool = false


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	size = Vector2(WIDTH, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 5)
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 0)
	head.add_child(titles)
	_title.theme_type_variation = &"Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	_subtitle.theme_type_variation = &"Caption"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)
	var close := Button.new()
	close.text = "×"
	close.theme_type_variation = &"Small"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.tooltip_text = "Закрыть"
	close.pressed.connect(close_card)
	head.add_child(close)
	column.add_child(HSeparator.new())
	_rows.columns = 2
	_rows.add_theme_constant_override(&"h_separation", 10)
	_rows.add_theme_constant_override(&"v_separation", 1)
	column.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 6)
	column.add_child(buttons)
	for pair: Array in [[_home_button, "Показать дом", true], [_work_button, "Показать работу", false]]:
		var button: Button = pair[0]
		button.text = pair[1]
		button.theme_type_variation = &"Small"
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_place.bind(pair[2]))
		buttons.add_child(button)
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS * 0.78
	torus.outer_radius = RING_RADIUS
	torus.rings = 24
	torus.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = UiTheme.ACCENT
	material.no_depth_test = true
	material.render_priority = 1
	torus.material = material
	_ring.mesh = torus
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	Events.citizen_selected.connect(select)
	Events.cell_inspected.connect(func(_cell: Vector2i) -> void:
		if not _own_inspect:
			close_card())
	Events.grid_reset.connect(close_card)
	Events.stats_changed.connect(func() -> void:
		if _agent != null:
			_refresh_rows())


## Открывает карточку агента agent узла agents (TrafficVisualizer / PeopleVisualizer).
func select(agents: Node, agent: RefCounted) -> void:
	_release()
	_agents = agents
	_agent = agent
	agent.followed = true
	var traffic: Traffic = GameState.traffic
	citizen = Citizens.make(GameState.grid, traffic.job_sites, agent.home_id, agent.path, agent.citizen_seed,
			agents.agent_gender(agent))
	agents.add_child(_ring)
	_title.text = "%s, %s" % [citizen.full_name(), age_text(citizen.age)]
	_refresh_rows()
	_follow()


func close_card() -> void:
	_release()
	visible = false


## Открыта ли карточка (агент выбран).
func is_open() -> bool:
	return _agent != null


func _release() -> void:
	if _agent != null:
		_agent.followed = false
	_agent = null
	_agents = null
	citizen = null
	if _ring.get_parent() != null:
		_ring.get_parent().remove_child(_ring)


func _notification(what: int) -> void:
	# Кольцо вне дерева (карточка закрыта) само не освободится.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_ring) and _ring.get_parent() == null:
		_ring.free()


func _unhandled_input(event: InputEvent) -> void:
	if _agent != null and event.is_action_pressed(&"tool_cancel"):
		close_card()


func _process(_delta: float) -> void:
	if _agent != null:
		_follow()


## Карточка — над агентом, кольцо — под ним; агент пропал или сменил поездку — закрываемся.
func _follow() -> void:
	if not is_instance_valid(_agents) or not _agents.has_agent(_agent) or not _agent.followed:
		close_card()
		return
	var at: Vector3 = _agents.agent_position(_agent)
	_ring.position = at + Vector3.UP * 0.03
	_subtitle.text = "%s · %s %s %s" % [citizen.job, _verb(), "на работу" if _agent.forward else "домой",
			_agents.travel_mode()]
	var camera: Camera3D = get_viewport().get_camera_3d()
	var head: Vector3 = at + Vector3.UP * ANCHOR_HEIGHT
	if camera == null or camera.is_position_behind(head):
		visible = false
		return
	var screen: Vector2 = camera.unproject_position(head)
	var view: Vector2 = get_viewport_rect().size
	# Строки с переносом сначала меряются узкими и высокими — каждый кадр ужимаем до настоящего размера.
	reset_size()
	var card: Vector2 = size
	var top_left := Vector2(screen.x - card.x * 0.5, screen.y - card.y - TAIL)
	top_left.x = clampf(top_left.x, MARGIN, maxf(MARGIN, view.x - card.x - MARGIN))
	top_left.y = clampf(top_left.y, MARGIN, maxf(MARGIN, view.y - card.y - MARGIN))
	position = top_left
	# Фигурка ушла за край экрана — карточку прячем, пока не вернётся.
	visible = Rect2(Vector2.ZERO, view).has_point(screen)
	queue_redraw()


## Хвостик к фигурке.
func _draw() -> void:
	if _agent == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var tip: Vector2 = camera.unproject_position(_agents.agent_position(_agent) + Vector3.UP * ANCHOR_HEIGHT) - position
	var base_x: float = clampf(tip.x, UiTheme.RADIUS + TAIL, size.x - UiTheme.RADIUS - TAIL)
	if tip.y < size.y:
		return
	draw_colored_polygon(PackedVector2Array([Vector2(base_x - TAIL, size.y - 1.0), Vector2(base_x + TAIL, size.y - 1.0),
			Vector2(base_x, minf(tip.y, size.y + TAIL))]), Color(UiTheme.PAPER, 1.0))


func _verb() -> String:
	return "идёт" if _agents.travel_mode() == "пешком" else "едет"


## Строки карточки: дом, работа, семья, настроение (пересчитываются со статистикой города).
func _refresh_rows() -> void:
	if citizen == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var grid: CityGrid = GameState.grid
	var home: BuildingInstance = grid.buildings.get(citizen.home_id)
	var home_data: BuildingData = BuildingCatalog.get_type(home.type_id) if home != null else null
	var work: BuildingInstance = grid.buildings.get(citizen.work_id)
	var work_data: BuildingData = BuildingCatalog.get_type(work.type_id) if work != null else null
	if home_data != null:
		_add("Живёт", home_data.display_name)
	else:
		_add("Живёт", "за городом, приезжает по трассе")
	_add("Работает", work_data.display_name if work_data != null else "—")
	_add("Семья", citizen.family)
	if not citizen.pet.is_empty():
		_add("Питомец", citizen.pet)
	_add("Увлечение", citizen.hobby)
	_add("Дорога", "%d мин %s" % [_agents.trip_minutes(_agent), _agents.travel_mode()])
	if home != null and home_data != null and home_data.population > 0:
		var factors: Array[Array] = Happiness.factors(grid, home, home_data, GameState.land, GameState.traffic,
				GameState.tax_rate)
		var mood: int = Happiness.score_of(factors)
		_add("Настроение", "%d / 100 — %s" % [mood, mood_word(mood, citizen.male)], mood < Levels.DECLINE_HAPPINESS)
		var worst: Array = []
		for factor: Array in factors:
			if roundi(factor[1]) <= COMPLAINT_LEVEL and (worst.is_empty() or factor[1] < worst[1]):
				worst = factor
		if not worst.is_empty():
			_add("Жалуется", String(worst[0]).to_lower(), true)
	_home_button.disabled = home == null
	_work_button.disabled = work == null
	reset_size()


func _add(label_text: String, value_text: String, bad: bool = false) -> void:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"Caption"
	_rows.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size = Vector2(150, 0)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bad:
		value.add_theme_color_override(&"font_color", UiTheme.BAD)
	_rows.add_child(value)


## Камера — к дому или работе, там открывается «Инфо»; карточка жителя остаётся.
func _show_place(home: bool) -> void:
	if citizen == null:
		return
	var building: BuildingInstance = GameState.grid.buildings.get(citizen.home_id if home else citizen.work_id)
	if building == null:
		return
	var cell: Vector2i = building.anchor_cell()
	Events.camera_focus_requested.emit(cell)
	_own_inspect = true
	Events.cell_inspected.emit(cell)
	_own_inspect = false


## Строки карточки «подпись → значение» (для проверок).
func rows() -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	var children: Array[Node] = _rows.get_children()
	for i: int in range(0, children.size() - 1, 2):
		result[(children[i] as Label).text] = (children[i + 1] as Label).text
	return result


func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


## «1 год», «23 года», «45 лет».
static func age_text(years: int) -> String:
	var word := "лет"
	if years % 10 == 1 and years % 100 != 11:
		word = "год"
	elif years % 10 in [2, 3, 4] and years % 100 not in [12, 13, 14]:
		word = "года"
	return "%d %s" % [years, word]


static func mood_word(mood: int, male: bool) -> String:
	if mood >= 70:
		return "счастлив" if male else "счастлива"
	if mood >= 45:
		return "доволен" if male else "довольна"
	if mood >= 30:
		return "так себе"
	return "недоволен" if male else "недовольна"
