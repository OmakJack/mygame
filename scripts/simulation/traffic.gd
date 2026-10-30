class_name Traffic
extends RefCounted
## Потоки поездок «дом → работа» по дорогам и пробки. Без отдельных машин: считаем поездки целиком.
## Многоисточниковый Дейкстра от всех мест работы сразу даёт пути всех домов за один проход.
## SUB_PASSES проходов, каждый развозит часть работников с учётом уже набранной загрузки:
## поток делится между дорогой и объездом, а переполненная работа становится «дороже».

## Доля жителей, которые ездят на работу.
const WORK_SHARE: float = 0.5
## Сколько поездок выдерживает клетка обычной дороги.
const CAPACITY: float = 80.0
const BASE_COST: float = 1.0
## Добавка к стоимости клетки за каждую единицу перегрузки.
const JAM_PENALTY: float = 3.0
## Добавка к старту места работы за каждую единицу переполнения рабочих мест. Должна быть
## заметно круче штрафа пробки: число мест — жёсткий предел, а пробка — нет (иначе люди
## «предпочли» бы переполненный магазин забитой дороге в промзону).
const JOB_OVERLOAD_PENALTY: float = 20.0
const SUB_PASSES: int = 6
## Время до работы: до OK — нормально, к MAX — тяжесть растёт до 1.
const OK_COMMUTE: float = 25.0
const MAX_COMMUTE: float = 60.0
## Поправка жилого спроса за долю тяжёлых поездок.
const WEIGHT: float = 0.3
const MAX_SAMPLE_PATHS: int = 120
## Доля рабочих мест, которую занимают приезжие с трассы (въезжают через въезд, как в C:S).
const COMMUTER_SHARE: float = 0.15
const INFINITE: float = 1.0e20

## Как добираться (пешеходы и велосипеды): время пешком и на велосипеде — на клетку пути;
## машина — время по дорогам с пробками. Доли — по логиту: exp(−время / MODE_SPREAD).
## Пешком — не дальше WALK_MAX клеток, на велосипеде — BIKE_MAX; по шоссе никто не идёт и не едет.
## В пробке машина медленнее — часть людей пересаживается на велосипед или идёт пешком,
## и пробка рассасывается: на дороги идёт только доля машин.
const WALK_COST: float = 2.5
const BIKE_COST: float = 2.2
## Велосипед ещё достать и поставить.
const BIKE_EXTRA: float = 4.0
const WALK_MAX: int = 12
const BIKE_MAX: int = 30
const MODE_SPREAD: float = 4.0
const MAX_PEOPLE_PATHS: int = 80
## С какой доли пеших (велосипедистов) путь дома попадает в выборку для фигурок.
const PEOPLE_PATH_SHARE: float = 0.12

## Нагрузка по индексу клетки (поездок за день).
var road_load := PackedFloat32Array()
## id дома → тяжесть поездки в [0, 1] (1 — работы не достать).
var home_badness: Dictionary[int, float] = {}
var jammed_cells: int = 0
var average_commute: float = 0.0
## Средняя тяжесть поездки по работникам, [0, 1].
var long_commute_share: float = 0.0
var total_workers: float = 0.0
## Выборка путей (индексы клеток от дороги дома до дороги работы) — для машинок.
var sample_paths: Array[PackedInt32Array] = []
## Выборки путей пешеходов и велосипедистов — для фигурок на тротуарах.
var walk_paths: Array[PackedInt32Array] = []
var bike_paths: Array[PackedInt32Array] = []
## Сколько работников (жителей города) идут пешком и едут на велосипеде.
var walkers: float = 0.0
var cyclists: float = 0.0


## Доли способов добраться до работы: Vector3(машина, велосипед, пешком).
## car_time — время на машине с пробками; length — длина пути в клетках; highway — путь идёт по шоссе.
static func mode_shares(car_time: float, length: float, highway: bool) -> Vector3:
	if highway:
		return Vector3(1.0, 0.0, 0.0)
	var car: float = exp(-car_time / MODE_SPREAD)
	var bike: float = exp(-(length * BIKE_COST + BIKE_EXTRA) / MODE_SPREAD) if length <= BIKE_MAX else 0.0
	var walk: float = exp(-length * WALK_COST / MODE_SPREAD) if length <= WALK_MAX else 0.0
	var sum: float = car + bike + walk
	if sum <= 0.0:
		return Vector3(1.0, 0.0, 0.0)
	return Vector3(car, bike, walk) / sum


