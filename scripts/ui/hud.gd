class_name Hud
extends CanvasLayer
## Интерфейс: двухрядная верхняя панель с 3D-иконками показателей и кнопкой «Советник» (Advisor —
## список проблем с местами на карте), нижняя док-панель с вкладками и 3D-карточками инструментов.
## Состояние напрямую не меняет: только сигналы Events и публичные SimClock.set_speed() / SaveManager.

## Вкладки инструментов. Инструменты — режимы BuildTool; здания — служебные из каталога
## («utilities» — дают свет или воду, «services» — службы, «parks» — парки).
const TABS: Array[Dictionary] = [
	{"id": "roads", "name": "Дороги", "tools": [
		{"mode": BuildTool.Mode.ROAD, "name": "Улица", "key": "R", "icon": "tool_road"},
		{"mode": BuildTool.Mode.ROAD_AVENUE, "name": "Проспект", "key": "T", "icon": "tool_avenue"},
		{"mode": BuildTool.Mode.ROAD_HIGHWAY, "name": "Шоссе", "key": "Y", "icon": "tool_highway"},
	]},
	{"id": "zones", "name": "Зоны", "tools": [
		{"mode": BuildTool.Mode.ZONE_R, "name": "Жилая", "key": "1", "icon": "tool_zone_r"},
		{"mode": BuildTool.Mode.ZONE_C, "name": "Коммерция", "key": "2", "icon": "tool_zone_c"},
		{"mode": BuildTool.Mode.ZONE_I, "name": "Промзона", "key": "3", "icon": "tool_zone_i"},
		{"mode": BuildTool.Mode.DEZONE, "name": "Снять зону", "key": "4", "icon": "tool_dezone"},
		{"mode": BuildTool.Mode.ZONE_R_HIGH, "name": "Многоэтажки", "key": "5", "icon": "tool_zone_r_high"},
		{"mode": BuildTool.Mode.ZONE_C_HIGH, "name": "Торговые дома", "key": "6", "icon": "tool_zone_c_high"},
		{"mode": BuildTool.Mode.ZONE_O, "name": "Офисы", "key": "7", "icon": "tool_zone_o"},
	]},
	{"id": "utilities", "name": "Свет и вода", "buildings": "utilities"},
	{"id": "services", "name": "Службы", "buildings": "services"},
	{"id": "parks", "name": "Парки", "buildings": "parks"},
]
const SPEEDS: Array[Dictionary] = [
	{"speed": 0, "name": "Пауза"},
	{"speed": 1, "name": "×1"},
	{"speed": 3, "name": "×3"},
	{"speed": 8, "name": "×8"},
]
## Полоски спроса: подпись и цвет (как у зон).
const DEMANDS: Array[Dictionary] = [
	{"name": "R", "color": Color(0.25, 0.75, 0.3)},
	{"name": "C", "color": Color(0.25, 0.5, 0.95)},
	{"name": "I", "color": Color(0.95, 0.75, 0.2)},
]
## Размер карточки инструмента (с 3D-иконкой сверху).
const CARD_SIZE := Vector2(106, 78)
## Ширина шкалы света или воды во вкладке «Свет и вода».
const METER_WIDTH: float = 250.0
## Вкладка фильтров карты (свет, вода, пробки…) — FilterPanel.
const FILTER_TAB := "filters"
## Сколько секунд висит сообщение о сохранении.
const TOAST_SECONDS: float = 2.5
## Ширина часов «00:00» с запасом, px.
const CLOCK_WIDTH: float = 52.0
## Подсказки к формам дороги (RoadTool.Shape).
const ROAD_SHAPE_TIPS: Array[String] = [
	"Прямая: щелчок — начало, щелчок — конец, дорога тянется дальше.\nПКМ — закончить, Tab — следующая форма",
	"Дуга: щелчок — начало, щелчок — изгиб, щелчок — конец",
	"Плавная: каждый кусок продолжает предыдущий плавной дугой",
	"Замена: щелчок по дороге меняет её тип на выбранный (улица, проспект, шоссе)",
]

