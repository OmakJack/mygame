extends CanvasLayer
## Панель статистики и кнопки. Состояние напрямую не меняет:
## только сигналы Events и публичный SimClock.set_speed().

## Кнопки инструментов: режим, название, клавиша.
const TOOLS: Array[Dictionary] = [
	{"mode": BuildTool.Mode.ROAD, "name": "Дорога", "key": "R"},
	{"mode": BuildTool.Mode.ZONE_R, "name": "Жилая", "key": "1"},
	{"mode": BuildTool.Mode.ZONE_C, "name": "Коммерция", "key": "2"},
	{"mode": BuildTool.Mode.ZONE_I, "name": "Промзона", "key": "3"},
	{"mode": BuildTool.Mode.DEZONE, "name": "Снять зону", "key": "4"},
	{"mode": BuildTool.Mode.BULLDOZE, "name": "Снос", "key": "B"},
	{"mode": BuildTool.Mode.NONE, "name": "Выкл.", "key": "Esc"},
]
const SPEEDS: Array[Dictionary] = [
	{"speed": 0, "name": "Пауза"},
	{"speed": 1, "name": "×1"},
	{"speed": 3, "name": "×3"},
]
## Полоски спроса: подпись и цвет (как у зон).
const DEMANDS: Array[Dictionary] = [
	{"name": "R", "color": Color(0.25, 0.8, 0.3)},
	{"name": "C", "color": Color(0.25, 0.5, 0.95)},
	{"name": "I", "color": Color(0.95, 0.8, 0.2)},
]
const DEBT_COLOR := Color(1.0, 0.35, 0.3)
## Свет или вода: кому-то не хватило.
const SHORTAGE_COLOR := Color(1.0, 0.35, 0.3)

var _tool_buttons: Dictionary[int, Button] = {}
var _service_buttons: Dictionary[StringName, Button] = {}
var _speed_buttons: Dictionary[int, Button] = {}
var _demand_bars: Array[DemandBar] = []
var _current_tool: int = BuildTool.Mode.NONE
var _current_type: StringName = &""


func _ready() -> void:
	_build_demand_bars()
	_build_speed_buttons()
	_build_tool_buttons()
	_build_service_buttons()
	%TaxDown.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate - 1))
	%TaxUp.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate + 1))
	Events.stats_changed.connect(_refresh_stats)
	Events.tool_mode_changed.connect(_on_tool_mode_changed)
	Events.speed_changed.connect(_sync_speed_buttons)
	Events.overlay_changed.connect(_show_overlay)
	_show_overlay(ZoneVisualizer.Overlay.ZONES)
	_refresh_stats()
	_sync_tool_buttons()
	_sync_speed_buttons(SimClock.speed)


func _refresh_stats() -> void:
	var balance: int = GameState.income - GameState.expenses
	%MoneyLabel.text = "$%d (%+d/день)" % [GameState.money, balance]
	%MoneyLabel.tooltip_text = "Доход: +$%d/день
Содержание дорог и служб: −$%d/день" 			% [GameState.income, GameState.expenses]
	if GameState.money < 0:
		%MoneyLabel.add_theme_color_override(&"font_color", DEBT_COLOR)
	else:
		%MoneyLabel.remove_theme_color_override(&"font_color")
	%DayLabel.text = "День %d" % GameState.day
	%PopLabel.text = "Жители: %d" % GameState.population
	%JobsLabel.text = "Работа: C %d · I %d" % [GameState.jobs_commercial, GameState.jobs_industrial]
	var utilities: Utilities = GameState.utilities
	_show_resource(%PowerLabel, "Свет", utilities.power_use, utilities.power_supply, utilities.unpowered_count)
	_show_resource(%WaterLabel, "Вода", utilities.water_use, utilities.water_supply, utilities.no_water_count)
	_show_hints()
	%TaxLabel.text = "Налог %d%%" % GameState.tax_rate
	%TaxDown.disabled = GameState.tax_rate <= Economy.MIN_TAX_RATE
	%TaxUp.disabled = GameState.tax_rate >= Economy.MAX_TAX_RATE
	var demands: Array[float] = [GameState.demand_r, GameState.demand_c, GameState.demand_i]
	for i: int in _demand_bars.size():
		_demand_bars[i].value = demands[i]
		_demand_bars[i].tooltip_text = "Спрос %s: %+.2f" % [DEMANDS[i].name, demands[i]]


