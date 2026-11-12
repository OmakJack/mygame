class_name InfoPanel
extends PanelContainer
## Карточка «Инфо» (фаза 9): клик по клетке без инструмента — что на ней и как ей живётся.
## Справа по центру; обновляется с каждым пересчётом города, закрывается крестиком.
## У станции (StationModules) — её модули и кнопки «поставить рядом» (ветряк, насос, служебная
## дорога): кнопка включает постановку модуля на карте (BuildTool, режим MODULE), как в SimCity.

const WIDTH: float = 296.0
## Ниже этого значения показатель хороший (загрязнение, шум) — красим, только если выше.
const BAD_LEVEL: int = 40

var cell := Vector2i(-1, -1)

var _icon := TextureRect.new()
var _title := Label.new()
var _subtitle := Label.new()
var _rows := GridContainer.new()
## Кнопки модулей станции: пересобираются, только когда меняется станция или её модули.
var _modules_box := VBoxContainer.new()
var _module_buttons: Dictionary[StringName, Button] = {}
var _modules_key: String = ""


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -12.0
	offset_top = 28.0
	offset_bottom = 28.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	column.add_child(head)
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 1)
	head.add_child(titles)
	_title.theme_type_variation = &"Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	_subtitle.theme_type_variation = &"Caption"
	titles.add_child(_subtitle)
	var close := Button.new()
	close.text = "×"
	close.theme_type_variation = &"Small"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.tooltip_text = "Закрыть"
	close.pressed.connect(hide)
	head.add_child(close)
	column.add_child(HSeparator.new())
	_rows.columns = 2
	_rows.add_theme_constant_override(&"h_separation", 14)
	_rows.add_theme_constant_override(&"v_separation", 2)
	column.add_child(_rows)
	_modules_box.add_theme_constant_override(&"separation", 4)
	_modules_box.visible = false
	column.add_child(_modules_box)


func _ready() -> void:
	Events.cell_inspected.connect(show_cell)
	Events.stats_changed.connect(func() -> void:
		if visible:
			_refresh())
	Events.grid_reset.connect(hide)


func show_cell(target: Vector2i) -> void:
	cell = target
	_refresh()
	visible = true


