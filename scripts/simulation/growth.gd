class_name Growth
extends RefCounted
## Застройщик по месту (переделка роста, Р2; как в Cities: Skylines и SimCity 4): размер дома решает
## город, а не жест разметки. Застройщик берёт свободную клетку зоны у самой улицы (полоса CityGrid,
## глубина 1), смотрит, сколько свободного фасада вдоль улицы и насколько глубока полоса за ним, и выбирает
## ширину дома по зоне, спросу и цене земли. Участок — от улицы на всю свободную глубину полосы (до 4),
## дом — у улицы фасадом к ней, позади — двор (CityGrid.Lot). Каждый дом смотрит на свою улицу.
## Свет и вода росту не нужны (как в SimCity): дом растёт и без них, а над ним висит значок
## (BadgeVisualizer), пока игрок не проведёт свет и воду. Запас компонента, если хватает, сразу уменьшается.
## Р3 — желанность места по зоне (как в SimCity 4): жильё встаёт там, где жителям будет хорошо
## («счастье места» — как Happiness, но без налога, дороги до работы, света и воды), и не встаёт там, где
## сразу пустело бы; магазины — где рядом покупатели и поток машин; промзона — на дешёвой земле подальше
## от жилья; офисы — на дорогой земле у служб. Почему клетка пустует — why_not (карточка «Инфо»).
## C3 — вдоль свободной дороги (диагональ, дуга) участок — колонки ячеек FreeStrips (plan_free_at),
## дом встаёт под углом дороги (build_free_lot).

## С такого загрязнения жильё на клетке не растёт.
const MAX_HOME_POLLUTION: int = 40
## Сколько случайных фасадных клеток застройщик рассматривает за раз; побеждает лучший план.
const VALUE_SAMPLES: int = 6
## Сколько свободного фасада вдоль улицы смотрит застройщик в каждую сторону от клетки.
const MAX_RUN: int = 7
## Желаемая ширина дома по зоне — при спросе 0 и цене земли VALUE_MID.
const BASE_WIDTH: Dictionary[CityGrid.Zone, float] = {
	CityGrid.Zone.RESIDENTIAL: 1.4,
	CityGrid.Zone.RESIDENTIAL_HIGH: 1.8,
	CityGrid.Zone.COMMERCIAL: 1.6,
	CityGrid.Zone.COMMERCIAL_HIGH: 2.4,
	CityGrid.Zone.INDUSTRIAL: 2.4,
	CityGrid.Zone.OFFICE: 2.0,
}
## Прибавка к желаемой ширине: за спрос 1.0 и за каждое очко цены земли выше VALUE_MID (промзоне цена всё равно).
const WIDTH_PER_DEMAND: float = 1.6
const WIDTH_PER_VALUE: float = 0.04
const VALUE_MID: int = 30
## Разброс желаемой ширины: ± столько клеток случайно — улица не из одинаковых домов.
const WIDTH_JITTER: float = 0.9
## Штрафы плана (в клетках ширины): за «сироту» — клетку колонки глубже участка (её потом не достать)
## и за ряд, разорванный посередине (свободный фасад остаётся с двух сторон).
const ORPHAN_PENALTY: float = 0.5
const SPLIT_PENALTY: float = 0.4
## Участок вдоль свободной дороги на колонку шире дома (боковой двор) — штраф плану.
const EXTRA_COLUMN_PENALTY: float = 0.6
## Клетка под домом вдоль свободной дороги — центр в доме или не дальше столько от его края, м.
const HOUSE_CELL_MARGIN: float = 0.3
## Насколько цена земли важнее точности плана при выборе из VALUE_SAMPLES (очков цены за клетку штрафа).
const VALUE_PER_PENALTY: float = 4.0
## Доля домов глубиной 2, когда участок позволяет (иначе — глубиной 1, двор длиннее).
const DEEP_SHARE: float = 0.6
## Жильё не встаёт, если «счастье места» ниже этого: между порогом упадка (Levels.DECLINE_HAPPINESS = 20)
## и заселения брошенных (Decay.RECOVER_HAPPINESS = 35) — новый дом не пустеет сразу.
const MIN_HOME_MOOD: int = 30
## Магазины: покупатели — жители в радиусе CUSTOMER_RADIUS (по Манхэттену), не больше CUSTOMERS_CAP,
## очки — CUSTOMER_WEIGHT · √жителей (первые покупатели важнее: 9 жителей — +7.5, 100 — +25);
## поток — загрузка улицы у фасада (0..1.5).
const CUSTOMER_RADIUS: int = 6
const CUSTOMERS_CAP: int = 150
const CUSTOMER_WEIGHT: float = 2.5
const PASSING_WEIGHT: float = 12.0
## Промзона: чем дешевле земля, тем лучше; жители в радиусе INDUSTRY_HOME_RADIUS — минус
## INDUSTRY_HOME_WEIGHT · √жителей (не к домам).
const INDUSTRY_HOME_RADIUS: int = 4
const INDUSTRY_HOME_WEIGHT: float = 2.5


