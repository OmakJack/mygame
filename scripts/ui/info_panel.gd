class_name InfoPanel
extends PanelContainer
## Карточка «Инфо» (фаза 9): клик по клетке без инструмента — что на ней и как ей живётся.
## Справа по центру; обновляется с каждым пересчётом города, закрывается крестиком.

const WIDTH: float = 280.0
## Ниже этого значения показатель хороший (загрязнение, шум) — красим, только если выше.
const BAD_LEVEL: int = 40

var cell := Vector2i(-1, -1)

var _title := Label.new()
var _subtitle := Label.new()
var _rows := GridContainer.new()


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -12.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	_title.theme_type_variation = &"Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.theme_type_variation = &"Small"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Закрыть"
	close.pressed.connect(hide)
	head.add_child(close)
	_subtitle.theme_type_variation = &"Caption"
	column.add_child(_subtitle)
	_rows.columns = 2
	_rows.add_theme_constant_override(&"h_separation", 16)
	_rows.add_theme_constant_override(&"v_separation", 4)
	column.add_child(_rows)


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
	var building: BuildingInstance = grid.get_building_at(cell)
	var data: BuildingData = BuildingCatalog.get_type(building.type_id) if building != null else null
	if data != null:
		_title.text = data.display_name
		_subtitle.text = _kind(data)
		if data.population > 0:
			_add("Жители", str(data.population))
		if data.jobs > 0:
			_add("Рабочие места", str(data.jobs))
		if data.power_use > 0:
			_add("Свет", "есть" if building.powered else "нет", not building.powered)
		if data.water_use > 0:
			_add("Вода", "есть" if building.has_water else "нет", not building.has_water)
		if data.power_supply > 0:
			_add("Даёт свет", str(data.power_supply))
		if data.water_supply > 0:
			_add("Даёт воду", str(data.water_supply))
		if data.land_value > 0:
			_add("Цена земли вокруг", "+%d" % data.land_value)
		if building.construction_ticks > 0:
			_add("Стройка", "ещё %d дн." % building.construction_ticks)
		_add_mood(grid, building, data)
	elif grid.is_road(cell):
		_title.text = "Мост" if grid.is_water(cell) else "Дорога"
		var ratio: float = GameState.traffic.load_ratio(grid, grid.index_of(cell))
		_subtitle.text = "Загрузка %d%%" % roundi(ratio * 100.0)
	elif grid.is_water(cell):
		_title.text = "Вода"
		_subtitle.text = "Дорога через воду — мост ($%d/кл.)" % Economy.BRIDGE_COST
	else:
		_title.text = "Пустой участок"
		_subtitle.text = _zone_name(grid.get_zone(cell))
	if not grid.is_water(cell) or grid.is_road(cell):
		var value: int = land.value_at(land.land_value, grid, cell)
		var pollution: int = land.value_at(land.pollution, grid, cell)
		var noise: int = land.value_at(land.noise, grid, cell)
		_add("Цена земли", "%d / 100" % value, value < 25)
		_add("Загрязнение", str(pollution), pollution >= BAD_LEVEL)
		_add("Шум", str(noise), noise >= BAD_LEVEL)
		if data != null and data.population + data.jobs > 0:
			_add("Налог с участка", "×%.2f" % Economy.land_factor(value))


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
		return
	var blockers: PackedStringArray = Levels.blockers(grid, building, data, GameState.land, GameState.happiness)
	_add("До ур. %d" % (data.level + 1), "готов" if blockers.is_empty() else ", ".join(blockers), not blockers.is_empty())


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
