class_name BudgetPanel
extends PanelContainer
## Вкладка «Бюджет», как экономика в Cities: Skylines: доходы и расходы за игровой час по статьям
## (GameState.budget, Budget.compute) — кольцо долей и список с суммами и долями; налог ползунком;
## внизу — история по часам (GameState.budget_history): казна или доходы и расходы, за 24 ч, 3 дня
## или неделю. Открывается кнопкой «Бюджет» внизу или щелчком по деньгам; Esc или × — закрыть.

const WIDTH: float = 900.0
## Отступ сверху — под верхней панелью, px.
const TOP: float = 100.0
## Высота списка статей (длиннее — прокрутка).
const LIST_HEIGHT: float = 134.0
const SPANS: Array[Array] = [[24, "24 ч"], [72, "3 дня"], [168, "Неделя"]]

var _balance := Label.new()
var _treasury := Label.new()
var _income_total := Label.new()
var _expense_total := Label.new()
var _income_donut := BudgetCharts.Donut.new()
var _expense_donut := BudgetCharts.Donut.new()
var _income_rows := GridContainer.new()
var _expense_rows := GridContainer.new()
var _income_empty := Label.new()
var _expense_empty := Label.new()
var _tax_slider := HSlider.new()
var _tax_value := Label.new()
var _tax_hint := Label.new()
var chart := BudgetCharts.TimeChart.new()
var _mode_buttons: Array[Button] = []
var _span_buttons: Array[Button] = []
## id статьи → [образец цвета, иконка, название, количество, сумма, доля].
var _rows: Dictionary[StringName, Array] = {}
## Порядок статей в кольце — для подсветки строки при наведении на сегмент.
var _income_order: Array[StringName] = []
var _expense_order: Array[StringName] = []


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	# Под верхней панелью, по центру; нижняя панель инструментов на это время закрыта.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = TOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	column.add_child(_build_head())
	column.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	column.add_child(body)
	body.add_child(_build_section("Доходы", "налоги с жителей и работы", _income_total, _income_donut, _income_rows,
			_income_empty, "Налогов пока нет: стройте дома и работу", true))
	body.add_child(VSeparator.new())
	body.add_child(_build_section("Расходы", "содержание дорог и зданий", _expense_total, _expense_donut, _expense_rows,
			_expense_empty, "Расходов пока нет", false))
	column.add_child(HSeparator.new())
	column.add_child(_build_chart_bar())
	column.add_child(chart)
	_income_donut.hovered.connect(func(index: int) -> void: _highlight_row(_income_order, index))
	_expense_donut.hovered.connect(func(index: int) -> void: _highlight_row(_expense_order, index))


func _build_head() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	head.add_child(UiTheme.make_chip_icon("stat_money", 34))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = "Бюджет города"
	title.theme_type_variation = &"Title"
	titles.add_child(title)
	var caption := Label.new()
	caption.text = "Все доходы и расходы — за игровой час"
	caption.theme_type_variation = &"Caption"
	titles.add_child(caption)
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 0)
	head.add_child(right)
	_balance.theme_type_variation = &"Title"
	_balance.add_theme_font_size_override(&"font_size", 22)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_balance)
	_treasury.theme_type_variation = &"Caption"
	_treasury.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_treasury)
	var close := Button.new()
	close.text = "×"
	close.theme_type_variation = &"Small"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.tooltip_text = "Закрыть [Esc]"
	close.pressed.connect(hide)
	head.add_child(close)
	return head


func _build_section(title_text: String, caption_text: String, total: Label, donut: BudgetCharts.Donut,
		rows: GridContainer, empty: Label, empty_text: String, with_tax: bool) -> Control:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override(&"separation", 6)
	var head := HBoxContainer.new()
	section.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"Title"
	titles.add_child(title)
	var caption := Label.new()
	caption.text = caption_text
	caption.theme_type_variation = &"Caption"
	titles.add_child(caption)
	total.theme_type_variation = &"Title"
	total.add_theme_font_size_override(&"font_size", 18)
	total.add_theme_color_override(&"font_color", BudgetCharts.TimeChart.INCOME_COLOR if with_tax
			else BudgetCharts.TimeChart.EXPENSE_COLOR)
	total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(total)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	section.add_child(body)
	donut.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(donut)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	rows.columns = 6
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"h_separation", 6)
	rows.add_theme_constant_override(&"v_separation", 1)
	list.add_child(rows)
	empty.text = empty_text
	empty.theme_type_variation = &"Caption"
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(empty)
	if with_tax:
		section.add_child(_build_tax())
	return section