## Ставит один дом на зону zone_type. Возвращает левую верхнюю клетку дома или NO_CELL, если места нет.
## demand — спрос категории зоны (0..1): чем выше, тем шире дома. Без land — без желанности (проверки).
## context — place_context, общий для попыток одного тика (пусто — посчитать здесь и дописать в него);
## новый дом с жителями дописывается в его «homes», чтобы следующая попытка видела покупателей.
static func grow_one(grid: CityGrid, zone_type: CityGrid.Zone, rng: RandomNumberGenerator,
		network: RoadNetwork, utilities: Utilities, land: LandValue = null, demand: float = 0.5,
		traffic: Traffic = null, context: Dictionary = {}) -> Vector2i:
	var types: Array[BuildingData] = BuildingCatalog.growable_types(zone_type)
	if types.is_empty():
		return CityGrid.NO_CELL
	var by_width: Dictionary[int, Array] = {}
	for data: BuildingData in types:
		if not by_width.has(data.size.x):
			by_width[data.size.x] = []
		by_width[data.size.x].append(data)

	# Фасадные клетки: свободная земля зоны у самой улицы, улица связана с трассой.
	var entry_comp: int = network.component_of.get(grid.entry, -2) if grid.has_entry() else -1
	var frontage: Array[Vector2i] = []
	for cell: Vector2i in grid.zoned_empty_cells[zone_type]:
		if grid.get_strip_depth(cell) != 1:
			continue
		var component: int = network.component_of.get(grid.strip_road(cell), -1)
		if component == -1 or (grid.has_entry() and component != entry_comp):
			continue
		frontage.append(cell)
	if frontage.is_empty():
		return CityGrid.NO_CELL

	var use_value: bool = land != null and zone_type != CityGrid.Zone.INDUSTRIAL
	if land != null and context.is_empty():
		context.merge(place_context(grid, traffic))
	var best: Dictionary = {}
	var best_score: float = -INF
	for sample: int in mini(VALUE_SAMPLES, frontage.size()):
		var cell: Vector2i = frontage[rng.randi_range(0, frontage.size() - 1)]
		var value: int = land.value_at(land.land_value, grid, cell) if land != null else VALUE_MID
		var target: float = BASE_WIDTH.get(zone_type, 2.0) + clampf(demand, 0.0, 1.0) * WIDTH_PER_DEMAND \
				+ rng.randf_range(-WIDTH_JITTER, WIDTH_JITTER)
		if use_value:
			target += (value - VALUE_MID) * WIDTH_PER_VALUE
		var plan: Dictionary = plan_free_at(grid, land, zone_type, cell, by_width, target) \
				if grid.free_slot(cell) != null else plan_at(grid, land, zone_type, cell, by_width, target)
		if plan.is_empty():
			continue
		var score: float = -plan.penalty * VALUE_PER_PENALTY
		if land != null:
			var place: Array = place_score(grid, zone_type, plan.front, plan.dir, land, context)
			if not place[1].is_empty():
				continue
			score += place[0]
		if score > best_score:
			best_score = score
			best = plan
	if best.is_empty():
		return CityGrid.NO_CELL

	var data: BuildingData = _pick_type(best.options, best.depth, rng)
	var dir: int = best.dir
	var front: Array[Vector2i] = best.front
	var id: int = build_free_lot(grid, data, best) if best.has("segment") else build_lot(grid, data, front, dir, best.depth)
	if id == -1:
		return CityGrid.NO_CELL
	# Свет и вода — из запаса компонента, если хватает; нет — дом стоит без них (со значком),
	# пока следующий пересчёт (Utilities.distribute) не найдёт ему запас.
	var building: BuildingInstance = grid.buildings[id]
	var component: int = network.component_for_building(grid, building)
	building.powered = utilities.spare_power.get(component, 0) >= data.power_use
	building.has_water = utilities.spare_water.get(component, 0) >= data.water_use
	if building.powered:
		utilities.spare_power[component] = utilities.spare_power.get(component, 0) - data.power_use
	if building.has_water:
		utilities.spare_water[component] = utilities.spare_water.get(component, 0) - data.water_use
	if data.population > 0 and context.has("homes"):
		context["homes"].append([building.cell, data.population])
	return building.cells()[0]


