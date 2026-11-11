class_name Hints
extends RefCounted
## Советник: что мешает городу расти и где это на карте. Только читают GameState.
## collect() — записи по срочности с местами на карте (панель «Советник», Advisor), build() — их тексты.

## Сколько мест на карте запоминать за запись: «Показать» перебирает их по кругу.
const MAX_SPOTS: int = 30

## С этого населения советуем первый парк.
const PARK_HINT_FROM: int = 100

## Срочность записи: порядок в списке и цвет её полоски. STEP — первые шаги пустого города.
enum Level { STEP, ALERT, WARNING, TIP }

const SERVICE_NAMES: Dictionary[BuildingData.Service, String] = {
	BuildingData.Service.SCHOOL: "школа",
	BuildingData.Service.HEALTH: "поликлиника",
	BuildingData.Service.FIRE: "пожарная часть",
	BuildingData.Service.POLICE: "полиция",
}
const SERVICE_ICONS: Dictionary[BuildingData.Service, String] = {
	BuildingData.Service.SCHOOL: "school_01",
	BuildingData.Service.HEALTH: "health_01",
	BuildingData.Service.FIRE: "fire_01",
	BuildingData.Service.POLICE: "police_01",
}
## Ниже этого покрытия служба считается нехватающей.
const LOW_COVERAGE: float = 0.5
## С этой доли тяжёлых поездок подсказываем, что жителям далеко до работы.
const LONG_COMMUTE_HINT: float = 0.25
## С этого загрязнения жилой участок считается «у завода» (как запрет роста жилья).
const DIRTY_HOME: int = Growth.MAX_HOME_POLLUTION
## Р5: с такого спроса категории без свободной зоны у улиц — подсказка разметить ещё (иначе рост стоит молча).
const LAND_HINT_DEMAND: float = 0.3
const LAND_HINTS: Dictionary[CityGrid.Zone, String] = {
	CityGrid.Zone.RESIDENTIAL: "Жилью нужна земля: спрос %d%%, а свободной жилой зоны у улиц нет — разметьте ещё [1]",
	CityGrid.Zone.COMMERCIAL: "Магазинам нужна земля: спрос %d%%, а свободной коммерческой зоны у улиц нет — разметьте ещё [2]",
	CityGrid.Zone.INDUSTRIAL: "Заводам нужна земля: спрос %d%%, а свободной промзоны у улиц нет — разметьте ещё [3]",
}
const LAND_ICONS: Dictionary[CityGrid.Zone, String] = {
	CityGrid.Zone.RESIDENTIAL: "tool_zone_r",
	CityGrid.Zone.COMMERCIAL: "tool_zone_c",
	CityGrid.Zone.INDUSTRIAL: "tool_zone_i",
}


## Запись советника: что не так, насколько срочно и где это на карте.
class Entry:
	## Постоянный ключ («power», «service_1»): по нему видно, что запись новая, и помнится, какое место показано.
	var id: String
	var text: String
	## Hints.Level.
	var level: int
	## 3D-иконка UiTheme.
	var icon: String
	## Где на карте (клетки зданий, зон, дорог); пусто — места нет.
	var cells: Array[Vector2i] = []
	## Какой слой карты включить (ZoneVisualizer.Overlay), −1 — не менять.
	var overlay: int = -1
	## Какую вкладку инструментов открыть («roads», «zones», «utilities», «services», «parks»), «» — никакую.
	var tab: String = ""
	## Места — здания: показать и карточку «Инфо» (что с домом и почему).
	var inspect: bool = false

	func _init(entry_id: String, entry_text: String, entry_level: int, entry_icon: String) -> void:
		id = entry_id
		text = entry_text
		level = entry_level
		icon = entry_icon


## Тексты записей по срочности.
static func build() -> Array[String]:
	var texts: Array[String] = []
	for entry: Entry in collect():
		texts.append(entry.text)
	return texts


