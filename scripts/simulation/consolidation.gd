class_name Consolidation
extends RefCounted
## Укрупнение (переделка роста, Р4; как в SimCity 4): когда земля дорожает, застройщик сносит 1–3 соседних
## участка одной улицы и застраивает их заново домами поглубже — дом растёт вглубь двора (2×1 → 2×2), соседние
## участки сливаются в один дом (три домика 1×1 → дом 3×2), широкий дом без глубокого варианта уступает место
## двум глубоким (ряд коттеджей 5×1 → дома 3×2 и 2×2). Жителей и мест — не меньше MIN_GAIN от прежних, уровень —
## меньший из снесённых (дальше дома растут обычным повышением, Levels). Пока идёт стройка, там никого нет —
## центр со временем застраивается плотнее. Промзоне цена земли всё равно: она укрупняется от высокого спроса.

## Сколько соседних участков сливается в один дом.
const MAX_LOTS: int = 3
## Цена земли под домом, с которой он укрупняется: между уровнем 2 и 3 (Levels.LAND_FOR_LEVEL — 30 и 50).
const MIN_VALUE: int = 40
## Промзона укрупняется при таком спросе (0..1).
const INDUSTRY_DEMAND: float = 0.5
## Во сколько раз больше жителей и мест должно быть у новых домов, чем у снесённых.
const MIN_GAIN: float = 1.5
## Укрупняют только обжитые дома: столько тиков после стройки (2 игровых часа).
const MIN_AGE_TICKS: int = 120
## Шанс укрупнения на тике (не больше одного за тик): центр меняется постепенно.
const CHANCE: float = 0.2


## Одно укрупнение за тик (с шансом CHANCE). Возвращает изменённые клетки.
static func step(grid: CityGrid, rng: RandomNumberGenerator, network: RoadNetwork, utilities: Utilities,
		land: LandValue, demands: Dictionary[CityGrid.Zone, float]) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if rng.randf() >= CHANCE:
		return changed
	var plans: Array[Dictionary] = find_plans(grid, land, demands)
	if plans.is_empty():
		return changed
	return apply(grid, plans[rng.randi_range(0, plans.size() - 1)], rng, network, utilities)