## «Свет 40/100»: потребление / запас; красным, если кому-то не хватило.
func _show_resource(label: Label, title: String, use: int, supply: int, short_count: int) -> void:
	label.text = "%s %d/%d" % [title, use, supply]
	label.tooltip_text = "%s: потребление %d из %d" % [title, use, supply]
	if short_count > 0:
		label.add_theme_color_override(&"font_color", SHORTAGE_COLOR)
		label.tooltip_text += "
Не хватило: %d зд." % short_count
	else:
		label.remove_theme_color_override(&"font_color")


func _show_hints() -> void:
	for child: Node in %Hints.get_children():
		child.queue_free()
	var hints: Array[String] = Hints.build()
	for text: String in hints:
		var label := Label.new()
		label.text = "• " + text
		%Hints.add_child(label)
	%HintsPanel.visible = not hints.is_empty()


func _show_overlay(overlay: int) -> void:
	%OverlayLabel.text = "Слой: %s [V]" % ZoneVisualizer.OVERLAY_NAMES[overlay]


func _build_demand_bars() -> void:
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
		var button := _make_button(entry.name)
		var speed: int = entry.speed
		button.pressed.connect(func() -> void:
			SimClock.set_speed(speed)
			# Повторный клик по активной кнопке не должен её «отжимать».
			_sync_speed_buttons(SimClock.speed))
		%Speed.add_child(button)
		_speed_buttons[speed] = button


func _build_tool_buttons() -> void:
	for entry: Dictionary in TOOLS:
		var mode: int = entry.mode
		var text: String = "%s [%s]" % [entry.name, entry.key]
		var cost: int = BuildTool.cost_of(mode)
		if cost > 0:
			text += "\n$%d" % cost
		var button := _make_button(text)
		button.pressed.connect(func() -> void:
			Events.tool_requested.emit(mode)
			_sync_tool_buttons())
		%Tools.add_child(button)
		_tool_buttons[mode] = button


## Служебные здания из каталога: название и цена.
func _build_service_buttons() -> void:
	%Tools.add_child(VSeparator.new())
	# Сначала станции (у них service = NONE), потом службы в порядке, в каком они нужны городу.
	var types: Array[BuildingData] = BuildingCatalog.buildable_types().duplicate()
	types.sort_custom(func(a: BuildingData, b: BuildingData) -> bool:
		return a.service < b.service or (a.service == b.service and a.id < b.id))
	for data: BuildingData in types:
		var button := _make_button("%s
$%d" % [data.display_name, data.cost])
		button.tooltip_text = "Содержание: $%d/день" % data.upkeep
		var type_id: StringName = data.id
		button.pressed.connect(func() -> void:
			Events.building_place_requested.emit(type_id)
			_sync_tool_buttons())
		%Tools.add_child(button)
		_service_buttons[type_id] = button


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	# Без фокуса: иначе Пробел нажимал бы последнюю кнопку вместо паузы.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_tool_mode_changed(mode: int, type_id: StringName) -> void:
	_current_tool = mode
	_current_type = type_id
	_sync_tool_buttons()


func _sync_tool_buttons() -> void:
	for mode: int in _tool_buttons:
		_tool_buttons[mode].set_pressed_no_signal(mode == _current_tool)
	var placing: bool = _current_tool == BuildTool.Mode.PLACE
	for type_id: StringName in _service_buttons:
		_service_buttons[type_id].set_pressed_no_signal(placing and type_id == _current_type)


func _sync_speed_buttons(speed: int) -> void:
	for value: int in _speed_buttons:
		_speed_buttons[value].set_pressed_no_signal(value == speed)