func _refresh() -> void:
	var grid: CityGrid = GameState.grid
	if not grid.is_in_bounds(cell):
		hide()
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	var land: LandValue = GameState.land
	# Клик по двору — карточка его дома.
	var building: BuildingInstance = grid.get_building_or_yard(cell)
	var data: BuildingData = BuildingCatalog.get_type(building.type_id) if building != null else null
	_show_modules(building if data != null and StationModules.is_station(data.id) else null)
	if data != null:
		_title.text = data.display_name
		_subtitle.text = _kind(data) + (" · заброшено" if building.abandoned else "")
		_icon.texture = UiTheme.icon(_building_icon(data))
		var lot: CityGrid.Lot = grid.lot_of(building)
		if lot != null and not lot.poly.is_empty():
			_add("Участок", "вдоль дороги под углом, %d кл., дом %d×%d" % [lot.shape.size(), data.size.x, data.size.y])
		elif lot != null and lot.rect.size != building.size:
			var lot_size: Vector2i = lot.building_size()
			_add("Участок", "%d×%d, дом %d×%d, двор %d кл." % [lot_size.x, lot_size.y, data.size.x, data.size.y,
					lot_size.x * lot_size.y - data.area()])
		elif data.area() > 1:
			_add("Участок", "%d×%d (%d кл.)" % [data.size.x, data.size.y, data.area()])
		if building.abandoned:
			_add_abandoned(grid, building, data)
		elif data.population > 0:
			_add("Жители", "%d (%s)" % [data.population, _families_text(LevelStats.families(data.population))])
		if data.jobs > 0:
			_add("Рабочие места", str(data.jobs))
		var power_use: int = StationModules.power_use(building, data)
		if power_use > 0 and not building.abandoned:
			_add("Свет", "%s, %s" % [Utilities.power_text(power_use), "есть" if building.powered else "нет"],
					not building.powered)
		if data.water_use > 0 and not building.abandoned:
			_add("Вода", "%s, %s" % [Utilities.water_text(data.water_use), "есть" if building.has_water else "нет"],
					not building.has_water)
		if data.power_supply > 0:
			_add("Даёт свет", Utilities.power_text(StationModules.power_supply(building, data)))
		if data.water_supply > 0:
			_add("Даёт воду", Utilities.water_text(StationModules.water_supply(building, data)),
					power_use > 0 and not building.powered)
		if StationModules.is_station(data.id):
			_add("Модули", _modules_text(grid, building))
			_add("Достроено", "%d из %d модулей" % [StationModules.module_count(building), StationModules.MAX_MODULES])
			_add("Содержание", "$%d/ч" % roundi(GameTime.per_hour(StationModules.upkeep(building, data))))
		if data.land_value > 0:
			_add("Цена земли вокруг", "+%d" % data.land_value)
		if building.construction_ticks > 0:
			var total: int = maxi(building.construction_total, building.construction_ticks)
			_add("Стройка", "%d%%, ещё %d мин" % [roundi(100.0 * (total - building.construction_ticks) / total),
					building.construction_ticks * GameTime.TICK_MINUTES])
		var left: int = Decay.ticks_left(building)
		if left >= 0 and not building.abandoned:
			_add("Опустеет через", "%s — %s" % [_minutes_text(left * GameTime.TICK_MINUTES),
					"нет дороги" if building.no_road_ticks > 0 else "нет света или воды"], true)
		if not building.abandoned:
			_add_mood(grid, building, data)
	elif grid.is_road(cell):
		var road_type: int = grid.get_road_type(cell)
		_title.text = RoadTypes.NAMES.get(road_type, "Дорога") + (" · мост" if grid.is_water(cell) else "")
		_icon.texture = UiTheme.icon(_road_icon(road_type))
		var ratio: float = GameState.traffic.load_ratio(grid, grid.index_of(cell))
		_subtitle.text = "Трасса за город" if grid.highway_cells.has(cell) else "Загрузка %d%%" % roundi(ratio * 100.0)
		_add("Пропускает", "%d поездок" % RoadTypes.CAPACITY.get(road_type, 0.0))
		_add("Загрузка", "%d%%" % roundi(ratio * 100.0), ratio >= 1.0)
		_add("Содержание", "$%d/ч" % roundi(GameTime.per_hour(RoadTypes.UPKEEP.get(road_type, 0.0))))
		if not RoadTypes.gives_access(road_type):
			_add("Дома", "не подключаются")
	elif grid.is_water(cell):
		_title.text = "Вода"
		_subtitle.text = "Дорога через воду — мост ($%d/кл.)" % Economy.BRIDGE_COST
		_icon.texture = UiTheme.icon("stat_water")
	else:
		_title.text = "Пустой участок"
		var zone: CityGrid.Zone = grid.get_zone(cell)
		_subtitle.text = _zone_name(zone)
		if zone != CityGrid.Zone.NONE:
			_add_why_not(grid, cell, zone, land)
		_icon.texture = UiTheme.icon(_zone_icon(zone))
	if not grid.is_water(cell) or grid.is_road(cell):
		var value: int = land.building_value(land.land_value, grid, building) if building != null \
				else land.value_at(land.land_value, grid, cell)
		var pollution: int = land.building_value(land.pollution, grid, building) if building != null \
				else land.value_at(land.pollution, grid, cell)
		var noise: int = land.building_value(land.noise, grid, building) if building != null \
				else land.value_at(land.noise, grid, cell)
		_add("Цена земли", "%d / 100" % value, value < 25)
		_add("Загрязнение", str(pollution), pollution >= BAD_LEVEL)
		_add("Шум", str(noise), noise >= BAD_LEVEL)
		if data != null and data.population + data.jobs > 0 and not building.abandoned:
			_add("Налог с участка", "×%.2f" % Economy.land_factor(value))


## «Ветряк ×3, вертикальный ветряк, служебная дорога 6 кл.» — что стоит у станции.
static func _modules_text(grid: CityGrid, building: BuildingInstance) -> String:
	var order: Array[StringName] = []
	var count: Dictionary[StringName, int] = {}
	for item: Array in StationModules.placed(grid, building):
		var module: StationModules.Module = item[0]
		if not count.has(module.id):
			order.append(module.id)
		count[module.id] = count.get(module.id, 0) + 1
	var parts: PackedStringArray = []
	for id: StringName in order:
		var name: String = StationModules.module(id).name.to_lower()
		parts.append(name if count[id] == 1 else "%s ×%d" % [name, count[id]])
	var road: int = StationModules.road_count(building)
	if road > 0:
		parts.append("служебная дорога %d кл." % road)
	return ", ".join(parts)


## Что даёт модуль — для кнопки и подсказки.
static func _module_gain(module: StationModules.Module) -> String:
	if module.is_road:
		return "бесплатно, тянется мышью"
	if module.power > 0:
		return "+" + Utilities.power_text(module.power)
	return "+" + Utilities.water_text(module.water)