## Все возможные укрупнения: {buildings — сносимые дома подряд по улице, rect — их общий участок,
## dir — сторона на улицу, depth — глубина участка, pieces — новые дома вдоль улицы по порядку: типы на выбор
## одной ширины}.
static func find_plans(grid: CityGrid, land: LandValue, demands: Dictionary[CityGrid.Zone, float]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lot: CityGrid.Lot in grid.lots.values():
		var first: BuildingInstance = grid.building_on_lot(lot)
		if first == null or not blockers(grid, first, land, demands).is_empty():
			continue
		var zone_type: CityGrid.Zone = BuildingCatalog.get_type(first.type_id).zone
		var lots: Array[CityGrid.Lot] = [lot]
		var buildings: Array[BuildingInstance] = [first]
		while true:
			var plan: Dictionary = _plan(lots, buildings)
			if not plan.is_empty():
				result.append(plan)
			if lots.size() >= MAX_LOTS:
				break
			var next: CityGrid.Lot = _next_lot(grid, lots.back())
			var building: BuildingInstance = grid.building_on_lot(next) if next != null else null
			if building == null or BuildingCatalog.get_type(building.type_id).zone != zone_type \
					or not blockers(grid, building, land, demands).is_empty():
				break
			lots.append(next)
			buildings.append(building)
	return result


## Что мешает дому укрупниться (пусто — может, если найдутся соседи и тип побольше). Для «Инфо» и планов.
static func blockers(grid: CityGrid, building: BuildingInstance, land: LandValue,
		demands: Dictionary[CityGrid.Zone, float]) -> PackedStringArray:
	var data: BuildingData = BuildingCatalog.get_type(building.type_id)
	var lot: CityGrid.Lot = grid.lot_of(building)
	if data == null or not data.grows or data.zone == CityGrid.Zone.NONE:
		return PackedStringArray(["не растёт"])
	if building.is_free():
		return PackedStringArray(["вдоль кривой дороги дома пока не объединяются"])
	if lot == null:
		return PackedStringArray(["у дома нет участка"])
	if building.abandoned:
		return PackedStringArray(["заброшен"])
	if building.construction_ticks > 0:
		return PackedStringArray(["строится"])
	for cell: Vector2i in lot.cells():
		if grid.get_zone(cell) != data.zone:
			return PackedStringArray(["зону участка перекрасили"])
	var result: PackedStringArray = []
	var demand: float = demands.get(CityGrid.zone_category(data.zone), 0.0)
	if demand <= 0.0:
		result.append("нет спроса")
	elif data.zone == CityGrid.Zone.INDUSTRIAL:
		if demand < INDUSTRY_DEMAND:
			result.append("спрос промзоны %d%% из %d%%" % [roundi(demand * 100.0), roundi(INDUSTRY_DEMAND * 100.0)])
	else:
		var value: int = land.building_value(land.land_value, grid, building)
		if value < MIN_VALUE:
			result.append("цена земли %d из %d" % [value, MIN_VALUE])
	if not building.powered:
		result.append("нет света")
	if not building.has_water:
		result.append("нет воды")
	if building.age_ticks < MIN_AGE_TICKS:
		var minutes: int = (MIN_AGE_TICKS - building.age_ticks) * GameTime.TICK_MINUTES
		result.append("дом новый — ещё %d ч %02d мин" % [minutes / GameTime.MINUTES_PER_HOUR,
				minutes % GameTime.MINUTES_PER_HOUR])
	return result


## Строка «Укрупнение» карточки «Инфо»: что мешает, во что дом скоро перестроят или почему некуда.
static func status(grid: CityGrid, building: BuildingInstance, land: LandValue,
		demands: Dictionary[CityGrid.Zone, float], network: RoadNetwork, utilities: Utilities) -> String:
	var reasons: PackedStringArray = blockers(grid, building, land, demands)
	if not reasons.is_empty():
		return ", ".join(reasons)
	for plan: Dictionary in find_plans(grid, land, demands):
		if plan.buildings.has(building):
			var sizes: PackedStringArray = []
			var types: Array[BuildingData] = []
			for options: Array in plan.pieces:
				sizes.append("%d×%d" % [options[0].size.x, options[0].size.y])
				types.append(options[0])
			var lacking: String = _shortage(grid, plan.buildings, types, network, utilities)
			if not lacking.is_empty():
				return "не хватает %s на дом %s" % [lacking, " и ".join(sizes)]
			if plan.buildings.size() > 1:
				return "скоро: с соседями (%d уч.) в дом %s" % [plan.buildings.size(), " и ".join(sizes)]
			if sizes.size() > 1:
				return "скоро: вместо него дома %s — глубже" % " и ".join(sizes)
			return "скоро: дом вглубь двора, %s" % sizes[0]
	return "ждёт соседей: на свой участок дома больше нет"


## Сносит дома плана и ставит новые на их общий участок по порядку вдоль улицы (стройплощадки), у каждого —
## свой участок на всю глубину. Изменённые клетки; пусто, если в компоненте дорог не хватает запаса света
## и воды на прибавку (как у повышения, Levels).
static func apply(grid: CityGrid, plan: Dictionary, rng: RandomNumberGenerator, network: RoadNetwork,
		utilities: Utilities) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var types: Array[BuildingData] = []
	for options: Array in plan.pieces:
		types.append(BuildingCatalog.pick_weighted(options, rng))
	var buildings: Array[BuildingInstance] = plan.buildings
	if not _shortage(grid, buildings, types, network, utilities).is_empty():
		return changed
	var component: int = network.component_for_building(grid, buildings[0])
	var more: Vector2i = _extra(buildings, types)
	var rect: Rect2i = plan.rect
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			changed.append(Vector2i(x, y))
	for building: BuildingInstance in buildings:
		grid.remove_building(building.id)
	var front: Array[Vector2i] = BuildingInstance.edge_cells(rect.position, rect.size, plan.dir)
	var start: int = 0
	for data: BuildingData in types:
		var id: int = Growth.build_lot(grid, data, front.slice(start, start + data.size.x), plan.dir, plan.depth)
		start += data.size.x
		if id == -1:
			continue
		var built: BuildingInstance = grid.buildings[id]
		built.powered = true
		built.has_water = true
		Levels.start_construction(built, data)
	utilities.spare_power[component] = utilities.spare_power.get(component, 0) - maxi(0, more.x)
	utilities.spare_water[component] = utilities.spare_water.get(component, 0) - maxi(0, more.y)
	return changed


## Прибавка света (x) и воды (y) от замены домов buildings на types.
static func _extra(buildings: Array[BuildingInstance], types: Array[BuildingData]) -> Vector2i:
	var more := Vector2i.ZERO
	for data: BuildingData in types:
		more += Vector2i(data.power_use, data.water_use)
	for building: BuildingInstance in buildings:
		var old: BuildingData = BuildingCatalog.get_type(building.type_id)
		more -= Vector2i(old.power_use, old.water_use)
	return more


## Чего не хватает в компоненте дорог на прибавку («дороги», «света», «воды»); пусто — хватает.
static func _shortage(grid: CityGrid, buildings: Array[BuildingInstance], types: Array[BuildingData],
		network: RoadNetwork, utilities: Utilities) -> String:
	var component: int = network.component_for_building(grid, buildings[0])
	if component == -1:
		return "дороги"
	var more: Vector2i = _extra(buildings, types)
	if utilities.spare_power.get(component, 0) < more.x:
		return "света"
	if utilities.spare_water.get(component, 0) < more.y:
		return "воды"
	return ""


## План для домов подряд по улице: их общий участок и новые дома вдоль улицы — уровня меньшего из снесённых,
## глубиной не больше участка, вместе с прибавкой не меньше MIN_GAIN. Ширины новых домов — раскладка всей ширины
## участков с наибольшим числом жителей и мест (жители пропорциональны площади — значит, глубже), из равных —
## меньше домов. Несколько участков — только если домов станет меньше (иначе каждый растёт вглубь сам).
## Пусто — такой застройки нет.
static func _plan(lots: Array[CityGrid.Lot], buildings: Array[BuildingInstance]) -> Dictionary:
	var width: int = 0
	var old: int = 0
	var level: int = 3
	var rect: Rect2i = lots[0].rect
	for i: int in lots.size():
		width += lots[i].building_size().x
		rect = rect.merge(lots[i].rect)
		var data: BuildingData = BuildingCatalog.get_type(buildings[i].type_id)
		old += data.population + data.jobs
		level = mini(level, data.level)
	var depth: int = lots[0].building_size().y
	var zone_type: CityGrid.Zone = BuildingCatalog.get_type(buildings[0].type_id).zone
	# Лучшие типы каждой ширины: больше всего жителей и мест при глубине не больше участка.
	var best: Dictionary[int, Array] = {}
	for data: BuildingData in BuildingCatalog.level_types(zone_type, level):
		if data.size.x > width or data.size.y > depth:
			continue
		var people: int = data.population + data.jobs
		var known: Array = best.get(data.size.x, [])
		if known.is_empty() or people > known[0].population + known[0].jobs:
			best[data.size.x] = [data]
		elif people == known[0].population + known[0].jobs:
			known.append(data)
	# Раскладка ширины: layout[w] = [жители и места, ширины домов]; пусто — ширину w не разложить.
	var layout: Array[Array] = [[0, []]]
	for w: int in range(1, width + 1):
		var found: Array = []
		for piece: int in best:
			if piece > w or layout[w - piece].is_empty():
				continue
			var people: int = layout[w - piece][0] + best[piece][0].population + best[piece][0].jobs
			var pieces: Array = layout[w - piece][1] + [piece]
			if found.is_empty() or people > found[0] or (people == found[0] and pieces.size() < found[1].size()):
				found = [people, pieces]
		layout.append(found)
	var result: Array = layout[width]
	if result.is_empty() or result[0] < old * MIN_GAIN or (lots.size() > 1 and result[1].size() >= lots.size()):
		return {}
	var widths: Array = result[1].duplicate()
	widths.sort_custom(func(a: int, b: int) -> bool: return a > b)
	var pieces: Array[Array] = []
	for piece: int in widths:
		pieces.append(best[piece])
	return {"buildings": buildings.duplicate(), "rect": rect, "dir": lots[0].dir, "depth": depth, "pieces": pieces}


## Соседний участок той же улицы дальше по ходу (вдоль улицы — сторона dir + 1) и той же полосы
## (совпадает поперёк улицы: та же глубина), или null.
static func _next_lot(grid: CityGrid, lot: CityGrid.Lot) -> CityGrid.Lot:
	var along: Vector2i = CityGrid.NEIGHBORS[(lot.dir + 1) % 4]
	var front: Array[Vector2i] = BuildingInstance.edge_cells(lot.rect.position, lot.rect.size, lot.dir)
	var probe: Vector2i = (front.back() if along.x + along.y > 0 else front[0]) + along
	var next: CityGrid.Lot = grid.get_lot(probe)
	if next == null or next == lot or next.dir != lot.dir or not next.poly.is_empty():
		return null
	if lot.dir % 2 == 0:
		return next if next.rect.position.y == lot.rect.position.y and next.rect.size.y == lot.rect.size.y else null
	return next if next.rect.position.x == lot.rect.position.x and next.rect.size.x == lot.rect.size.x else null