## Время поездки по способу: машина — car_time, велосипед и пешком — по длине пути.
static func mode_times(car_time: float, length: float) -> Vector3:
	return Vector3(car_time, length * BIKE_COST + BIKE_EXTRA, length * WALK_COST)


## Поправка жилого спроса.
func demand_offset() -> float:
	return -WEIGHT * long_commute_share


## Загрузка клетки: нагрузка / ёмкость.
func load_ratio(grid: CityGrid, index: int) -> float:
	if road_load.is_empty():
		return 0.0
	return road_load[index] / _cell_capacity(grid, index)


## Ёмкость и время проезда клетки — по типу дороги (фаза 11, RoadTypes).
static func _cell_capacity(grid: CityGrid, index: int) -> float:
	return RoadTypes.CAPACITY.get(grid.road_type[index], CAPACITY)


static func _cell_base_cost(grid: CityGrid, index: int) -> float:
	return RoadTypes.TRAVEL_COST.get(grid.road_type[index], BASE_COST)


static func compute(grid: CityGrid) -> Traffic:
	var traffic := Traffic.new()
	var cell_count: int = grid.size * grid.size
	traffic.road_load.resize(cell_count)
	traffic.road_load.fill(0.0)

	# Дома (откуда) и рабочие места на клетках дорог (куда).
	var home_ids := PackedInt32Array()
	var home_road := PackedInt32Array()
	var home_access := PackedFloat32Array()
	var home_workers := PackedFloat32Array()
	var jobs_at := PackedFloat32Array()
	jobs_at.resize(cell_count)
	jobs_at.fill(0.0)
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		var road: Vector2i = grid.find_nearest_road(building.cell)
		if road == CityGrid.NO_CELL:
			continue
		if CityGrid.is_residential(data.zone) and data.population > 0:
			home_ids.append(building.id)
			home_road.append(grid.index_of(road))
			home_access.append(absi(road.x - building.cell.x) + absi(road.y - building.cell.y))
			home_workers.append(data.population * WORK_SHARE)
		elif data.jobs > 0 and building.powered and building.has_water \
				and data.zone != CityGrid.Zone.NONE:
			jobs_at[grid.index_of(road)] += data.jobs
	var sources := PackedInt32Array()
	var total_jobs: float = 0.0
	for index: int in cell_count:
		if jobs_at[index] > 0.0:
			sources.append(index)
			total_jobs += jobs_at[index]
	for workers: float in home_workers:
		traffic.total_workers += workers
	# Приезжие с трассы: «дом» на клетке въезда (номер −1: не дом города, в счастье и итоги не идёт).
	if grid.has_entry() and grid.is_road(grid.entry) and total_jobs > 0.0:
		home_ids.append(-1)
		home_road.append(grid.index_of(grid.entry))
		home_access.append(0.0)
		home_workers.append(total_jobs * COMMUTER_SHARE)

	var home_count: int = home_ids.size()
	var commute_sum := PackedFloat32Array()
	commute_sum.resize(home_count)
	commute_sum.fill(0.0)
	var reached := PackedInt32Array()
	reached.resize(home_count)
	reached.fill(0)
	var arrivals := PackedFloat32Array()
	arrivals.resize(cell_count)
	arrivals.fill(0.0)
	var cost := PackedFloat32Array()
	cost.resize(cell_count)
	var dist := PackedFloat32Array()
	dist.resize(cell_count)
	var next := PackedInt32Array()
	next.resize(cell_count)
	# Штраф переполнения каждой работы в текущем проходе (чтобы вычесть его из времени дороги).
	var penalty := PackedFloat32Array()
	penalty.resize(cell_count)
	# Работа, к которой ведёт клетка, и поток, проходящий через клетку, — в текущем проходе.
	var source_of := PackedInt32Array()
	source_of.resize(cell_count)
	var flow_at := PackedFloat32Array()
	flow_at.resize(cell_count)
	# Длина пути до работы в клетках и есть ли на нём шоссе — для пешеходов и велосипедов.
	var hops := PackedInt32Array()
	hops.resize(cell_count)
	var via_highway := PackedByteArray()
	via_highway.resize(cell_count)
	var sample_stride: int = maxi(1, ceili(float(home_count * SUB_PASSES) / MAX_SAMPLE_PATHS))

	for pass_index: int in SUB_PASSES:
		# Набранная загрузка — в пересчёте на весь поток (прошло pass_index проходов из SUB_PASSES).
		var scale: float = float(SUB_PASSES) / pass_index if pass_index > 0 else 0.0
		for road: Vector2i in grid.road_cells:
			var index: int = grid.index_of(road)
			var ratio: float = traffic.road_load[index] * scale / _cell_capacity(grid, index)
			cost[index] = _cell_base_cost(grid, index) + JAM_PENALTY * maxf(0.0, ratio - 1.0)
		var order: PackedInt32Array = _dijkstra(grid, sources, jobs_at, arrivals, scale, cost, penalty, dist, next)
		# Клетки в порядке Дейкстры: «следующая» клетка всегда раньше — источник протягиваем вперёд.
		for cell: int in order:
			source_of[cell] = cell if next[cell] == -1 else source_of[next[cell]]
			var on_highway: int = 1 if grid.road_type[cell] == RoadTypes.Type.HIGHWAY else 0
			if next[cell] == -1:
				hops[cell] = 0
				via_highway[cell] = on_highway
			else:
				hops[cell] = hops[next[cell]] + 1
				via_highway[cell] = on_highway | via_highway[next[cell]]

		flow_at.fill(0.0)
		for home: int in home_count:
			var start: int = home_road[home]
			if dist[start] >= INFINITE:
				continue
			var flow: float = home_workers[home] / SUB_PASSES
			# Штраф переполненной работы — только для выбора пути, во время дороги не входит.
			var car_time: float = dist[start] - penalty[source_of[start]] + home_access[home]
			var length: float = hops[start] + home_access[home]
			# Приезжие с трассы — только на машинах.
			var shares := Vector3(1.0, 0.0, 0.0)
			if home_ids[home] >= 0:
				shares = mode_shares(car_time, length, via_highway[start] == 1)
				traffic.cyclists += flow * shares.y
				traffic.walkers += flow * shares.z
			# На дороги идут только машины; пешие и велосипедисты сразу «доходят» до работы.
			flow_at[start] += flow * shares.x
			arrivals[source_of[start]] += flow * (shares.y + shares.z)
			commute_sum[home] += shares.dot(mode_times(car_time, length))
			reached[home] += 1
			if (home + pass_index) % sample_stride == 0:
				if traffic.sample_paths.size() < MAX_SAMPLE_PATHS and shares.x >= PEOPLE_PATH_SHARE:
					traffic.sample_paths.append(_walk(start, next))
				if traffic.bike_paths.size() < MAX_PEOPLE_PATHS and shares.y >= PEOPLE_PATH_SHARE:
					traffic.bike_paths.append(_walk(start, next))
				if traffic.walk_paths.size() < MAX_PEOPLE_PATHS and shares.z >= PEOPLE_PATH_SHARE:
					traffic.walk_paths.append(_walk(start, next))
		# Пути образуют дерево к местам работы: поток собираем одним проходом с конца порядка Дейкстры
		# (O(дороги) вместо O(дома · длина пути)).
		for i: int in range(order.size() - 1, -1, -1):
			var cell: int = order[i]
			var flow: float = flow_at[cell]
			if flow == 0.0:
				continue
			traffic.road_load[cell] += flow
			if next[cell] == -1:
				arrivals[cell] += flow
			else:
				flow_at[next[cell]] += flow

	_summarize(traffic, grid, home_ids, home_workers, commute_sum, reached)
	return traffic