## Ставит дом data у клеток фасада front (улица — в сторону dir) и участок от улицы на depth клеток вглубь:
## дом у улицы, позади — двор. Номер дома или −1. Общее для роста и укрупнения (Consolidation).
static func build_lot(grid: CityGrid, data: BuildingData, front: Array[Vector2i], dir: int, depth: int) -> int:
	var id: int = grid.place_building(data.id, _rect_inward(front, dir, data.size.y).position, dir)
	if id != -1:
		grid.add_lot(_rect_inward(front, dir, depth), dir)
	return id


## Общее для оценки мест за один рост: работающие службы [клетка, радиус], дома [клетка, жители], трафик.
static func place_context(grid: CityGrid, traffic: Traffic) -> Dictionary:
	var homes: Array[Array] = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.population > 0 and not building.abandoned:
			homes.append([building.cell, data.population])
	return {"services": Happiness._active_services(grid), "homes": homes, "traffic": traffic}


## Желанность места для зоны: [очки, причина отказа или ""] по клеткам фасада cells (улица — в сторону dir).
static func place_score(grid: CityGrid, zone_type: CityGrid.Zone, cells: Array[Vector2i], _dir: int,
		land: LandValue, context: Dictionary) -> Array:
	var value: float = _average(grid, land.land_value, cells)
	var pollution: float = _average(grid, land.pollution, cells)
	match zone_type:
		CityGrid.Zone.RESIDENTIAL, CityGrid.Zone.RESIDENTIAL_HIGH:
			if pollution >= MAX_HOME_POLLUTION:
				return [0.0, "загрязнение %d — жильё не строят от %d" % [roundi(pollution), MAX_HOME_POLLUTION]]
			var factors: Array[Array] = home_factors(grid, cells, land, context)
			var mood: int = Happiness.score_of(factors)
			if mood < MIN_HOME_MOOD:
				return [float(mood), "место на %d из %d: %s" % [mood, MIN_HOME_MOOD, _worst(factors)]]
			return [float(mood), ""]
		CityGrid.Zone.COMMERCIAL, CityGrid.Zone.COMMERCIAL_HIGH:
			var passing: float = 0.0
			var traffic: Traffic = context.get("traffic")
			if traffic != null:
				for cell: Vector2i in cells:
					var road: Vector2i = grid.strip_road(cell)
					if grid.is_in_bounds(road):
						passing += clampf(traffic.load_ratio(grid, grid.index_of(road)), 0.0, 1.5)
				passing /= cells.size()
			var customers: int = mini(_residents_near(cells, context, CUSTOMER_RADIUS), CUSTOMERS_CAP)
			return [value * 0.5 + sqrt(customers) * CUSTOMER_WEIGHT + passing * PASSING_WEIGHT - pollution * 0.3, ""]
		CityGrid.Zone.INDUSTRIAL:
			return [(LandValue.BASE_VALUE * 2.0 - value) * 0.3
					- sqrt(_residents_near(cells, context, INDUSTRY_HOME_RADIUS)) * INDUSTRY_HOME_WEIGHT, ""]
	# Офисы: дорогая земля, службы рядом, без дыма.
	var covered: int = 0
	for cell: Vector2i in cells:
		covered += _services_covering(cell, context)
	return [value + covered * 4.0 / cells.size() - pollution * 0.5, ""]