## Где модуль ставится — для подсказки кнопки.
static func _module_rule(module: StationModules.Module) -> String:
	if module.is_road:
		return "Тяните от участка станции или от конца дороги. Вдоль неё ставятся ветряки"
	if module.along_road:
		return "Ставится вдоль служебной дороги или у самой станции"
	return "Ставится вплотную к станции, её дороге или к другим насосам и башням"


## Кнопки «поставить рядом» у станции (building = null — не станция: кнопок нет).
func _show_modules(building: BuildingInstance) -> void:
	var key: String = str(building.id) if building != null else ""
	if key != _modules_key:
		_modules_key = key
		for child: Node in _modules_box.get_children():
			child.queue_free()
		_module_buttons.clear()
		if building != null:
			var caption := Label.new()
			caption.text = "Поставить рядом со станцией"
			caption.theme_type_variation = &"Caption"
			_modules_box.add_child(caption)
			for module: StationModules.Module in StationModules.options(building.type_id):
				var button := Button.new()
				button.text = "+ %s · %s" % [module.name, _module_gain(module)] if module.is_road \
						else "+ %s · $%d · %s" % [module.name, module.cost, _module_gain(module)]
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.focus_mode = Control.FOCUS_NONE
				button.pressed.connect(place_module.bind(building.id, module.id))
				_modules_box.add_child(button)
				_module_buttons[module.id] = button
			var remove := Label.new()
			remove.text = "Убрать модуль — бульдозером по нему"
			remove.theme_type_variation = &"Caption"
			_modules_box.add_child(remove)
	_modules_box.visible = building != null
	if building == null:
		return
	for id: StringName in _module_buttons:
		var module: StationModules.Module = StationModules.module(id)
		var reason: String = StationModules.why_not(building, id)
		if reason.is_empty() and not Economy.can_afford(module.cost):
			reason = "не хватает денег"
		_module_buttons[id].disabled = not reason.is_empty()
		var upkeep: String = ", содержание +$%d/ч" % roundi(GameTime.per_hour(module.upkeep)) if module.upkeep > 0 else ""
		var needs: String = ", берёт свет %s" % Utilities.power_text(module.power_use) if module.power_use > 0 else ""
		_module_buttons[id].tooltip_text = ("Нельзя: %s" % reason) if not reason.is_empty() \
				else "%s: %s%s%s.\n%s" % [module.name, _module_gain(module), upkeep, needs, _module_rule(module)]


## Включает постановку модуля станции на карте (BuildTool, режим MODULE). false — станции нет.
func place_module(building_id: int, module_id: StringName) -> bool:
	if not GameState.grid.buildings.has(building_id):
		return false
	Events.module_place_requested.emit(building_id, module_id)
	return true


## Брошенное здание (Decay): никого нет, что мешает въехать или через сколько въедут, как снести.
func _add_abandoned(grid: CityGrid, building: BuildingInstance, data: BuildingData) -> void:
	_add("Состояние", "заброшено — %s" % ("жителей нет" if data.population > 0 else "работников нет"), true)
	var blockers: PackedStringArray = Decay.recover_blockers(grid, building, data, GameState.network, GameState.land,
			GameState.traffic, GameState.tax_rate, GameState.demand_by_zone())
	if blockers.is_empty():
		_add("Въедут через", _minutes_text((Decay.RECOVER_TICKS - building.recover_ticks) * GameTime.TICK_MINUTES))
	else:
		_add("Не въезжают", ", ".join(blockers), true)
	_add("Снести", "бульдозер [B], бесплатно")


## «45 мин», «2 ч 5 мин».
static func _minutes_text(minutes: int) -> String:
	if minutes < GameTime.MINUTES_PER_HOUR:
		return "%d мин" % minutes
	var rest: int = minutes % GameTime.MINUTES_PER_HOUR
	return "%d ч" % (minutes / GameTime.MINUTES_PER_HOUR) + (" %d мин" % rest if rest > 0 else "")


## «1 семья», «3 семьи», «5 семей».
static func _families_text(count: int) -> String:
	var word := "семей"
	if count % 10 == 1 and count % 100 != 11:
		word = "семья"
	elif count % 10 in [2, 3, 4] and count % 100 not in [12, 13, 14]:
		word = "семьи"
	return "%d %s" % [count, word]