func _build_tax() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	var label := Label.new()
	label.text = "Налог"
	row.add_child(label)
	_tax_slider.min_value = Economy.MIN_TAX_RATE
	_tax_slider.max_value = Economy.MAX_TAX_RATE
	_tax_slider.step = 1
	_tax_slider.tick_count = (Economy.MAX_TAX_RATE - Economy.MIN_TAX_RATE) / 5 + 1
	_tax_slider.ticks_on_borders = true
	_tax_slider.focus_mode = Control.FOCUS_NONE
	_tax_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tax_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tax_slider.value_changed.connect(func(value: float) -> void:
		if roundi(value) != GameState.tax_rate:
			Events.tax_rate_requested.emit(roundi(value)))
	row.add_child(_tax_slider)
	_tax_value.custom_minimum_size = Vector2(40, 0)
	_tax_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_tax_value)
	_tax_hint.theme_type_variation = &"Caption"
	box.add_child(_tax_hint)
	return box


func _build_chart_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 6)
	var title := Label.new()
	title.text = "По часам"
	title.theme_type_variation = &"Title"
	bar.add_child(title)
	var modes: Array[Array] = [[BudgetCharts.TimeChart.Mode.MONEY, "Казна"], [BudgetCharts.TimeChart.Mode.FLOW,
			"Доходы и расходы"]]
	for item: Array in modes:
		var button := _small_toggle(item[1])
		var chart_mode: int = item[0]
		button.pressed.connect(func() -> void: set_mode(chart_mode))
		bar.add_child(button)
		_mode_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	for item: Array in SPANS:
		var button := _small_toggle(item[1])
		var hours: int = item[0]
		button.pressed.connect(func() -> void: set_span(hours))
		bar.add_child(button)
		_span_buttons.append(button)
	set_mode(BudgetCharts.TimeChart.Mode.FLOW)
	set_span(24)
	return bar


func _small_toggle(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"Small"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	return button


func set_mode(chart_mode: int) -> void:
	chart.mode = chart_mode as BudgetCharts.TimeChart.Mode
	for i: int in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == chart_mode)
	chart.queue_redraw()


func set_span(hours: int) -> void:
	chart.span_hours = hours
	for i: int in _span_buttons.size():
		_span_buttons[i].set_pressed_no_signal(SPANS[i][0] == hours)
	chart.queue_redraw()


func _ready() -> void:
	Events.stats_changed.connect(func() -> void:
		if visible:
			refresh())
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())


func toggle() -> void:
	visible = not visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"tool_cancel"):
		hide()
		get_viewport().set_input_as_handled()


## Цифры, кольца, списки и график — из GameState.
func refresh() -> void:
	var budget: Budget = GameState.budget
	var balance: float = budget.income_per_hour() - budget.expenses_per_hour()
	_balance.text = BudgetCharts.money_text(balance, true) + "/ч"
	_balance.add_theme_color_override(&"font_color", BudgetCharts.TimeChart.INCOME_COLOR if balance >= 0.0
			else BudgetCharts.TimeChart.EXPENSE_COLOR)
	_treasury.text = "В казне " + BudgetCharts.money_text(GameState.money)
	_income_total.text = BudgetCharts.money_text(budget.income_per_hour(), true) + "/ч"
	_expense_total.text = BudgetCharts.money_text(-budget.expenses_per_hour(), true) + "/ч"
	_income_order = _fill(_income_rows, _income_empty, budget.income, budget.income_per_hour())
	_expense_order = _fill(_expense_rows, _expense_empty, budget.expenses, budget.expenses_per_hour())
	_income_donut.set_data(_segments(budget.income, _income_order), BudgetCharts.short_money(budget.income_per_hour()), "в час")
	_expense_donut.set_data(_segments(budget.expenses, _expense_order), BudgetCharts.short_money(budget.expenses_per_hour()),
			"в час")
	_tax_slider.set_value_no_signal(GameState.tax_rate)
	_tax_value.text = "%d%%" % GameState.tax_rate
	_tax_hint.text = "1%% налога ≈ %s/ч · выше налог — меньше спрос на дома и работу" % BudgetCharts.money_text(
			budget.income_per_hour() / maxf(1.0, GameState.tax_rate))
	chart.set_data(GameState.budget_history, GameState.money, GameState.minutes)