## Слагаемые «счастья места» для жилья (как Happiness.factors без налога, дороги до работы, света и воды).
static func home_factors(grid: CityGrid, cells: Array[Vector2i], land: LandValue, context: Dictionary) -> Array[Array]:
	var covered: float = 0.0
	for cell: Vector2i in cells:
		covered += _services_covering(cell, context)
	covered /= cells.size()
	return [
		["Службы рядом", covered * Happiness.PER_SERVICE],
		["Цена земли", (_average(grid, land.land_value, cells) - LandValue.BASE_VALUE) * Happiness.LAND_WEIGHT],
		["Загрязнение", -_average(grid, land.pollution, cells) * Happiness.POLLUTION_WEIGHT],
		["Шум", -_average(grid, land.noise, cells) * Happiness.NOISE_WEIGHT],
	]


## Почему на пустой клетке зоны не строят (пусто — построят, когда дойдёт очередь). Для карточки «Инфо».
static func why_not(grid: CityGrid, cell: Vector2i, network: RoadNetwork, land: LandValue, traffic: Traffic,
		demands: Dictionary[CityGrid.Zone, float]) -> PackedStringArray:
	var result: PackedStringArray = []
	var zone_type: CityGrid.Zone = grid.get_zone(cell)
	if zone_type == CityGrid.Zone.NONE or not grid.zoned_empty_cells[zone_type].has(cell):
		return result
	if not grid.in_strip(cell):
		return PackedStringArray(["далеко от дороги: дом строят в 4 клетках от неё по прямой"])
	var dir: int = grid.get_strip_dir(cell)
	var front: Vector2i = cell
	var slot: FreeStrips.Slot = grid.free_slot(cell)
	if slot != null:
		# Вдоль свободной дороги: ячейки колонки между клеткой и дорогой должны быть свободны.
		for row: int in range(1, slot.row):
			if not _free_slot_ok(grid, zone_type, grid.free_strips.slot_in(slot.segment, slot.side, slot.col, row)):
				return PackedStringArray(["нет выхода на улицу: между клеткой и дорогой занято"])
	else:
		# Участок растёт от улицы: клетка в глубине ждёт, пока застроят её фасад.
		front = cell + CityGrid.NEIGHBORS[dir] * (grid.get_strip_depth(cell) - 1)
		for k: int in range(1, grid.get_strip_depth(cell)):
			var c: Vector2i = cell + CityGrid.NEIGHBORS[dir] * k
			if not grid.zoned_empty_cells[zone_type].has(c) or grid.get_strip_dir(c) != dir:
				return PackedStringArray(["нет выхода на улицу: между клеткой и дорогой занято"])
	var road: Vector2i = grid.strip_road(cell)
	if grid.has_entry() and network.component_of.get(road, -1) != network.component_of.get(grid.entry, -2):
		result.append("улица не связана с трассой")
	if demands.get(CityGrid.zone_category(zone_type), 0.0) <= 0.0:
		result.append("нет спроса")
	if land != null:
		var cells: Array[Vector2i] = [front]
		var place: Array = place_score(grid, zone_type, cells, dir, land, place_context(grid, traffic))
		if not place[1].is_empty():
			result.append(place[1])
	return result


static func _average(grid: CityGrid, layer: PackedByteArray, cells: Array[Vector2i]) -> float:
	if layer.size() != grid.size * grid.size or cells.is_empty():
		return 0.0
	var sum: float = 0.0
	for cell: Vector2i in cells:
		sum += layer[grid.index_of(cell)] if grid.is_in_bounds(cell) else 0
	return sum / cells.size()


## Сколько работающих служб покрывают клетку.
static func _services_covering(cell: Vector2i, context: Dictionary) -> int:
	var covered: int = 0
	for source: Array in context.get("services", []):
		var at: Vector2i = source[0]
		if absi(at.x - cell.x) + absi(at.y - cell.y) <= source[1]:
			covered += 1
	return covered