var _tool_buttons: Dictionary[int, Button] = {}
var _service_buttons: Dictionary[StringName, Button] = {}
var _speed_buttons: Dictionary[int, Button] = {}
var _demand_bars: Array[DemandBar] = []
var _utility_meters: Array[UtilityMeter] = []
## Вкладки: id → кнопка вкладки и ряд её карточек.
var _tab_buttons: Dictionary[String, Button] = {}
var _tab_cards: Dictionary[String, HBoxContainer] = {}
var _active_tab: String = ""
var _current_tool: int = BuildTool.Mode.NONE
var _current_type: StringName = &""
var _filters := FilterPanel.new()
## Слой карты сейчас (ZoneVisualizer.Overlay).
var _overlay: int = ZoneVisualizer.Overlay.ZONES
var _save_dialog := SaveDialog.new()
var _new_city_confirm := ConfirmationDialog.new()
var _toast := PanelContainer.new()
var _toast_label := Label.new()
var _info := InfoPanel.new()
## Советник: кнопка со счётчиком в верхней панели, список проблем и строчка о новой — вместо плашки подсказок.
var _advisor := Advisor.new()
## Плашка звания (фаза 10) — создаётся кодом рядом с «Жителями»; счастье — в плашке «Жители».
var _rank_label := Label.new()
## Игровые часы рядом с днём.
var _clock_label := Label.new()
## Номер последнего сообщения: старый таймер не прячет новое сообщение.
var _toast_serial: int = 0
## Скорость до окна подтверждения «Новый город».
var _speed_before_confirm: int = 1
## Формы дороги (RoadTool.Shape) и привязка к сетке — кнопки во вкладке «Дороги».
var _road_shape_buttons: Array[Button] = []
var _road_snap_button: Button


func _ready() -> void:
	var theme: Theme = UiTheme.build()
	$Root.theme = theme
	_build_rank_chips()
	_decorate_top_bar()
	_make_clock()
	_build_demand_bars()
	_build_speed_buttons()
	_build_advisor()
	_build_tabs()
	_build_bottom_extras()
	_build_city_controls()
	$Root.add_child(_info)
	Events.rank_changed.connect(_on_rank_changed)
	_new_city_confirm.theme = theme
	for window: Node in _save_dialog.find_children("*", "Window", true, false):
		(window as Window).theme = theme
	%TaxDown.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate - 1))
	%TaxUp.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate + 1))
	Events.stats_changed.connect(_refresh_stats)
	Events.tool_mode_changed.connect(_on_tool_mode_changed)
	Events.speed_changed.connect(_sync_speed_buttons)
	Events.overlay_changed.connect(func(mode: int) -> void: _overlay = mode)
	_select_tab("roads")
	_refresh_stats()
	_sync_tool_buttons()
	_sync_speed_buttons(SimClock.speed)


# --- Верхняя панель ---

func _decorate_top_bar() -> void:
	var top_row: Node = %DayLabel.get_parent()
	var city_icon := UiTheme.make_chip_icon("menu_crest", 24)
	top_row.add_child(city_icon)
	top_row.move_child(city_icon, %DayLabel.get_index())
	_attach_chip_icon(%MoneyLabel, "stat_money")
	_attach_chip_icon(%PopLabel, "stat_pop")
	_attach_chip_icon(_rank_label, "stat_rank")
	_attach_chip_icon(%JobsLabel, "stat_jobs")


