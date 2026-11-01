class_name FilterPanel
extends HBoxContainer
## Вкладка «Фильтры» нижней панели (как карты данных в SimCity и инфо-виды в Cities: Skylines):
## карточки — что показать на карте (свет, вода, пробки, службы, цена земли, загрязнение, шум),
## справа — легенда выбранного фильтра: цифры по городу и что значат цвета.
## Слой меняет ZoneVisualizer по Events.overlay_requested; панель только просит и показывает.

const FILTERS: Array[Dictionary] = [
	{"overlay": ZoneVisualizer.Overlay.POWER, "name": "Свет", "icon": "stat_power"},
	{"overlay": ZoneVisualizer.Overlay.WATER, "name": "Вода", "icon": "stat_water"},
	{"overlay": ZoneVisualizer.Overlay.TRAFFIC, "name": "Пробки", "icon": "stat_traffic"},
	{"overlay": ZoneVisualizer.Overlay.SERVICES, "name": "Службы", "icon": "health_01"},
	{"overlay": ZoneVisualizer.Overlay.LAND_VALUE, "name": "Цена земли", "icon": "stat_money"},
	{"overlay": ZoneVisualizer.Overlay.POLLUTION, "name": "Загрязнение", "icon": "tool_zone_i"},
	{"overlay": ZoneVisualizer.Overlay.NOISE, "name": "Шум", "icon": "tool_highway"},
]
const CARD_SIZE := Vector2(100, 78)
const LEGEND_WIDTH: float = 300.0
## Квадратик цвета в легенде, px.
const SWATCH: float = 14.0
## С такого шума дом считается шумным (как в карточке «Инфо»).
const NOISY: int = InfoPanel.BAD_LEVEL

var overlay: int = ZoneVisualizer.Overlay.ZONES

var _cards: Dictionary[int, Button] = {}
var _legend := VBoxContainer.new()
## Цвета легенды — в два столбца, чтобы панель не росла вверх.
var _swatches := GridContainer.new()


func _init() -> void:
	add_theme_constant_override(&"separation", 8)
	for filter: Dictionary in FILTERS:
		var mode: int = filter.overlay
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.theme_type_variation = &"Card"
		card.custom_minimum_size = CARD_SIZE
		# Легенда бывает выше карточек — карточки не растягиваем.
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiTheme.card_styles(card, "filters", filter.icon)
		card.pressed.connect(func() -> void:
			# Повторный клик по выбранному фильтру — обратно к обычной карте (зоны).
			Events.overlay_requested.emit(ZoneVisualizer.Overlay.ZONES if overlay == mode else mode))
		add_child(card)
		_cards[mode] = card
	add_child(VSeparator.new())
	_legend.custom_minimum_size = Vector2(LEGEND_WIDTH, 0)
	_legend.add_theme_constant_override(&"separation", 3)
	_legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_legend)


func _ready() -> void:
	Events.overlay_changed.connect(func(mode: int) -> void:
		overlay = mode
		refresh())
	Events.stats_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	refresh()


## Карточки (короткая цифра под названием) и легенда выбранного фильтра.
func refresh() -> void:
	for filter: Dictionary in FILTERS:
		var mode: int = filter.overlay
		var summary: Array = _summary(mode)
		var card: Button = _cards[mode]
		card.text = "%s\n%s" % [filter.name, summary[0]]
		card.tooltip_text = "Показать на карте: %s" % String(filter.name).to_lower()
		card.set_pressed_no_signal(mode == overlay)
		if summary[1]:
			card.add_theme_color_override(&"font_color", UiTheme.BAD)
		else:
			card.remove_theme_color_override(&"font_color")
	_fill_legend()