## Счастье дома с причинами и что мешает следующему уровню (фаза 10).
func _add_mood(grid: CityGrid, building: BuildingInstance, data: BuildingData) -> void:
	if data.population > 0:
		var factors: Array[Array] = Happiness.factors(grid, building, data, GameState.land, GameState.traffic,
				GameState.tax_rate)
		var mood: int = Happiness.score_of(factors)
		_add("Счастье", "%d / 100" % mood, mood < Levels.DECLINE_HAPPINESS)
		for factor: Array in factors:
			var delta: int = roundi(factor[1])
			if delta != 0:
				_add("   " + factor[0], "%+d" % delta, delta < 0)
	if not data.grows or data.zone == CityGrid.Zone.NONE:
		return
	if data.level >= 3:
		_add("Уровень", "3 — высший")
	else:
		var blockers: PackedStringArray = Levels.blockers(grid, building, data, GameState.land, GameState.happiness)
		_add("До ур. %d" % (data.level + 1), "готов" if blockers.is_empty() else ", ".join(blockers),
				not blockers.is_empty())
	_add_consolidation(grid, building)


## Укрупнение (Р4): что мешает или во что дом скоро перестроят вместе с соседями.
func _add_consolidation(grid: CityGrid, building: BuildingInstance) -> void:
	_add("Укрупнение", Consolidation.status(grid, building, GameState.land, GameState.demand_by_zone(),
			GameState.network, GameState.utilities))


## Почему на пустой клетке зоны не строят (Growth.why_not); если ничего не мешает — когда построят.
## У жилья — «место для жилья»: счастье будущих жильцов, от MIN_HOME_MOOD застройщик строит.
func _add_why_not(grid: CityGrid, cell: Vector2i, zone: CityGrid.Zone, land: LandValue) -> void:
	var reasons: PackedStringArray = Growth.why_not(grid, cell, GameState.network, land, GameState.traffic,
			GameState.demand_by_zone())
	for i: int in reasons.size():
		_add("Не строят" if i == 0 else "", reasons[i], true)
	if CityGrid.is_residential(zone) and grid.in_strip(cell):
		var front: Vector2i = cell + CityGrid.NEIGHBORS[grid.get_strip_dir(cell)] * (grid.get_strip_depth(cell) - 1)
		var cells: Array[Vector2i] = [front]
		var mood: int = Happiness.score_of(Growth.home_factors(grid, cells, land, Growth.place_context(grid,
				GameState.traffic)))
		_add("Место для жилья", "%d (строят от %d)" % [mood, Growth.MIN_HOME_MOOD], mood < Growth.MIN_HOME_MOOD)
	if reasons.is_empty():
		_add("Строят", "у улицы, участком вглубь — когда дойдёт очередь" if grid.get_strip_depth(cell) > 1
				else "когда дойдёт очередь")


func _add(label_text: String, value_text: String, bad: bool = false) -> void:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"Caption"
	_rows.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size = Vector2(120, 0)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bad:
		value.add_theme_color_override(&"font_color", UiTheme.BAD)
	_rows.add_child(value)


static func _building_icon(data: BuildingData) -> String:
	var id_str: String = String(data.id)
	if UiTheme.icon(id_str) != null:
		return id_str
	return _zone_icon(data.zone)


static func _zone_icon(zone: CityGrid.Zone) -> String:
	match zone:
		CityGrid.Zone.RESIDENTIAL:
			return "tool_zone_r"
		CityGrid.Zone.COMMERCIAL:
			return "tool_zone_c"
		CityGrid.Zone.INDUSTRIAL:
			return "tool_zone_i"
		CityGrid.Zone.RESIDENTIAL_HIGH:
			return "tool_zone_r_high"
		CityGrid.Zone.COMMERCIAL_HIGH:
			return "tool_zone_c_high"
		CityGrid.Zone.OFFICE:
			return "tool_zone_o"
	return "tool_overlay"


static func _road_icon(road_type: int) -> String:
	match road_type:
		RoadTypes.Type.AVENUE:
			return "tool_avenue"
		RoadTypes.Type.HIGHWAY:
			return "tool_highway"
	return "tool_road"


static func _kind(data: BuildingData) -> String:
	if data.park != BuildingData.Park.NONE:
		return "Парк"
	if data.power_supply > 0 or data.water_supply > 0:
		return "Свет и вода"
	if data.service != BuildingData.Service.NONE:
		return "Служба"
	return _zone_name(data.zone)


static func _zone_name(zone: CityGrid.Zone) -> String:
	match zone:
		CityGrid.Zone.RESIDENTIAL:
			return "Жилая зона"
		CityGrid.Zone.COMMERCIAL:
			return "Коммерция"
		CityGrid.Zone.INDUSTRIAL:
			return "Промзона"
		CityGrid.Zone.RESIDENTIAL_HIGH:
			return "Многоэтажки"
		CityGrid.Zone.COMMERCIAL_HIGH:
			return "Торговые дома"
		CityGrid.Zone.OFFICE:
			return "Офисы"
	return "Без зоны"