## Часы — отдельной надписью постоянной ширины: цифры у шрифта разной ширины, и плашки рядом
## дрожали бы каждую игровую минуту.
func _make_clock() -> void:
	_clock_label.custom_minimum_size = Vector2(CLOCK_WIDTH, 0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_clock_label.tooltip_text = "Игровое время, как в SimCity: час — %s на ×1, %s на ×3, %s на ×8" % [
			_duration(SimClock.seconds_per_hour(1)), _duration(SimClock.seconds_per_hour(3)),
			_duration(SimClock.seconds_per_hour(8))]
	var top_row: Node = %DayLabel.get_parent()
	top_row.add_child(_clock_label)
	top_row.move_child(_clock_label, %DayLabel.get_index() + 1)


## «2 мин», «40 с».
static func _duration(seconds: float) -> String:
	if seconds >= 60.0:
		return "%s мин" % String.num(seconds / 60.0, 1).trim_suffix(".0")
	return "%d с" % roundi(seconds)


## Город, сутки и часы; проверяем каждый кадр, текст меняем, только если изменился.
func _show_clock() -> void:
	var day_text: String = "%s · День %d" % [GameState.city_name, GameState.day]
	if %DayLabel.text != day_text:
		%DayLabel.text = day_text
	var time_text: String = SimClock.time_text()
	if _clock_label.text != time_text:
		_clock_label.text = time_text


func _process(_delta: float) -> void:
	_show_clock()


func _attach_chip_icon(label: Label, icon_name: String) -> void:
	var chip: Node = label.get_parent()
	if chip == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.remove_child(label)
	row.add_child(UiTheme.make_chip_icon(icon_name, 19))
	row.add_child(label)
	chip.add_child(row)
	# После переноса Godot сбрасывает owner — без него %MoneyLabel и другие уникальные имена
	# не находятся, и верхняя панель перестаёт обновляться. Надписи из кода (звание) owner не нужен.
	if label.unique_name_in_owner:
		label.owner = self


func _refresh_stats() -> void:
	var balance: int = GameState.income - GameState.expenses
	%MoneyLabel.text = "$%d (%+d/ч)" % [GameState.money, roundi(GameTime.per_hour(balance))]
	var money_tip: String = "За игровой час:\nдоход +$%d\nсодержание дорог и служб −$%d"
	%MoneyLabel.tooltip_text = money_tip % [roundi(GameTime.per_hour(GameState.income)),
			roundi(GameTime.per_hour(GameState.expenses))]
	_mark_bad(%MoneyLabel, GameState.money < 0)
	_show_clock()
	%PopLabel.text = "Жители: %d" % GameState.population
	%JobsLabel.text = "Работа: C %d · I %d" % [GameState.jobs_commercial, GameState.jobs_industrial]
	_advisor.refresh()
	_show_rank()
	_sync_locks()
	%TaxLabel.text = "Налог %d%%" % GameState.tax_rate
	%TaxDown.disabled = GameState.tax_rate <= Economy.MIN_TAX_RATE
	%TaxUp.disabled = GameState.tax_rate >= Economy.MAX_TAX_RATE
	for meter: UtilityMeter in _utility_meters:
		meter.refresh()
	var demands: Array[float] = [GameState.demand_r, GameState.demand_c, GameState.demand_i]
	for i: int in _demand_bars.size():
		_demand_bars[i].value = demands[i]
		_demand_bars[i].tooltip_text = "Спрос %s: %+.2f" % [DEMANDS[i].name, demands[i]]


## «Посёлок · 230/600»: звание и сколько жителей до следующего; счастье — среднее по жителям.
func _show_rank() -> void:
	var rank: int = maxi(0, GameState.rank)
	_rank_label.text = Ranks.NAMES[rank]
	if rank + 1 < Ranks.THRESHOLDS.size():
		_rank_label.text += " · %d/%d" % [GameState.population, Ranks.THRESHOLDS[rank + 1]]
		var next_unlocks: PackedStringArray = Ranks.unlocks_of(rank + 1)
		_rank_label.tooltip_text = "Следующее звание: %s (%d жителей), награда $%d" % [
				Ranks.NAMES[rank + 1], Ranks.THRESHOLDS[rank + 1], Ranks.REWARDS[rank + 1]]
		if not next_unlocks.is_empty():
			_rank_label.tooltip_text += "\nОткроет: " + ", ".join(next_unlocks)
	var mood: int = GameState.happiness.average
	if mood >= 0:
		%PopLabel.text += " · счастье %d%%" % mood
	%PopLabel.tooltip_text = "Счастье жителей: службы, цена земли, загрязнение, шум, дорога до работы, налог. Подробнее — клик по дому."
	_mark_bad(%PopLabel, mood >= 0 and mood < Levels.DECLINE_HAPPINESS + 15)


## Карточки закрытых зон и дорог — серые, с подсказкой, с какого звания откроются.
func _sync_locks() -> void:
	for mode: int in _tool_buttons:
		if BuildTool.MODE_ROADS.has(mode):
			var road_type: int = BuildTool.MODE_ROADS[mode]
			var rank: int = RoadTypes.UNLOCK_RANK[road_type]
			var road_locked: bool = BuildTool.is_locked(mode)
			_tool_buttons[mode].disabled = road_locked
			var about: String = "%s: пропускает %d поездок, скорость ×%.1f, содержание $%d/кл. в час" % [
					RoadTypes.NAMES[road_type], RoadTypes.CAPACITY[road_type], 1.0 / RoadTypes.TRAVEL_COST[road_type],
					roundi(GameTime.per_hour(RoadTypes.UPKEEP[road_type]))]
			if road_type == RoadTypes.Type.HIGHWAY:
				about += "\nДома к шоссе не подключаются"
			about += "\nЩелчок — начало, щелчок — конец; «Замена» — сменить тип готовой дороги"
			_tool_buttons[mode].tooltip_text = ("Откроется на звании «%s» (%d жителей)\n" % [Ranks.NAMES[rank],
					Ranks.THRESHOLDS[rank]] if road_locked else "") + about
			continue
		if not BuildTool.MODE_ZONES.has(mode) or mode == BuildTool.Mode.DEZONE:
			continue
		var zone_type: CityGrid.Zone = BuildTool.MODE_ZONES[mode]
		var locked: bool = BuildTool.is_locked(mode)
		_tool_buttons[mode].disabled = locked
		_tool_buttons[mode].tooltip_text = ("Откроется на звании «%s» (%d жителей)" % [
				Ranks.NAMES[Ranks.UNLOCKS[zone_type]], Ranks.THRESHOLDS[Ranks.UNLOCKS[zone_type]]]) if locked else ""


func _build_rank_chips() -> void:
	var row: Node = %PopLabel.get_parent().get_parent()
	var after: int = %PopLabel.get_parent().get_index()
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"Chip"
	_rank_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_rank_label.theme_type_variation = &"Title"
	chip.add_child(_rank_label)
	row.add_child(chip)
	row.move_child(chip, after + 1)
	%PopLabel.mouse_filter = Control.MOUSE_FILTER_PASS


func _on_rank_changed(rank: int) -> void:
	var text: String = "Новое звание: %s! Награда $%d" % [Ranks.NAMES[rank], Ranks.REWARDS[rank]]
	var unlocks: PackedStringArray = Ranks.unlocks_of(rank)
	if not unlocks.is_empty():
		text += ". Открыты: " + ", ".join(unlocks)
	_show_toast(text)


func _mark_bad(label: Label, bad: bool) -> void:
	if bad:
		label.add_theme_color_override(&"font_color", UiTheme.BAD)
	else:
		label.remove_theme_color_override(&"font_color")


## Кнопка «Советник» — слева, сразу за часами: список и строчка открываются под ней, у левого края,
## и не закрывают карточку «Инфо» (она справа).
func _build_advisor() -> void:
	var top_row: Node = _clock_label.get_parent()
	top_row.add_child(_advisor.button)
	top_row.move_child(_advisor.button, _clock_label.get_index() + 1)
	_advisor.anchor_bar = $Root/Margin/Layout/TopBar
	$Root.add_child(_advisor)
	$Root.add_child(_advisor.bubble)
	_advisor.entry_opened.connect(_on_advisor_entry)


## «Показать» в советнике: слой карты записи (через вкладку «Фильтры») или её вкладка построек.
func _on_advisor_entry(entry: Hints.Entry) -> void:
	if entry.overlay >= 0:
		_select_tab(FILTER_TAB)
		_request_overlay(entry.overlay)
	elif not entry.tab.is_empty():
		_select_tab(entry.tab)


func _build_demand_bars() -> void:
	var caption := Label.new()
	caption.text = "Спрос"
	caption.theme_type_variation = &"Caption"
	%Demand.add_child(caption)
	for entry: Dictionary in DEMANDS:
		var label := Label.new()
		label.text = entry.name
		%Demand.add_child(label)
		var bar := DemandBar.new()
		bar.color = entry.color
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		%Demand.add_child(bar)
		_demand_bars.append(bar)


func _build_speed_buttons() -> void:
	for entry: Dictionary in SPEEDS:
		var button := _make_button(entry.name, &"Small")
		var speed: int = entry.speed
		if speed > 0:
			button.tooltip_text = "Игровой час — %s" % _duration(SimClock.seconds_per_hour(speed))
		button.pressed.connect(func() -> void:
			SimClock.set_speed(speed)
			# Повторный клик по активной кнопке не должен её «отжимать».
			_sync_speed_buttons(SimClock.speed))
		%Speed.add_child(button)
		_speed_buttons[speed] = button


func _sync_speed_buttons(speed: int) -> void:
	for value: int in _speed_buttons:
		_speed_buttons[value].set_pressed_no_signal(value == speed)


# --- Нижняя панель: вкладки и карточки ---

func _build_tabs() -> void:
	for tab: Dictionary in TABS:
		var id: String = tab.id
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override(&"separation", 8)
		cards.visible = false
		%Tools.add_child(cards)
		_tab_cards[id] = cards
		for tool: Dictionary in tab.get("tools", []):
			_add_tool_card(cards, id, tool)
		if tab.has("buildings"):
			for data: BuildingData in _tab_buildings(tab.buildings):
				_add_building_card(cards, id, data)
		if id == "utilities":
			_add_utility_meters(cards)
		if id == "roads":
			_add_road_shapes(cards)
		var button := _make_button(tab.name, &"Tab")
		UiTheme.tab_styles(button, id)
		button.pressed.connect(func() -> void:
			# Повторный клик по открытой вкладке сворачивает панель.
			_select_tab("" if _active_tab == id else id))
		%Tabs.add_child(button)
		_tab_buttons[id] = button


## Формы дороги и привязка к сетке — справа от типов дорог (как панель инструмента в Cities: Skylines).
func _add_road_shapes(row: HBoxContainer) -> void:
	row.add_child(VSeparator.new())
	var box := GridContainer.new()
	box.columns = 3
	box.add_theme_constant_override(&"h_separation", 4)
	box.add_theme_constant_override(&"v_separation", 4)
	for shape: int in RoadTool.SHAPE_NAMES.size():
		var button := _make_button(RoadTool.SHAPE_NAMES[shape], &"Small")
		button.tooltip_text = ROAD_SHAPE_TIPS[shape]
		button.pressed.connect(func() -> void: Events.road_shape_requested.emit(shape))
		box.add_child(button)
		_road_shape_buttons.append(button)
	_road_snap_button = _make_button("Сетка [G]", &"Small")
	_road_snap_button.tooltip_text = "Привязка к центрам клеток: дороги ровно по сетке зон.\nБез сетки — любые точки, углы липнут к 15°"
	_road_snap_button.toggled.connect(func(on: bool) -> void: Events.road_grid_snap_requested.emit(on))
	box.add_child(_road_snap_button)
	row.add_child(box)
	Events.road_tool_changed.connect(_sync_road_shapes)
	_sync_road_shapes(RoadTool.Shape.STRAIGHT, true)


func _sync_road_shapes(shape: int, grid_snap: bool) -> void:
	for i: int in _road_shape_buttons.size():
		_road_shape_buttons[i].set_pressed_no_signal(i == shape)
	_road_snap_button.set_pressed_no_signal(grid_snap)


## Шкалы света и воды справа от станций, как в Cities: Skylines: видно, хватает ли и сколько ещё нужно.
func _add_utility_meters(row: HBoxContainer) -> void:
	row.add_child(VSeparator.new())
	for kind: UtilityMeter.Kind in [UtilityMeter.Kind.POWER, UtilityMeter.Kind.WATER]:
		var meter := UtilityMeter.new(kind)
		meter.custom_minimum_size = Vector2(METER_WIDTH, 0)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(meter)
		_utility_meters.append(meter)


## Здания вкладки: «utilities» — дают свет или воду, «parks» — парки (по цене),
## «services» — остальные службы по порядку ступеней.
func _tab_buildings(kind: String) -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for data: BuildingData in BuildingCatalog.buildable_types():
		var data_kind: String = "services"
		if data.power_supply > 0 or data.water_supply > 0:
			data_kind = "utilities"
		elif data.park != BuildingData.Park.NONE:
			data_kind = "parks"
		if data_kind == kind:
			result.append(data)
	result.sort_custom(func(a: BuildingData, b: BuildingData) -> bool:
		if a.service != b.service:
			return a.service < b.service
		# «Свет и вода»: сначала станции света, потом воды.
		if (a.water_supply > 0) != (b.water_supply > 0):
			return b.water_supply > 0
		return a.cost < b.cost or (a.cost == b.cost and a.id < b.id))
	return result


func _add_tool_card(row: HBoxContainer, category: String, tool: Dictionary) -> void:
	var mode: int = tool.mode
	var cost: int = BuildTool.cost_of(mode)
	var price: String = ("$%d/кл. · " % cost) if cost > 0 else ""
	var button := _make_card("%s\n%s%s" % [tool.name, price, tool.key], category, tool.get("icon", ""))
	button.pressed.connect(func() -> void:
		Events.tool_requested.emit(mode)
		_sync_tool_buttons())
	row.add_child(button)
	_tool_buttons[mode] = button


func _add_building_card(row: HBoxContainer, category: String, data: BuildingData) -> void:
	var button := _make_card("%s\n$%d" % [data.display_name, data.cost], category, String(data.id))
	button.tooltip_text = _service_tooltip(data)
	var type_id: StringName = data.id
	button.pressed.connect(func() -> void:
		Events.building_place_requested.emit(type_id)
		_sync_tool_buttons())
	row.add_child(button)
	_service_buttons[type_id] = button


## «Снос» и вкладка «Фильтры» — рядом с вкладками, всегда под рукой.
func _build_bottom_extras() -> void:
	%Tabs.add_child(VSeparator.new())
	var bulldoze := _make_card("Снос [B]", "bulldoze", "tool_bulldoze", false)
	bulldoze.custom_minimum_size = Vector2(104, 38)
	bulldoze.pressed.connect(func() -> void:
		Events.tool_requested.emit(BuildTool.Mode.BULLDOZE)
		_sync_tool_buttons())
	%Tabs.add_child(bulldoze)
	_tool_buttons[BuildTool.Mode.BULLDOZE] = bulldoze
	# Фильтры — такая же вкладка, как остальные: карточки в той же панели, что и инструменты.
	_filters.visible = false
	%Tools.add_child(_filters)
	_tab_cards[FILTER_TAB] = _filters
	var filters := _make_button("Фильтры [V]", &"Tab")
	UiTheme.tab_styles(filters, FILTER_TAB)
	filters.tooltip_text = "Что показать на карте: свет, вода, пробки, службы, цена земли, загрязнение, шум"
	filters.pressed.connect(func() -> void:
		_select_tab("" if _active_tab == FILTER_TAB else FILTER_TAB))
	%Tabs.add_child(filters)
	_tab_buttons[FILTER_TAB] = filters


func _select_tab(id: String) -> void:
	_active_tab = id
	for tab_id: String in _tab_cards:
		_tab_cards[tab_id].visible = tab_id == id
		_tab_buttons[tab_id].set_pressed_no_signal(tab_id == id)
	%ToolPanel.visible = not id.is_empty()
	# Фильтр виден, пока открыта его вкладка (как в Cities: Skylines): другая вкладка — снова зоны.
	if id != FILTER_TAB:
		_request_overlay(ZoneVisualizer.Overlay.ZONES)


func _request_overlay(mode: int) -> void:
	if mode != _overlay:
		Events.overlay_requested.emit(mode)


## Слой под инструмент, как в SimCity: станции — свет или вода, службы — их покрытие,
## парки — цена земли; дороги и зоны — обычная карта.
static func _overlay_for(mode: int, type_id: StringName) -> int:
	var data: BuildingData = BuildingCatalog.get_type(type_id) if mode == BuildTool.Mode.PLACE else null
	if data == null:
		return ZoneVisualizer.Overlay.ZONES
	if data.power_supply > 0:
		return ZoneVisualizer.Overlay.POWER
	if data.water_supply > 0:
		return ZoneVisualizer.Overlay.WATER
	if data.service != BuildingData.Service.NONE:
		return ZoneVisualizer.Overlay.SERVICES
	if data.park != BuildingData.Park.NONE:
		return ZoneVisualizer.Overlay.LAND_VALUE
	return ZoneVisualizer.Overlay.ZONES


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"overlay_next"):
		_select_tab("" if _active_tab == FILTER_TAB else FILTER_TAB)
		get_viewport().set_input_as_handled()