## Все записи советника по срочности: первые шаги, тревоги, предупреждения, советы.
static func collect() -> Array[Entry]:
	var entries: Array[Entry] = []
	var utilities: Utilities = GameState.utilities
	var grid: CityGrid = GameState.grid

	var zoned: int = 0
	for cells: Dictionary in grid.zoned_empty_cells.values():
		zoned += cells.size()
	# Пустой город: ведём по первым шагам. Станции — раньше зон, чтобы не потратить деньги на зоны.
	if GameState.population == 0:
		var step: Entry = _first_step(grid, utilities, zoned)
		if step != null:
			entries.append(step)
			return entries
	var cut_off: Array[Vector2i] = []
	for cells: Dictionary in grid.zoned_empty_cells.values():
		for cell: Vector2i in cells:
			if grid.in_strip(cell) and not GameState.network.reaches_highway(grid, cell):
				cut_off.append(cell)
	if not cut_off.is_empty():
		var entry := Entry.new("cut_off", "%d кл. зон не связаны с трассой — дома там не строятся" % cut_off.size(),
				Level.ALERT, "tool_road")
		entry.cells = _spots(cut_off)
		entry.tab = "roads"
		entries.append(entry)
	var demands: Dictionary[CityGrid.Zone, float] = GameState.demand_by_zone()
	for category: CityGrid.Zone in LAND_HINTS:
		if demands[category] >= LAND_HINT_DEMAND and not has_free_frontage(grid, GameState.network, category):
			var entry := Entry.new("land_%d" % category, LAND_HINTS[category] % roundi(demands[category] * 100.0),
					Level.WARNING, LAND_ICONS[category])
			entry.tab = "zones"
			entries.append(entry)
	if zoned > 0 and utilities.power_supply == 0 and utilities.water_supply == 0:
		entries.append(_tab_entry("stations", "Нет ветростанции и водозабора: без света и воды дома не повышаются и пустеют — поставьте их у дороги",
				Level.ALERT, "power_plant_01", "utilities"))
	elif zoned > 0 and utilities.power_supply == 0:
		entries.append(_tab_entry("stations", "Нет ветростанции: без света дома не повышаются и пустеют — поставьте её у дороги",
				Level.ALERT, "power_plant_01", "utilities"))
	elif zoned > 0 and utilities.water_supply == 0:
		entries.append(_tab_entry("stations", "Нет водозабора: без воды дома не повышаются и пустеют — поставьте его у дороги",
				Level.ALERT, "water_tower_01", "utilities"))

	# Здания без света и воды, без дороги, заброшенные — места для «Показать».
	var unpowered: Array[Vector2i] = []
	var dry: Array[Vector2i] = []
	var cut_road: Array[Vector2i] = []
	var abandoned: Array[Vector2i] = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		if data.power_use > 0 and not building.powered:
			unpowered.append(building.anchor_cell())
		if data.water_use > 0 and not building.has_water:
			dry.append(building.anchor_cell())
		if building.abandoned:
			abandoned.append(building.anchor_cell())
		elif building.no_road_ticks > 0:
			cut_road.append(building.anchor_cell())
	if utilities.unpowered_count > 0:
		var entry := Entry.new("power", "Нет света у %d зд.: достройте ветряки на ветростанции (её карточка «Инфо») или поставьте ещё одну" % utilities.unpowered_count,
				Level.ALERT, "stat_power")
		entry.cells = _spots(unpowered)
		entry.overlay = ZoneVisualizer.Overlay.POWER
		entries.append(entry)
	if utilities.no_water_count > 0:
		var entry := Entry.new("water", "Нет воды у %d зд.: достройте насосы на водозаборе (его карточка «Инфо»; насосам нужен свет)" % utilities.no_water_count,
				Level.ALERT, "stat_water")
		entry.cells = _spots(dry)
		entry.overlay = ZoneVisualizer.Overlay.WATER
		entries.append(entry)
	# Упадок (Decay): здания без дороги скоро опустеют, брошенные ждут бульдозера или починки.
	if not cut_road.is_empty():
		var entry := Entry.new("cut_road", "Без дороги %d зд.: верните дорогу, иначе через пару часов опустеют" % cut_road.size(),
				Level.ALERT, "tool_road")
		entry.cells = _spots(cut_road)
		entry.inspect = true
		entries.append(entry)
	if not abandoned.is_empty():
		var entry := Entry.new("abandoned", "Заброшено %d зд.: снесите бульдозером [B] или исправьте причину" % abandoned.size(),
				Level.WARNING, "tool_bulldoze")
		entry.cells = _spots(abandoned)
		entry.inspect = true
		entries.append(entry)

	for service: BuildingData.Service in Services.REQUIRED_FROM:
		if GameState.population < Services.REQUIRED_FROM[service]:
			continue
		var coverage: float = GameState.service_coverage.get(service, 0.0)
		if coverage < LOW_COVERAGE:
			var entry := Entry.new("service_%d" % service, "Нужна %s: покрытие %d%%" % [SERVICE_NAMES[service],
					roundi(coverage * 100.0)], Level.WARNING, SERVICE_ICONS[service])
			entry.cells = Services.uncovered_homes(grid, service, MAX_SPOTS)
			entry.overlay = ZoneVisualizer.Overlay.SERVICES
			entries.append(entry)

	var traffic: Traffic = GameState.traffic
	if traffic.jammed_cells > 0:
		var advice: String = "постройте объезд"
		if RoadTypes.is_unlocked(RoadTypes.Type.AVENUE, GameState.rank):
			advice = "проложите проспект [T] поверх улицы или объезд"
		var entry := Entry.new("jams", "Пробки на %d кл. дорог: %s" % [traffic.jammed_cells, advice], Level.WARNING,
				"stat_traffic")
		entry.cells = _jammed_roads(grid, traffic)
		entry.overlay = ZoneVisualizer.Overlay.TRAFFIC
		entries.append(entry)
	if traffic.total_workers > 0.0 and traffic.long_commute_share >= LONG_COMMUTE_HINT:
		var entry := Entry.new("commute", "Жителям далеко до работы: %d%% — магазины и заводы ближе к домам" % roundi(
				traffic.long_commute_share * 100.0), Level.TIP, "stat_jobs")
		entry.overlay = ZoneVisualizer.Overlay.TRAFFIC
		entries.append(entry)

	# Фаза 9: грязь у жилья и подсказка про парки.
	var land: LandValue = GameState.land
	var dirty_homes: Array[Vector2i] = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.population > 0 and not building.abandoned \
				and land.building_value(land.pollution, grid, building) >= DIRTY_HOME:
			dirty_homes.append(building.anchor_cell())
	var dirty_zone: Array[Vector2i] = []
	for cell: Vector2i in grid.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL]:
		if land.value_at(land.pollution, grid, cell) >= DIRTY_HOME:
			dirty_zone.append(cell)
	if not dirty_homes.is_empty():
		var entry := Entry.new("dirty", "Дома рядом с заводами: %d — жильё лучше подальше от промзоны" % dirty_homes.size(),
				Level.WARNING, "tool_zone_i")
		entry.cells = _spots(dirty_homes)
		entry.overlay = ZoneVisualizer.Overlay.POLLUTION
		entries.append(entry)
	elif not dirty_zone.is_empty():
		var entry := Entry.new("dirty", "Жильё не растёт у заводов: %d кл. жилой зоны в загрязнении" % dirty_zone.size(),
				Level.WARNING, "tool_zone_i")
		entry.cells = _spots(dirty_zone)
		entry.overlay = ZoneVisualizer.Overlay.POLLUTION
		entries.append(entry)
	# Застройщик (Р3) не ставит жильё, где «счастье места» ниже Growth.MIN_HOME_MOOD (шум, дешёвая земля).
	if demands[CityGrid.Zone.RESIDENTIAL] > 0.0:
		var poor_spots: Array[Vector2i] = _poor_home_spots(grid, land)
		if not poor_spots.is_empty():
			var entry := Entry.new("noisy", "Жильё не строят на шумных местах: %d кл. у улицы — тише улица, парк или служба рядом" % poor_spots.size(),
					Level.TIP, "tool_highway")
			entry.cells = _spots(poor_spots)
			entry.overlay = ZoneVisualizer.Overlay.NOISE
			entries.append(entry)
	var unhappy: Array[Vector2i] = []
	for building_id: int in GameState.happiness.by_building:
		if GameState.happiness.by_building[building_id] < Levels.DECLINE_HAPPINESS and grid.buildings.has(building_id):
			unhappy.append(grid.buildings[building_id].cell)
	if not unhappy.is_empty():
		var entry := Entry.new("unhappy", "Жителям плохо в %d домах — скоро уедут (карточка дома: почему)" % unhappy.size(),
				Level.WARNING, "stat_pop")
		entry.cells = _spots(unhappy)
		entry.inspect = true
		entries.append(entry)
	if GameState.population >= PARK_HINT_FROM and not _has_parks(grid):
		entries.append(_tab_entry("parks", "Парк поднимет цену земли и налоги вокруг (вкладка «Парки»)", Level.TIP,
				"park_plaza", "parks"))

	var balance: int = GameState.income - GameState.expenses
	if GameState.money < 0:
		entries.append(Entry.new("money", "Казна в минусе: поднимите налог или снесите лишнее", Level.ALERT, "stat_money"))
	elif balance < 0:
		entries.append(Entry.new("money", "Расходы больше доходов: %+d $/ч" % GameTime.per_hour(balance), Level.WARNING,
				"stat_money"))

	var ordered: Array[Entry] = []
	for level: int in [Level.STEP, Level.ALERT, Level.WARNING, Level.TIP]:
		for entry: Entry in entries:
			if entry.level == level:
				ordered.append(entry)
	return ordered


