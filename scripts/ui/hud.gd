class_name Hud
extends CanvasLayer
## Интерфейс: верхняя панель с показателями, подсказки, нижняя панель с вкладками инструментов.
## Состояние напрямую не меняет: только сигналы Events и публичные SimClock.set_speed() / SaveManager.

## Вкладки инструментов. Инструменты — режимы BuildTool; здания — служебные из каталога
## («utilities» — дают свет или воду, «services» — службы).
const TABS: Array[Dictionary] = [
	{"id": "roads", "name": "Дороги", "tools": [
		{"mode": BuildTool.Mode.ROAD, "name": "Улица", "key": "R"},
		{"mode": BuildTool.Mode.ROAD_AVENUE, "name": "Проспект", "key": "T"},
		{"mode": BuildTool.Mode.ROAD_HIGHWAY, "name": "Шоссе", "key": "Y"},
	]},
	{"id": "zones", "name": "Зоны", "tools": [
		{"mode": BuildTool.Mode.ZONE_R, "name": "Жилая", "key": "1"},
		{"mode": BuildTool.Mode.ZONE_C, "name": "Коммерция", "key": "2"},
		{"mode": BuildTool.Mode.ZONE_I, "name": "Промзона", "key": "3"},
		{"mode": BuildTool.Mode.DEZONE, "name": "Снять зону", "key": "4"},
		{"mode": BuildTool.Mode.ZONE_R_HIGH, "name": "Многоэтажки", "key": "5"},
		{"mode": BuildTool.Mode.ZONE_C_HIGH, "name": "Торговые дома", "key": "6"},
		{"mode": BuildTool.Mode.ZONE_O, "name": "Офисы", "key": "7"},
	]},
	{"id": "utilities", "name": "Свет и вода", "buildings": "utilities"},
	{"id": "services", "name": "Службы", "buildings": "services"},
	{"id": "parks", "name": "Парки", "buildings": "parks"},
]
const SPEEDS: Array[Dictionary] = [
	{"speed": 0, "name": "Пауза"},
	{"speed": 1, "name": "×1"},
	{"speed": 3, "name": "×3"},
]
## Полоски спроса: подпись и цвет (как у зон).
const DEMANDS: Array[Dictionary] = [
	{"name": "R", "color": Color(0.25, 0.75, 0.3)},
	{"name": "C", "color": Color(0.25, 0.5, 0.95)},
	{"name": "I", "color": Color(0.95, 0.75, 0.2)},
]
## Размер карточки инструмента.
const CARD_SIZE := Vector2(104, 58)
## Сколько секунд висит сообщение о сохранении.
const TOAST_SECONDS: float = 2.5

var _tool_buttons: Dictionary[int, Button] = {}
var _service_buttons: Dictionary[StringName, Button] = {}
var _speed_buttons: Dictionary[int, Button] = {}
var _demand_bars: Array[DemandBar] = []
## Вкладки: id → кнопка вкладки и ряд её карточек.
var _tab_buttons: Dictionary[String, Button] = {}
var _tab_cards: Dictionary[String, HBoxContainer] = {}
var _active_tab: String = ""
var _current_tool: int = BuildTool.Mode.NONE
var _current_type: StringName = &""
var _overlay_label := Label.new()
var _save_dialog := SaveDialog.new()
var _new_city_confirm := ConfirmationDialog.new()
var _toast := PanelContainer.new()
var _toast_label := Label.new()
var _info := InfoPanel.new()
## Плашка звания (фаза 10) — создаётся кодом рядом с «Жителями»; счастье — в плашке «Жители».
var _rank_label := Label.new()
## Номер последнего сообщения: старый таймер не прячет новое сообщение.
var _toast_serial: int = 0
## Скорость до окна подтверждения «Новый город».
var _speed_before_confirm: int = 1


func _ready() -> void:
	var theme: Theme = UiTheme.build()
	$Root.theme = theme
	_build_demand_bars()
	_build_speed_buttons()
	_build_tabs()
	_build_bottom_extras()
	_build_city_controls()
	$Root.add_child(_info)
	_build_rank_chips()
	Events.rank_changed.connect(_on_rank_changed)
	_new_city_confirm.theme = theme
	for window: Node in _save_dialog.find_children("*", "Window", true, false):
		(window as Window).theme = theme
	%TaxDown.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate - 1))
	%TaxUp.pressed.connect(func() -> void: Events.tax_rate_requested.emit(GameState.tax_rate + 1))
	Events.stats_changed.connect(_refresh_stats)
	Events.tool_mode_changed.connect(_on_tool_mode_changed)
	Events.speed_changed.connect(_sync_speed_buttons)
	Events.overlay_changed.connect(_show_overlay)
	_show_overlay(ZoneVisualizer.Overlay.ZONES)
	_select_tab("roads")
	_refresh_stats()
	_sync_tool_buttons()
	_sync_speed_buttons(SimClock.speed)