## Короткая цифра для карточки: [текст, плохо ли].
func _summary(mode: int) -> Array:
	var utilities: Utilities = GameState.utilities
	var traffic: Traffic = GameState.traffic
	match mode:
		ZoneVisualizer.Overlay.POWER:
			return [_load_text(utilities.power_use, utilities.power_supply),
					utilities.unpowered_count > 0 or utilities.power_use > utilities.power_supply]
		ZoneVisualizer.Overlay.WATER:
			return [_load_text(utilities.water_use, utilities.water_supply),
					utilities.no_water_count > 0 or utilities.water_use > utilities.water_supply]
		ZoneVisualizer.Overlay.TRAFFIC:
			if traffic.jammed_cells > 0:
				return ["на %d кл." % traffic.jammed_cells, true]
			return ["свободно", false]
		ZoneVisualizer.Overlay.SERVICES:
			var missing: int = _services_missing().size()
			return ["не хватает: %d" % missing if missing > 0 else "в норме", missing > 0]
		ZoneVisualizer.Overlay.LAND_VALUE:
			var value: int = GameState.land.average_value(GameState.grid)
			return ["%d / 100" % value if value >= 0 else "—", false]
		ZoneVisualizer.Overlay.POLLUTION:
			var homes: int = _homes_at_least(GameState.land.pollution, Growth.MAX_HOME_POLLUTION)
			return ["домов: %d" % homes if homes > 0 else "чисто", homes > 0]
		ZoneVisualizer.Overlay.NOISE:
			var homes: int = _homes_at_least(GameState.land.noise, NOISY)
			return ["домов: %d" % homes if homes > 0 else "тихо", homes > 0]
	return ["", false]


func _fill_legend() -> void:
	for holder: Node in [_legend, _swatches]:
		for child: Node in holder.get_children():
			holder.remove_child(child)
			# Сетку цветов не удаляем — она переиспользуется и встаёт в конец легенды заново.
			if child != _swatches:
				child.queue_free()
	var filter: Dictionary = {}
	for entry: Dictionary in FILTERS:
		if entry.overlay == overlay:
			filter = entry
	if filter.is_empty():
		_add_title("Фильтры карты")
		_add_line("Выберите, что показать на карте.")
		_add_line("Клавиша V — открыть или закрыть фильтры.")
		return
	# У света и воды заголовок — у шкалы (UtilityMeter: «Электричество», «Вода»).
	if overlay not in [ZoneVisualizer.Overlay.POWER, ZoneVisualizer.Overlay.WATER]:
		_add_title(filter.name)
	_swatches.columns = 2
	_swatches.add_theme_constant_override(&"h_separation", 14)
	_swatches.add_theme_constant_override(&"v_separation", 2)
	var utilities: Utilities = GameState.utilities
	var traffic: Traffic = GameState.traffic
	match overlay:
		ZoneVisualizer.Overlay.POWER:
			_add_meter(UtilityMeter.Kind.POWER)
			_add_swatch(ZoneVisualizer.POWER_SOURCE, "электростанция")
			_add_swatch(ZoneVisualizer.SERVED, "есть свет")
			_add_swatch(ZoneVisualizer.UNSERVED, "нет света")
			_add_swatch(ZoneVisualizer.POWER_ROAD, "дорога со светом")
		ZoneVisualizer.Overlay.WATER:
			_add_meter(UtilityMeter.Kind.WATER)
			_add_swatch(ZoneVisualizer.WATER_SOURCE, "водокачка (нужен свет)")
			_add_swatch(ZoneVisualizer.SERVED, "есть вода")
			_add_swatch(ZoneVisualizer.UNSERVED, "нет воды")
			_add_swatch(ZoneVisualizer.WATER_ROAD, "дорога с водой")
		ZoneVisualizer.Overlay.TRAFFIC:
			_add_line("Клеток с пробкой: %d" % traffic.jammed_cells, traffic.jammed_cells > 0)
			_add_line("До работы в среднем: %.1f (норма до %d)" % [traffic.average_commute, roundi(Traffic.OK_COMMUTE)],
					traffic.average_commute > Traffic.OK_COMMUTE)
			_add_line("Далеко до работы: %d%% работников" % roundi(traffic.long_commute_share * 100.0))
			if traffic.total_workers > 0.0:
				var walk: float = traffic.walkers / traffic.total_workers
				var bike: float = traffic.cyclists / traffic.total_workers
				_add_line("Машина %d%% · велосипед %d%% · пешком %d%%" % [
						roundi((1.0 - walk - bike) * 100.0), roundi(bike * 100.0), roundi(walk * 100.0)])
			_add_swatch(ZoneVisualizer.TRAFFIC_FREE, "свободно")
			_add_swatch(ZoneVisualizer.TRAFFIC_BUSY, "плотно")
			_add_swatch(ZoneVisualizer.TRAFFIC_JAM, "пробка")
			_add_swatch(ZoneVisualizer.LONG_COMMUTE, "дом далеко от работы")
		ZoneVisualizer.Overlay.SERVICES:
			for service: BuildingData.Service in Services.REQUIRED_FROM:
				var needed_from: int = Services.REQUIRED_FROM[service]
				var lower: String = Hints.SERVICE_NAMES[service]
				var name: String = lower.left(1).to_upper() + lower.substr(1)
				if GameState.population < needed_from:
					_add_line("%s: нужна с %d жителей" % [name, needed_from])
				else:
					var share: float = GameState.service_coverage.get(service, 0.0)
					_add_line("%s: покрыто %d%% домов" % [name, roundi(share * 100.0)], service in _services_missing())
			_add_swatch(ZoneVisualizer.SERVICE_BUILDING, "здание службы")
			_add_swatch(ZoneVisualizer.COVERAGE_COLOR, "покрытие (гуще — больше служб)")
		ZoneVisualizer.Overlay.LAND_VALUE:
			var value: int = GameState.land.average_value(GameState.grid)
			_add_line("Средняя под домами: %s" % ("%d / 100" % value if value >= 0 else "—"))
			_add_line("Дороже: парки, службы, вода рядом")
			_add_line("Дешевле: заводы, шумные дороги")
			_add_swatch(ZoneVisualizer.VALUE_LOW, "дёшево")
			_add_swatch(ZoneVisualizer.VALUE_MID, "обычно")
			_add_swatch(ZoneVisualizer.VALUE_HIGH, "дорого")
		ZoneVisualizer.Overlay.POLLUTION:
			var homes: int = _homes_at_least(GameState.land.pollution, Growth.MAX_HOME_POLLUTION)
			_add_line("Домов в грязи: %d" % homes, homes > 0)
			_add_line("Жильё не растёт, где загрязнение %d+" % Growth.MAX_HOME_POLLUTION)
			_add_swatch(Color(ZoneVisualizer.POLLUTION_COLOR, 0.35), "слабое")
			_add_swatch(Color(ZoneVisualizer.POLLUTION_COLOR, 0.85), "сильное")
		ZoneVisualizer.Overlay.NOISE:
			var homes: int = _homes_at_least(GameState.land.noise, NOISY)
			_add_line("Домов в шуме: %d" % homes, homes > 0)
			_add_line("Шум — от дорог и заводов, жителям хуже")
			_add_swatch(Color(ZoneVisualizer.NOISE_COLOR, 0.35), "тише")
			_add_swatch(Color(ZoneVisualizer.NOISE_COLOR, 0.85), "шумно")