## Сколько жителей в домах не дальше radius (по Манхэттену) от середины клеток.
static func _residents_near(cells: Array[Vector2i], context: Dictionary, radius: int) -> int:
	var mid: Vector2i = cells[cells.size() / 2]
	var people: int = 0
	for home: Array in context.get("homes", []):
		var at: Vector2i = home[0]
		if absi(at.x - mid.x) + absi(at.y - mid.y) <= radius:
			people += home[1]
	return people


## Самое большое минусовое слагаемое: «шум −17».
static func _worst(factors: Array[Array]) -> String:
	var worst: Array = factors[0]
	for factor: Array in factors:
		if factor[1] < worst[1]:
			worst = factor
	return "%s %d" % [String(worst[0]).to_lower(), roundi(worst[1])]


## План застройщика для фасадной клетки cell: {front — клетки фасада участка вдоль улицы, dir — сторона
## на улицу, depth — глубина участка, options — подходящие типы (ширина окна, глубина ≤ depth),
## penalty — штраф плана в клетках}. Пусто — здесь ничего не встаёт.
## Окно ряда, содержащее cell, оценивается: отличие ширины от желаемой target, «сироты» за мелкими
## колонками, разрыв ряда посередине. Жильё не встаёт там, где у улицы грязно.
static func plan_at(grid: CityGrid, land: LandValue, zone_type: CityGrid.Zone, cell: Vector2i,
		by_width: Dictionary[int, Array], target: float) -> Dictionary:
	var dir: int = grid.get_strip_dir(cell)
	if dir < 0:
		return {}
	var along: Vector2i = CityGrid.NEIGHBORS[(dir + 1) % 4]
	var run: Array[Vector2i] = [cell]
	for k: int in range(1, MAX_RUN):
		var c: Vector2i = cell - along * k
		if not _is_frontage(grid, c, zone_type, dir):
			break
		run.push_front(c)
	var seed_index: int = run.size() - 1
	for k: int in range(1, MAX_RUN):
		var c: Vector2i = cell + along * k
		if not _is_frontage(grid, c, zone_type, dir):
			break
		run.append(c)
	var depths: Array[int] = []
	var dirty: Array[bool] = []
	var residential: bool = CityGrid.is_residential(zone_type)
	for c: Vector2i in run:
		depths.append(_column_depth(grid, c, zone_type, dir))
		dirty.append(residential and land != null
				and land.value_at(land.pollution, grid, c) >= MAX_HOME_POLLUTION)

	var best: Dictionary = {}
	for width: int in by_width:
		for start: int in range(seed_index - width + 1, seed_index + 1):
			if start < 0 or start + width > run.size():
				continue
			var depth: int = CityGrid.STRIP_DEPTH
			var polluted: bool = false
			for i: int in range(start, start + width):
				depth = mini(depth, depths[i])
				polluted = polluted or dirty[i]
			if polluted:
				continue
			var options: Array = by_width[width].filter(
					func(data: BuildingData) -> bool: return data.size.y <= depth)
			if options.is_empty():
				continue
			var penalty: float = absf(width - target)
			for i: int in range(start, start + width):
				penalty += (depths[i] - depth) * ORPHAN_PENALTY
			if start > 0 and start + width < run.size():
				penalty += SPLIT_PENALTY
			if best.is_empty() or penalty < best.penalty:
				best = {
					"front": run.slice(start, start + width),
					"dir": dir,
					"depth": depth,
					"options": options,
					"penalty": penalty,
				}
	return best