## Вкладка, где лежит инструмент или здание (для клавиш R, 1–4 и выбора службы).
func _tab_of(mode: int, type_id: StringName) -> String:
	if mode == BuildTool.Mode.PLACE:
		for tab_id: String in _tab_cards:
			if _service_buttons.has(type_id) and _service_buttons[type_id].get_parent() == _tab_cards[tab_id]:
				return tab_id
		return ""
	for tab_id: String in _tab_cards:
		if _tool_buttons.has(mode) and _tool_buttons[mode].get_parent() == _tab_cards[tab_id]:
			return tab_id
	return ""


func _on_tool_mode_changed(mode: int, type_id: StringName) -> void:
	_current_tool = mode
	_current_type = type_id
	var tab: String = _tab_of(mode, type_id)
	if not tab.is_empty():
		_select_tab(tab)
		_request_overlay(_overlay_for(mode, type_id))
	_sync_tool_buttons()


func _sync_tool_buttons() -> void:
	for mode: int in _tool_buttons:
		_tool_buttons[mode].set_pressed_no_signal(mode == _current_tool)
	var placing: bool = _current_tool == BuildTool.Mode.PLACE
	for type_id: StringName in _service_buttons:
		_service_buttons[type_id].set_pressed_no_signal(placing and type_id == _current_type)