## Путь по указателям next от клетки до места работы (для машинок).
static func _walk(start: int, next: PackedInt32Array) -> PackedInt32Array:
	var path := PackedInt32Array()
	var current: int = start
	while current != -1:
		path.append(current)
		current = next[current]
	return path


## Многоисточниковый Дейкстра: dist — время до ближайшей работы, next — следующая клетка к ней,
## penalty — штраф переполнения у источников. Возвращает клетки в порядке, в каком они «устоялись».
## Двоичная куча — прямо здесь, на локальных массивах: вызовы методов объекта-кучи в GDScript
## стоили больше самого поиска (замер на 256×256).
static func _dijkstra(grid: CityGrid, sources: PackedInt32Array, jobs_at: PackedFloat32Array,
		arrivals: PackedFloat32Array, scale: float, cost: PackedFloat32Array, penalty: PackedFloat32Array,
		dist: PackedFloat32Array, next: PackedInt32Array) -> PackedInt32Array:
	dist.fill(INFINITE)
	next.fill(-1)
	var order := PackedInt32Array()
	var size: int = grid.size
	var cell_count: int = dist.size()
	# Локальная копия слоя: обращение к свойству grid в горячем цикле заметно дороже.
	var tiles: PackedByteArray = grid.tile_type
	var road: int = CityGrid.Tile.ROAD
	# Куча: элементы и ключи, занято heap_size мест (массивы только растут — без resize на каждом шаге).
	var heap_items := PackedInt32Array()
	var heap_keys := PackedFloat32Array()
	var heap_size: int = 0
	var pending := sources.duplicate()
	for source: int in sources:
		var overload: float = arrivals[source] * scale / jobs_at[source]
		penalty[source] = JOB_OVERLOAD_PENALTY * maxf(0.0, overload - 1.0)
		dist[source] = penalty[source] + cost[source]
	# Сначала источники, потом соседи: одна и та же вставка для обоих.
	var push_index: int = 0
	while true:
		# --- вставка очередного источника или соседа (pending) ---
		while push_index < pending.size():
			var item: int = pending[push_index]
			var key: float = dist[item]
			push_index += 1
			if heap_size == heap_items.size():
				heap_items.append(item)
				heap_keys.append(key)
			else:
				heap_items[heap_size] = item
				heap_keys[heap_size] = key
			var i: int = heap_size
			heap_size += 1
			while i > 0:
				var parent: int = (i - 1) >> 1
				if heap_keys[parent] <= key:
					break
				heap_items[i] = heap_items[parent]
				heap_keys[i] = heap_keys[parent]
				i = parent
			heap_items[i] = item
			heap_keys[i] = key
		pending.clear()
		push_index = 0
		if heap_size == 0:
			break
		# --- извлечение минимума ---
		var current: int = heap_items[0]
		var current_key: float = heap_keys[0]
		heap_size -= 1
		if heap_size > 0:
			var moved: int = heap_items[heap_size]
			var moved_key: float = heap_keys[heap_size]
			var i: int = 0
			while true:
				var child: int = 2 * i + 1
				if child >= heap_size:
					break
				if child + 1 < heap_size and heap_keys[child + 1] < heap_keys[child]:
					child += 1
				if heap_keys[child] >= moved_key:
					break
				heap_items[i] = heap_items[child]
				heap_keys[i] = heap_keys[child]
				i = child
			heap_items[i] = moved
			heap_keys[i] = moved_key
		# Устаревшая запись: клетку уже достали с меньшим ключом.
		if current_key > dist[current]:
			continue
		order.append(current)
		var x: int = current % size
		var here: float = dist[current]
		# Соседи по 4 сторонам — только клетки дорог. Без массива соседей: он создавался бы на каждом шаге.
		for side: int in 4:
			var neighbor: int
			match side:
				0:
					neighbor = current - size
				1:
					neighbor = current + 1 if x < size - 1 else -1
				2:
					neighbor = current + size
				_:
					neighbor = current - 1 if x > 0 else -1
			if neighbor < 0 or neighbor >= cell_count or tiles[neighbor] != road:
				continue
			var candidate: float = here + cost[neighbor]
			# Строго меньше: клетка возвращается в кучу только с меньшим ключом,
			# поэтому в order попадает ровно один раз.
			if candidate < dist[neighbor]:
				dist[neighbor] = candidate
				next[neighbor] = current
				pending.append(neighbor)
	return order


static func _summarize(traffic: Traffic, grid: CityGrid, home_ids: PackedInt32Array,
		home_workers: PackedFloat32Array, commute_sum: PackedFloat32Array, reached: PackedInt32Array) -> void:
	for road: Vector2i in grid.road_cells:
		if traffic.load_ratio(grid, grid.index_of(road)) >= 1.0:
			traffic.jammed_cells += 1
	var badness_sum: float = 0.0
	var commute_weighted: float = 0.0
	var reached_workers: float = 0.0
	for home: int in home_ids.size():
		if home_ids[home] < 0:
			continue
		var badness: float = 1.0
		if reached[home] > 0:
			var commute: float = commute_sum[home] / reached[home]
			badness = clampf((commute - OK_COMMUTE) / (MAX_COMMUTE - OK_COMMUTE), 0.0, 1.0)
			commute_weighted += commute * home_workers[home]
			reached_workers += home_workers[home]
		traffic.home_badness[home_ids[home]] = badness
		badness_sum += badness * home_workers[home]
	if traffic.total_workers > 0.0:
		traffic.long_commute_share = badness_sum / traffic.total_workers
	if reached_workers > 0.0:
		traffic.average_commute = commute_weighted / reached_workers