## План вдоль свободной дороги для клетки cell у самой дороги (ячейка ряда 1): как plan_at, но ряд —
## колонки ячеек FreeStrips. {segment, side, col — первая колонка, width, depth, options, penalty,
## front — клетки ряда 1 участка, dir — ближайшая сторона на дорогу}. Пусто — здесь ничего не встаёт.
static func plan_free_at(grid: CityGrid, land: LandValue, zone_type: CityGrid.Zone, cell: Vector2i,
		by_width: Dictionary[int, Array], target: float) -> Dictionary:
	var strips: FreeStrips = grid.free_strips
	var slot: FreeStrips.Slot = grid.free_slot(cell)
	if slot == null or slot.row != 1 or not _free_slot_ok(grid, zone_type, slot):
		return {}
	var run: Array[int] = [slot.col]
	for k: int in range(1, MAX_RUN):
		if not _free_slot_ok(grid, zone_type, strips.slot_in(slot.segment, slot.side, slot.col - k, 1)):
			break
		run.push_front(slot.col - k)
	var seed_index: int = run.size() - 1
	for k: int in range(1, MAX_RUN):
		if not _free_slot_ok(grid, zone_type, strips.slot_in(slot.segment, slot.side, slot.col + k, 1)):
			break
		run.append(slot.col + k)
	var depths: Array[int] = []
	var fronts: Array[Array] = []
	var dirty: Array[bool] = []
	var residential: bool = CityGrid.is_residential(zone_type)
	for col: int in run:
		var depth: int = 1
		while depth < FreeStrips.DEPTH and _free_slot_ok(grid, zone_type,
				strips.slot_in(slot.segment, slot.side, col, depth + 1)):
			depth += 1
		depths.append(depth)
		var cells: Array[Vector2i] = strips.slot_in(slot.segment, slot.side, col, 1).cells
		fronts.append(cells)
		var polluted: bool = false
		if residential and land != null:
			for c: Vector2i in cells:
				polluted = polluted or land.value_at(land.pollution, grid, c) >= MAX_HOME_POLLUTION
		dirty.append(polluted)

	# Участок — width колонок под дом шириной width или на колонку шире (внутренняя сторона дуги: веер
	# сужается вглубь, прямоугольный дом в свои колонки не влезает — лишняя колонка уходит в боковой двор).
	var plans: Array[Dictionary] = []
	for width: int in by_width:
		for extra: int in [0, 1]:
			var columns: int = width + extra
			for start: int in range(seed_index - columns + 1, seed_index + 1):
				if start < 0 or start + columns > run.size():
					continue
				var depth: int = FreeStrips.DEPTH
				var polluted: bool = false
				var front: Array[Vector2i] = []
				for i: int in range(start, start + columns):
					depth = mini(depth, depths[i])
					polluted = polluted or dirty[i]
					front.append_array(fronts[i])
				# Без клеток у дороги дому не на чем стоять (ячейки на месте клеток дороги).
				if polluted or front.is_empty():
					continue
				var options: Array = by_width[width].filter(
						func(data: BuildingData) -> bool: return data.size.y <= depth)
				if options.is_empty():
					continue
				var penalty: float = absf(width - target) + extra * EXTRA_COLUMN_PENALTY
				for i: int in range(start, start + columns):
					penalty += (depths[i] - depth) * ORPHAN_PENALTY
				if start > 0 and start + columns < run.size():
					penalty += SPLIT_PENALTY
				plans.append({
					"segment": slot.segment,
					"side": slot.side,
					"col": run[start],
					"width": width,
					"columns": columns,
					"front": front,
					"dir": CityGrid._dir_of_vector(slot.front),
					"depth": depth,
					"options": options,
					"penalty": penalty,
				})
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.penalty < b.penalty)
	# Лучший план, где дом влезает (FreeStrips.house_pose); проверяем по порядку — обычно хватает первого.
	for plan: Dictionary in plans:
		var fits: Dictionary[int, bool] = {}
		var fitting: Array = []
		for data: BuildingData in plan.options:
			if not fits.has(data.size.y):
				fits[data.size.y] = strips.house_pose(plan.segment, plan.side, plan.col, plan.columns,
						data.size.x * CityGrid.CELL_SIZE, data.size.y * CityGrid.CELL_SIZE).ok
			if fits[data.size.y]:
				fitting.append(data)
		if not fitting.is_empty():
			plan.options = fitting
			return plan
	return {}


## Ячейка свободна под зону: есть, этой зоны, не занята участком, все её клетки — свободная земля.
static func _free_slot_ok(grid: CityGrid, zone_type: CityGrid.Zone, slot: FreeStrips.Slot) -> bool:
	if slot == null or slot.zone != zone_type or grid.free_strips.occupied.has(slot.id):
		return false
	for cell: Vector2i in slot.cells:
		if not grid.zoned_empty_cells[zone_type].has(cell):
			return false
	return true