## Службы, которые городу уже нужны, но покрывают меньше Hints.LOW_COVERAGE домов.
func _services_missing() -> Array[BuildingData.Service]:
	var result: Array[BuildingData.Service] = []
	for service: BuildingData.Service in Services.REQUIRED_FROM:
		if GameState.population >= Services.REQUIRED_FROM[service] \
				and GameState.service_coverage.get(service, 0.0) < Hints.LOW_COVERAGE:
			result.append(service)
	return result


## Сколько домов с жителями, где слой (загрязнение, шум) не меньше limit.
func _homes_at_least(layer: PackedByteArray, limit: int) -> int:
	var grid: CityGrid = GameState.grid
	var land: LandValue = GameState.land
	if layer.size() != grid.size * grid.size:
		return 0
	var count: int = 0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.population > 0 and not building.abandoned \
				and land.building_value(layer, grid, building) >= limit:
			count += 1
	return count


## Загрузка станций для карточки: «загрузка 93%», «нет станций» или «—».
static func _load_text(use: int, supply: int) -> String:
	if supply > 0:
		return "загрузка %d%%" % roundi(100.0 * use / supply)
	return "нет станций" if use > 0 else "—"


## Шкала потребления и мощности, как в Cities: Skylines (UtilityMeter).
func _add_meter(kind: UtilityMeter.Kind) -> void:
	var meter := UtilityMeter.new(kind)
	_legend.add_child(meter)


func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Title"
	_legend.add_child(label)


func _add_line(text: String, bad: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bad:
		label.add_theme_color_override(&"font_color", UiTheme.BAD)
	_legend.add_child(label)


func _add_swatch(color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var swatch := ColorRect.new()
	# Цвет слоя полупрозрачный — в легенде кладём его на «бумагу», как на карте на землю.
	swatch.color = Color(UiTheme.PAPER, 1.0).lerp(Color(color, 1.0), maxf(color.a, 0.35))
	swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	row.add_child(label)
	_swatches.add_child(row)
	if _swatches.get_parent() == null:
		_legend.add_child(_swatches)