## Цена, содержание, что даёт и потребляет, радиус и с какого населения нужна служба.
func _service_tooltip(data: BuildingData) -> String:
	var lines: PackedStringArray = ["Цена: $%d, содержание: $%d/ч" % [data.cost, roundi(GameTime.per_hour(data.upkeep))]]
	if data.power_supply > 0:
		lines.append("Даёт свет: %s" % Utilities.power_text(data.power_supply))
	if data.water_supply > 0:
		lines.append("Даёт воду: %s" % Utilities.water_text(data.water_supply))
	if data.power_use > 0 or data.water_use > 0:
		lines.append("Потребляет: свет %s, вода %s" % [Utilities.power_text(data.power_use),
				Utilities.water_text(data.water_use)])
	if data.land_value > 0:
		lines.append("Цена земли вокруг: +%d" % data.land_value)
	if data.pollution > 0:
		lines.append("Загрязнение вокруг: %d" % data.pollution)
	if StationModules.is_station(data.id):
		var modules: PackedStringArray = []
		for module: StationModules.Module in StationModules.options(data.id):
			modules.append("%s (%s)" % [module.name.to_lower(), "бесплатно" if module.cost == 0 else "$%d" % module.cost])
		lines.append("Участок %d×%d клетки, первый модуль — сразу" % [data.size.x, data.size.y])
		lines.append("Модули ставятся рядом на карте (кнопки в карточке станции): %s" % ", ".join(modules))
	if data.service != BuildingData.Service.NONE:
		var needed_from: int = Services.REQUIRED_FROM.get(data.service, 0)
		lines.append("Радиус: %d кл.; нужна городу с %d жителей" % [data.service_radius, needed_from])
	lines.append("Ставится у дороги")
	return "\n".join(lines)