## Ставит дом data по плану plan_free_at под углом дороги и участок на plan.depth рядов: дом — у дороги,
## позади и по бокам — двор. Под домом — клетки участка, чьи центры под ним (хоть одна — ближайшая к его
## середине). Номер дома или −1.
static func build_free_lot(grid: CityGrid, data: BuildingData, plan: Dictionary) -> int:
	var strips: FreeStrips = grid.free_strips
	var lot: Array[Vector2i] = []
	for col: int in range(plan.col, plan.col + plan.columns):
		for row: int in range(1, plan.depth + 1):
			var slot: FreeStrips.Slot = strips.slot_in(plan.segment, plan.side, col, row)
			if slot != null:
				lot.append_array(slot.cells)
	if lot.is_empty():
		return -1
	var pose: Dictionary = strips.house_pose(plan.segment, plan.side, plan.col, plan.columns,
			data.size.x * CityGrid.CELL_SIZE, data.size.y * CityGrid.CELL_SIZE)
	var under: PackedVector2Array = Geometry2D.offset_polygon(pose.corners, HOUSE_CELL_MARGIN)[0]
	var house: Array[Vector2i] = []
	var nearest: Vector2i = lot[0]
	for cell: Vector2i in lot:
		var center: Vector2 = RoadGraph.cell_center(cell)
		if Geometry2D.is_point_in_polygon(center, under):
			house.append(cell)
		if center.distance_squared_to(pose.center) < RoadGraph.cell_center(nearest).distance_squared_to(pose.center):
			nearest = cell
	if house.is_empty():
		house.append(nearest)
	var id: int = grid.place_free_building(data.id, house, pose.center, pose.yaw, plan.dir)
	if id != -1:
		grid.add_free_lot(lot, strips.lot_shape(plan.segment, plan.side, plan.col, plan.columns, plan.depth).corners, plan.dir)
	return id


## Свободная фасадная клетка той же зоны и той же улицы.
static func _is_frontage(grid: CityGrid, cell: Vector2i, zone_type: CityGrid.Zone, dir: int) -> bool:
	return grid.zoned_empty_cells[zone_type].has(cell) and grid.get_strip_dir(cell) == dir \
			and grid.get_strip_depth(cell) == 1


## Сколько свободных клеток той же зоны и полосы подряд от фасадной клетки вглубь (до STRIP_DEPTH).
static func _column_depth(grid: CityGrid, front: Vector2i, zone_type: CityGrid.Zone, dir: int) -> int:
	var inward: Vector2i = -CityGrid.NEIGHBORS[dir]
	var depth: int = 1
	while depth < CityGrid.STRIP_DEPTH:
		var c: Vector2i = front + inward * depth
		if not grid.zoned_empty_cells[zone_type].has(c) or grid.get_strip_dir(c) != dir \
				or grid.get_strip_depth(c) != depth + 1:
			break
		depth += 1
	return depth


## Тип дома: при глубоком участке чаще глубиной 2 (меньше двора), иначе — глубиной 1.
static func _pick_type(options: Array, depth: int, rng: RandomNumberGenerator) -> BuildingData:
	var deep: Array = options.filter(func(data: BuildingData) -> bool: return data.size.y >= 2)
	var shallow: Array = options.filter(func(data: BuildingData) -> bool: return data.size.y < 2)
	if not deep.is_empty() and depth >= 2 and (shallow.is_empty() or rng.randf() < DEEP_SHARE):
		return BuildingCatalog.pick_weighted(deep, rng)
	return BuildingCatalog.pick_weighted(shallow if not shallow.is_empty() else options, rng)


## Прямоугольник от клеток фасада front вглубь (от улицы в сторону −dir) на depth клеток.
static func _rect_inward(front: Array[Vector2i], dir: int, depth: int) -> Rect2i:
	var inward: Vector2i = -CityGrid.NEIGHBORS[dir]
	var lo: Vector2i = front[0]
	var hi: Vector2i = front[0]
	for c: Vector2i in front:
		for k: int in depth:
			var p: Vector2i = c + inward * k
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2i(lo, hi - lo + Vector2i.ONE)
