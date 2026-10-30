class_name LandValue
extends RefCounted
## Слои города (фаза 9): загрязнение, шум и стоимость земли, 0..100 на клетку.
## Не сохраняются — считаются по зданиям, воде и трафику (как свет, вода и службы).
## Источник действует вокруг себя: в своей клетке — полной силой, к краю радиуса — до нуля.
## Размытие — скользящая сумма по X, потом по Y, дважды: треугольное ядро радиуса 2·R
## за несколько сложений на клетку, сколько бы ни было источников.

## Половина радиуса размытия (ядро — 2·R клеток).
const POLLUTION_R: int = 2
const NOISE_R: int = 1
const BONUS_R: int = 2
## Стоимость земли без ничего вокруг.
const BASE_VALUE: float = 25.0
## Сколько отнимают загрязнение и шум.
const POLLUTION_WEIGHT: float = 0.7
const NOISE_WEIGHT: float = 0.4
## Клетка воды поднимает цену берега.
const WATER_BONUS: float = 10.0
## Шум дороги: тихая улица и прибавка от загрузки трафика.
const ROAD_NOISE: float = 6.0
const TRAFFIC_NOISE: float = 20.0

var size: int = 0
var pollution := PackedByteArray()
var noise := PackedByteArray()
var land_value := PackedByteArray()


## Значение слоя в клетке (0, если слои ещё не посчитаны).
func value_at(layer: PackedByteArray, grid: CityGrid, cell: Vector2i) -> int:
	if layer.size() != grid.size * grid.size or not grid.is_in_bounds(cell):
		return 0
	return layer[grid.index_of(cell)]


## Средняя стоимость земли под зданиями с жителями или работой (для HUD); −1 — зданий нет.
func average_value(grid: CityGrid) -> int:
	var total: int = 0
	var count: int = 0
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and (data.population > 0 or data.jobs > 0):
			total += land_value[grid.index_of(building.cell)]
			count += 1
	return -1 if count == 0 else roundi(float(total) / count)


static func compute(grid: CityGrid, traffic: Traffic) -> LandValue:
	var result := LandValue.new()
	var n: int = grid.size * grid.size
	result.size = grid.size
	var dirty := PackedFloat32Array()
	var loud := PackedFloat32Array()
	var bonus := PackedFloat32Array()
	dirty.resize(n)
	loud.resize(n)
	bonus.resize(n)
	dirty.fill(0.0)
	loud.fill(0.0)
	bonus.fill(0.0)

	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		var i: int = grid.index_of(building.cell)
		# Дымит и шумит только работающее здание: без света или без дороги (ТЭЦ) — нет.
		var working: bool = building.powered if data.power_use > 0 else grid.has_road_access(building.cell)
		if working:
			dirty[i] += data.pollution
			loud[i] += data.noise
		# Цену земли поднимают парки всегда, службы — только работающие (ревью Argon 014).
		if data.park != BuildingData.Park.NONE or Services.is_active(grid, building, data):
			bonus[i] += data.land_value
	for cell: Vector2i in grid.road_cells:
		var i: int = grid.index_of(cell)
		var factor: float = RoadTypes.NOISE_FACTOR.get(grid.road_type[i], 1.0)
		loud[i] += (ROAD_NOISE + TRAFFIC_NOISE * clampf(traffic.load_ratio(grid, i), 0.0, 1.5)) * factor
	for i: int in n:
		if grid.water[i] == 1:
			bonus[i] += WATER_BONUS

	dirty = _blur(dirty, grid.size, POLLUTION_R)
	loud = _blur(loud, grid.size, NOISE_R)
	bonus = _blur(bonus, grid.size, BONUS_R)

	result.pollution.resize(n)
	result.noise.resize(n)
	result.land_value.resize(n)
	for i: int in n:
		var p: float = clampf(dirty[i], 0.0, 100.0)
		var q: float = clampf(loud[i], 0.0, 100.0)
		result.pollution[i] = roundi(p)
		result.noise[i] = roundi(q)
		var value: float = BASE_VALUE + bonus[i] - POLLUTION_WEIGHT * p - NOISE_WEIGHT * q
		result.land_value[i] = roundi(clampf(value, 0.0, 100.0))
	return result


## Двойное скользящее окно радиуса r по строкам и столбцам, нормировано так,
## что одиночный источник в своей клетке остаётся той же силы — и у края карты тоже:
## каждая строка дополняется нулями на 2·r с обеих сторон (как бесконечная плоскость без
## источников за картой), а не обрезается — иначе у края терялось бы до 40 % силы (ревью Argon 014).
static func _blur(layer: PackedFloat32Array, side: int, r: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = _axis(layer, side, r, true)
	out = _axis(out, side, r, false)
	# Пик ядра после двух проходов по каждой оси — (2r+1) на ось, итого (2r+1)².
	var peak: float = float((2 * r + 1) * (2 * r + 1))
	for i: int in out.size():
		out[i] /= peak
	return out


## Два прохода скользящей суммы радиуса r вдоль строк (along_x) или столбцов.
static func _axis(layer: PackedFloat32Array, side: int, r: int, along_x: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(layer.size())
	var pad: int = 2 * r
	var line_values := PackedFloat32Array()
	line_values.resize(side + 2 * pad)
	for line: int in side:
		line_values.fill(0.0)
		for t: int in side:
			line_values[pad + t] = layer[_at(line, t, side, along_x)]
		line_values = _box(_box(line_values, r), r)
		for t: int in side:
			out[_at(line, t, side, along_x)] = line_values[pad + t]
	return out


## Сумма в окне [t − r, t + r]; за краем массива — нули.
static func _box(values: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	var n: int = values.size()
	var sum: float = 0.0
	for k: int in mini(r + 1, n):
		sum += values[k]
	for t: int in n:
		out[t] = sum
		if t + r + 1 < n:
			sum += values[t + r + 1]
		if t - r >= 0:
			sum -= values[t - r]
	return out


static func _at(line: int, t: int, side: int, along_x: bool) -> int:
	return line * side + t if along_x else t * side + line