## Строки статей с ненулевой суммой, по убыванию; возвращает их id в этом порядке.
func _fill(grid: GridContainer, empty: Label, items: Array[Budget.Item], total: float) -> Array[StringName]:
	var shown: Array[Budget.Item] = []
	shown.assign(items.filter(func(entry: Budget.Item) -> bool: return entry.per_tick > 0.0001))
	shown.sort_custom(func(a: Budget.Item, b: Budget.Item) -> bool: return a.per_tick > b.per_tick)
	var order: Array[StringName] = []
	for entry: Budget.Item in items:
		_row(grid, entry)
	for entry: Budget.Item in items:
		var cells: Array = _rows[entry.id]
		var visible_row: bool = shown.has(entry)
		for cell: Control in cells:
			cell.visible = visible_row
	for k: int in shown.size():
		var entry: Budget.Item = shown[k]
		order.append(entry.id)
		var cells: Array = _rows[entry.id]
		# Порядок строк — по сумме.
		for c: int in cells.size():
			grid.move_child(cells[c], k * cells.size() + c)
		(cells[3] as Label).text = "%d %s" % [entry.count, entry.unit]
		(cells[4] as Label).text = BudgetCharts.money_text(entry.per_hour())
		(cells[5] as Label).text = "%d%%" % roundi(100.0 * entry.per_hour() / maxf(total, 0.001))
	empty.visible = shown.is_empty()
	return order


## Ячейки строки статьи (создаются один раз).
func _row(grid: GridContainer, entry: Budget.Item) -> void:
	if _rows.has(entry.id):
		return
	var swatch := ColorRect.new()
	swatch.color = entry.color
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := TextureRect.new()
	icon.texture = UiTheme.icon(entry.icon)
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var title := Label.new()
	title.text = entry.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := Label.new()
	count.theme_type_variation = &"Caption"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var amount := Label.new()
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.custom_minimum_size = Vector2(64, 0)
	var share := Label.new()
	share.theme_type_variation = &"Caption"
	share.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	share.custom_minimum_size = Vector2(34, 0)
	var cells: Array = [swatch, icon, title, count, amount, share]
	for cell: Control in cells:
		grid.add_child(cell)
	_rows[entry.id] = cells


func _segments(items: Array[Budget.Item], order: Array[StringName]) -> Array[Array]:
	var result: Array[Array] = []
	for id: StringName in order:
		for entry: Budget.Item in items:
			if entry.id == id:
				result.append([entry.per_hour(), entry.color, entry.name])
	return result


## Наведение на сегмент кольца — его строка жирнее.
func _highlight_row(order: Array[StringName], index: int) -> void:
	for k: int in order.size():
		var label: Label = _rows[order[k]][2]
		if k == index:
			label.add_theme_color_override(&"font_color", UiTheme.ACCENT_DARK)
		else:
			label.remove_theme_color_override(&"font_color")


## Строка статьи «название → сумма в час» (для проверок); только видимые.
func rows_text() -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for id: StringName in _rows:
		var cells: Array = _rows[id]
		if (cells[2] as Control).visible:
			result[(cells[2] as Label).text] = (cells[4] as Label).text
	return result


func balance_text() -> String:
	return _balance.text
