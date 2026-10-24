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

var _tool_buttons: Dictionary[int, Button] = {}
var _speed_buttons: Dictionary[int, Button] = {}
var _demand_bars: Array[ProgressBar] = []
var _current_tool: int = BuildTool.Mode.NONE


func _ready() -> void:
	_build_demand_bars()
	_build_speed_buttons()
	_build_tool_buttons()
	%TaxDown.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate - 1))
	%TaxUp.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate + 1))
	Events.stats_changed.connect(_refresh_stats)
	Events.tool_mode_changed.connect(_on_tool_mode_changed)
	Events.speed_changed.connect(_sync_speed_buttons)
	_refresh_stats()
	_sync_tool_buttons()
	_sync_speed_buttons(SimClock.speed)


func _refresh_stats() -> void:
	var balance: int = GameState.income - GameState.expenses
	%MoneyLabel.text = "$%d (%+d/день)" % [GameState.money, balance]
	if GameState.money < 0:
		%MoneyLabel.add_theme_color_override(&"font_color", DEBT_COLOR)
	else:
		%MoneyLabel.remove_theme_color_override(&"font_color")
	%DayLabel.text = "День %d" % GameState.day
	%PopLabel.text = "Жители: %d" % GameState.population
	%JobsLabel.text = "Работа: C %d · I %d" % [GameState.jobs_commercial, GameState.jobs_industrial]
	%TaxLabel.text = "Налог %d%%" % GameState.tax_rate
	var demands: Array[float] = [GameState.demand_r, GameState.demand_c, GameState.demand_i]
	for i: int in _demand_bars.size():
		_demand_bars[i].value = demands[i]
		_demand_bars[i].tooltip_text = "Спрос %s: %+.2f" % [DEMANDS[i].name, demands[i]]


func _build_demand_bars() -> void:
	for entry: Dictionary in DEMANDS:
		var label := Label.new()
		label.text = entry.name
		%Demand.add_child(label)
		var bar := ProgressBar.new()
		bar.min_value = -1.0
		bar.max_value = 1.0
		bar.step = 0.01
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(60, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = entry.color
		bar.add_theme_stylebox_override(&"fill", fill)
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


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	# Без фокуса: иначе Пробел нажимал бы последнюю кнопку вместо паузы.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_tool_mode_changed(mode: int) -> void:
	_current_tool = mode
	_sync_tool_buttons()


func _sync_tool_buttons() -> void:
	for mode: int in _tool_buttons:
		_tool_buttons[mode].set_pressed_no_signal(mode == _current_tool)


func _sync_speed_buttons(speed: int) -> void:
	for value: int in _speed_buttons:
		_speed_buttons[value].set_pressed_no_signal(value == speed)