# --- Верхняя панель ---

func _refresh_stats() -> void:
	var balance: int = GameState.income - GameState.expenses
	%MoneyLabel.text = "$%d (%+d/день)" % [GameState.money, balance]
	var money_tip: String = "Доход: +$%d/день\nСодержание дорог и служб: −$%d/день"
	%MoneyLabel.tooltip_text = money_tip % [GameState.income, GameState.expenses]
	_mark_bad(%MoneyLabel, GameState.money < 0)
	%DayLabel.text = "%s · День %d" % [GameState.city_name, GameState.day]
	%PopLabel.text = "Жители: %d" % GameState.population
	%JobsLabel.text = "Работа: C %d · I %d" % [GameState.jobs_commercial, GameState.jobs_industrial]
	var utilities: Utilities = GameState.utilities
	_show_resource(%PowerLabel, "Свет", utilities.power_use, utilities.power_supply, utilities.unpowered_count)
	_show_resource(%WaterLabel, "Вода", utilities.water_use, utilities.water_supply, utilities.no_water_count)
	_show_traffic()
	_show_hints()
	_show_rank()
	_sync_locks()
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
		label.tooltip_text += "\nНе хватило: %d зд." % short_count
	_mark_bad(label, short_count > 0)


## «Пробки 3 · до работы 18»: клетки с пробкой и среднее время до работы; красным при пробках.
func _show_traffic() -> void:
	var traffic: Traffic = GameState.traffic
	%TrafficLabel.text = "Пробки %d · до работы %d" % [traffic.jammed_cells, roundi(traffic.average_commute)]
	var tip: String = "Клеток дорог с пробкой: %d\nСреднее время до работы: %.1f (норма до %d)\nДалеко до работы: %d%% работников"
	%TrafficLabel.tooltip_text = tip % [traffic.jammed_cells, traffic.average_commute,
			roundi(Traffic.OK_COMMUTE), roundi(traffic.long_commute_share * 100.0)]
	_mark_bad(%TrafficLabel, traffic.jammed_cells > 0)


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
			_rank_label.tooltip_text += "
Откроет: " + ", ".join(next_unlocks)
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
			var about: String = "%s: пропускает %d поездок, скорость ×%.1f, содержание $%.1f/кл. в день" % [
					RoadTypes.NAMES[road_type], RoadTypes.CAPACITY[road_type], 1.0 / RoadTypes.TRAVEL_COST[road_type],
					RoadTypes.UPKEEP[road_type]]
			if road_type == RoadTypes.Type.HIGHWAY:
				about += "
Дома к шоссе не подключаются"
			about += "
Протяните поверх дороги другого типа — она заменится"
			_tool_buttons[mode].tooltip_text = ("Откроется на звании «%s» (%d жителей)
" % [Ranks.NAMES[rank],
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


func _show_hints() -> void:
	for child: Node in %Hints.get_children():
		child.queue_free()
	var hints: Array[String] = Hints.build()
	for text: String in hints:
		var label := Label.new()
		label.text = "• " + text
		%Hints.add_child(label)
	%HintsPanel.visible = not hints.is_empty()


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
		var button := _make_button(tab.name, &"Tab")
		UiTheme.tab_styles(button, id)
		button.pressed.connect(func() -> void:
			# Повторный клик по открытой вкладке сворачивает панель.
			_select_tab("" if _active_tab == id else id))
		%Tabs.add_child(button)
		_tab_buttons[id] = button


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
		return a.cost < b.cost or (a.cost == b.cost and a.id < b.id))
	return result


func _add_tool_card(row: HBoxContainer, category: String, tool: Dictionary) -> void:
	var mode: int = tool.mode
	var cost: int = BuildTool.cost_of(mode)
	var price: String = ("$%d/кл. · " % cost) if cost > 0 else ""
	var button := _make_card("%s\n%s%s" % [tool.name, price, tool.key], category)
	button.pressed.connect(func() -> void:
		Events.tool_requested.emit(mode)
		_sync_tool_buttons())
	row.add_child(button)
	_tool_buttons[mode] = button