func _make_card(text: String, category: String, icon_name: String = "", vertical_icon: bool = true) -> Button:
	var button := _make_button(text, &"Card")
	button.custom_minimum_size = CARD_SIZE
	UiTheme.card_styles(button, category, icon_name, vertical_icon)
	return button


func _make_button(text: String, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.theme_type_variation = variation
	# Без фокуса: иначе Пробел нажимал бы последнюю кнопку вместо паузы.
	button.focus_mode = Control.FOCUS_NONE
	return button


# --- Города, новый город, сообщения ---

## Кнопки «Города», «Новый город» и «Меню», окно сохранений, подтверждение и сообщения.
func _build_city_controls() -> void:
	var cities := _make_button("Города", &"Small")
	cities.toggle_mode = false
	cities.pressed.connect(_save_dialog.open)
	%Menu.add_child(cities)
	var new_city := _make_button("Новый город", &"Small")
	new_city.toggle_mode = false
	new_city.pressed.connect(request_new_city)
	%Menu.add_child(new_city)
	var menu := _make_button("Меню", &"Small")
	menu.toggle_mode = false
	menu.tooltip_text = "Главное меню [Esc]"
	menu.pressed.connect(func() -> void: Events.menu_requested.emit())
	%Menu.add_child(menu)
	$Root.add_child(_save_dialog)

	_new_city_confirm.title = "Новый город"
	_new_city_confirm.ok_button_text = "Сохранить и создать"
	_new_city_confirm.add_button("Не сохранять", true, "discard")
	_new_city_confirm.confirmed.connect(func() -> void:
		if SaveManager.save_city(GameState.city_name):
			SaveManager.new_city())
	_new_city_confirm.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_new_city_confirm.hide()
			SaveManager.new_city())
	# Пока окно подтверждения открыто — пауза и камера стоит; закрылось — скорость прежняя.
	_new_city_confirm.visibility_changed.connect(func() -> void:
		if not _new_city_confirm.visible:
			SimClock.set_speed(_speed_before_confirm)
			Events.modal_changed.emit(false))
	add_child(_new_city_confirm)

	_toast.add_child(_toast_label)
	_toast_label.theme_type_variation = &"Title"
	# Под верхней панелью, по центру.
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 86.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	$Root.add_child(_toast)
	Events.save_done.connect(func(save_name: String) -> void:
		# Сохранение под новым именем переименовывает город — обновим верхнюю панель.
		_refresh_stats()
		_show_toast("Сохранено: " + save_name))
	Events.load_done.connect(func(save_name: String, warnings: int) -> void:
		var text: String = "Загружено: " + save_name
		if warnings > 0:
			text += " (пропущено с ошибками: %d)" % warnings
		_show_toast(text))
	Events.save_error.connect(_show_toast)


## «Новый город»: пустой город заменяется сразу, иначе — вопрос «сохранить?». Зовёт и главное меню.
func request_new_city() -> void:
	if SaveManager.is_city_empty():
		SaveManager.new_city()
		return
	_new_city_confirm.dialog_text = "Сохранить «%s» перед созданием нового города?" % GameState.city_name
	_speed_before_confirm = SimClock.speed
	SimClock.set_speed(0)
	Events.modal_changed.emit(true)
	_new_city_confirm.popup_centered()


func _show_toast(text: String) -> void:
	_toast_serial += 1
	var serial: int = _toast_serial
	_toast_label.text = text
	# Под верхней панелью: её высота зависит от ширины окна (плашки переносятся на новые строки).
	_toast.offset_top = $Root/Margin/Layout/TopBar.get_global_rect().end.y + 10.0
	_toast.visible = true
	await get_tree().create_timer(TOAST_SECONDS).timeout
	if serial == _toast_serial:
		_toast.visible = false