## Есть ли у категории зон (R, C или I) свободная клетка у самой улицы, связанной с трассой, — там застройщик может строить.
static func has_free_frontage(grid: CityGrid, network: RoadNetwork, category: CityGrid.Zone) -> bool:
	for zone_type: CityGrid.Zone in grid.zoned_empty_cells:
		if CityGrid.zone_category(zone_type) != category:
			continue
		for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
			if grid.get_strip_depth(cell) == 1 and network.reaches_highway(grid, cell):
				return true
	return false


static func _tab_entry(id: String, text: String, level: int, icon: String, tab: String) -> Entry:
	var entry := Entry.new(id, text, level, icon)
	entry.tab = tab
	return entry


## Не больше MAX_SPOTS мест, равномерно по списку (не только из одного угла карты).
static func _spots(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= MAX_SPOTS:
		return cells
	var result: Array[Vector2i] = []
	for i: int in MAX_SPOTS:
		result.append(cells[i * cells.size() / MAX_SPOTS])
	return result


## Самые загруженные клетки дорог в пробке — сначала худшие.
static func _jammed_roads(grid: CityGrid, traffic: Traffic) -> Array[Vector2i]:
	var jammed: Array = []
	for road: Vector2i in grid.road_cells:
		var ratio: float = traffic.load_ratio(grid, grid.index_of(road))
		if ratio >= 1.0:
			jammed.append([ratio, road])
	jammed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var result: Array[Vector2i] = []
	for pair: Array in jammed.slice(0, MAX_SPOTS):
		result.append(pair[1])
	return result


static func _has_parks(grid: CityGrid) -> bool:
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.park != BuildingData.Park.NONE:
			return true
	return false


static func _first_step(grid: CityGrid, utilities: Utilities, zoned: int) -> Entry:
	if grid.has_entry() and grid.road_cells.size() <= grid.highway_cells.size():
		var entry := _tab_entry("step_road", "Шаг 1: проведите дорогу [R] от трассы у края карты — по ней в город приедут жители",
				Level.STEP, "tool_road", "roads")
		for cell: Vector2i in grid.highway_cells:
			entry.cells.append(cell)
			break
		return entry
	if grid.road_cells.is_empty():
		return _tab_entry("step_road", "Шаг 1: проведите дорогу [R]", Level.STEP, "tool_road", "roads")
	if utilities.power_supply == 0 and utilities.water_supply == 0:
		return _tab_entry("step_stations", "Шаг 2: поставьте у дороги ветростанцию и водозабор (вкладка «Свет и вода»)",
				Level.STEP, "power_plant_01", "utilities")
	if utilities.power_supply == 0:
		return _tab_entry("step_stations", "Шаг 2: поставьте у дороги ветростанцию — свет нужен и водозабору",
				Level.STEP, "power_plant_01", "utilities")
	if utilities.water_supply == 0:
		return _tab_entry("step_stations", "Шаг 2: поставьте у дороги водозабор (вкладка «Свет и вода»)",
				Level.STEP, "water_tower_01", "utilities")
	if zoned == 0:
		return _tab_entry("step_zones", "Шаг 3: разметьте у дороги жилую [1] и промышленную [3] зоны",
				Level.STEP, "tool_zone_r", "zones")
	return null


## Свободные клетки жилья у самой улицы, которые застройщик обходит: чисто, но «место» ниже MIN_HOME_MOOD.
static func _poor_home_spots(grid: CityGrid, land: LandValue) -> Array[Vector2i]:
	var context: Dictionary = {}
	var result: Array[Vector2i] = []
	for zone_type: CityGrid.Zone in [CityGrid.Zone.RESIDENTIAL, CityGrid.Zone.RESIDENTIAL_HIGH]:
		for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
			if grid.get_strip_depth(cell) != 1 or land.value_at(land.pollution, grid, cell) >= DIRTY_HOME:
				continue
			if context.is_empty():
				context = Growth.place_context(grid, GameState.traffic)
			var cells: Array[Vector2i] = [cell]
			if Happiness.score_of(Growth.home_factors(grid, cells, land, context)) < Growth.MIN_HOME_MOOD:
				result.append(cell)
	return result