func _add_building_card(row: HBoxContainer, category: String, data: BuildingData) -> void:
	var button := _make_card("%s\n$%d" % [data.display_name, data.cost], category)
	button.tooltip_text = _service_tooltip(data)
	var type_id: StringName = data.id
	button.pressed.connect(func() -> void:
		Events.building_place_requested.emit(type_id)
		_sync_tool_buttons())
	row.add_child(button)
	_service_buttons[type_id] = button


## «Снос» и переключатель слоя карты — рядом с вкладками, всегда под рукой.
func _build_bottom_extras() -> void:
	%Tabs.add_child(VSeparator.new())
	var bulldoze := _make_card("Снос\nB", "bulldoze")
	bulldoze.custom_minimum_size = Vector2(72, 0)
	bulldoze.pressed.connect(func() -> void:
		Events.tool_requested.emit(BuildTool.Mode.BULLDOZE)
		_sync_tool_buttons())
	%Tabs.add_child(bulldoze)
	_tool_buttons[BuildTool.Mode.BULLDOZE] = bulldoze
	var overlay := _make_button("", &"Small")
	overlay.toggle_mode = false
	overlay.tooltip_text = "Сменить слой карты: зоны, свет, вода, службы, трафик, цена земли, загрязнение, шум"
	overlay.pressed.connect(func() -> void:
		var event := InputEventAction.new()
		event.action = &"overlay_next"
		event.pressed = true
		Input.parse_input_event(event))
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.custom_minimum_size = Vector2(150, 0)
	overlay.add_child(_overlay_label)
	%Tabs.add_child(overlay)
	# Уникальное имя — чтобы находить надпись как %OverlayLabel, хоть она и создана кодом.
	_overlay_label.name = "OverlayLabel"
	_overlay_label.unique_name_in_owner = true
	_overlay_label.owner = self


func _select_tab(id: String) -> void:
	_active_tab = id
	for tab_id: String in _tab_cards:
		_tab_cards[tab_id].visible = tab_id == id
		_tab_buttons[tab_id].set_pressed_no_signal(tab_id == id)
	%ToolPanel.visible = not id.is_empty()


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
	_sync_tool_buttons()


func _sync_tool_buttons() -> void:
	for mode: int in _tool_buttons:
		_tool_buttons[mode].set_pressed_no_signal(mode == _current_tool)
	var placing: bool = _current_tool == BuildTool.Mode.PLACE
	for type_id: StringName in _service_buttons:
		_service_buttons[type_id].set_pressed_no_signal(placing and type_id == _current_type)


func _show_overlay(overlay: int) -> void:
	_overlay_label.text = "Слой: %s [V]" % ZoneVisualizer.OVERLAY_NAMES[overlay]


## Цена, содержание, что даёт и потребляет, радиус и с какого населения нужна служба.
func _service_tooltip(data: BuildingData) -> String:
	var lines: PackedStringArray = ["Цена: $%d, содержание: $%d/день" % [data.cost, data.upkeep]]
	if data.power_supply > 0:
		lines.append("Даёт свет: %d" % data.power_supply)
	if data.water_supply > 0:
		lines.append("Даёт воду: %d" % data.water_supply)
	if data.power_use > 0 or data.water_use > 0:
		lines.append("Потребляет: свет %d, вода %d" % [data.power_use, data.water_use])
	if data.land_value > 0:
		lines.append("Цена земли вокруг: +%d" % data.land_value)
	if data.pollution > 0:
		lines.append("Загрязнение вокруг: %d" % data.pollution)
	if data.service != BuildingData.Service.NONE:
		var needed_from: int = Services.REQUIRED_FROM.get(data.service, 0)
		lines.append("Радиус: %d кл.; нужна городу с %d жителей" % [data.service_radius, needed_from])
	lines.append("Ставится у дороги")
	return "\n".join(lines)


func _make_card(text: String, category: String) -> Button:
	var button := _make_button(text, &"Card")
	button.custom_minimum_size = CARD_SIZE
	UiTheme.card_styles(button, category)
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
	_toast.offset_top = 96.0
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
	_toast.visible = true
	await get_tree().create_timer(TOAST_SECONDS).timeout
	if serial == _toast_serial:
		_toast.visible = false
