class_name LotPlanner
extends RefCounted
## Как в Cities: Skylines: участок задаёт игрок разметкой зоны. Выделил одну клетку — участок 1×1
## и маленькое здание; две вдоль улицы — участок 2×1 и здание побольше на обе клетки, и т. д.
## Большое выделение делится на участки тех размеров, для которых в зоне есть здания:
## - фасад — сторона выделения, у которой больше всего дороги (иначе — к ближайшей дороге);
## - вглубь от фасада — полосы в 2 клетки (если в зоне есть здания глубиной 2), остаток — в 1;
## - вдоль фасада — наименьшим числом кусков (одно здание на 5 клеток лучше пяти по одной).


## Участки для клеток cells (только что размеченных зоной zone_type): [Rect2i, сторона фасада].
static func plan(grid: CityGrid, cells: Array[Vector2i], zone_type: CityGrid.Zone) -> Array[Array]:
	var result: Array[Array] = []
	if cells.is_empty() or zone_type == CityGrid.Zone.NONE:
		return result
	var widths: Array = _widths(zone_type)
	var single: Array[int] = widths[0]
	var double: Array[int] = widths[1]
	var wanted: Dictionary[Vector2i, bool] = {}
	var bounds := Rect2i(cells[0], Vector2i.ONE)
	for cell: Vector2i in cells:
		wanted[cell] = true
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	var dir: int = front_side(grid, bounds)
	var width: int = bounds.size.y if posmod(dir, 2) == 1 else bounds.size.x
	var depth: int = bounds.size.x if posmod(dir, 2) == 1 else bounds.size.y
	var covered: Dictionary[Vector2i, bool] = {}
	var v: int = 0
	while v < depth:
		var band: int = 2 if depth - v >= 2 and not double.is_empty() else 1
		var u: int = 0
		while u < width:
			# Сплошной кусок полосы: все клетки столбца (на всю глубину полосы) размечены.
			var run: int = 0
			while u + run < width and _column_full(bounds, dir, u + run, v, band, wanted):
				run += 1
			if run == 0:
				u += 1
				continue
			var pieces: Array[int] = _split(run, double if band == 2 else single, band == 2)
			var at: int = u
			for piece: int in pieces:
				if piece > 0:
					result.append([_local_rect(bounds, dir, at, v, piece, band), dir])
					at += piece
				else:
					# Столбец, который не делится на здания глубиной 2, — два участка 1×1.
					for k: int in band:
						result.append([_local_rect(bounds, dir, at, v + k, 1, 1), dir])
					at += 1
			for du: int in run:
				for dv: int in band:
					covered[_local_cell(bounds, dir, u + du, v + dv)] = true
			u += run
		v += band
	# Клетки, которые не вошли в полосы целиком (неровное выделение), — по одной.
	for cell: Vector2i in cells:
		if not covered.has(cell):
			result.append([Rect2i(cell, Vector2i.ONE), dir])
	return result


## Сторона фасада для прямоугольника: где больше всего клеток дороги снаружи у края.
@warning_ignore("integer_division")
static func front_side(grid: CityGrid, bounds: Rect2i) -> int:
	var best: int = -1
	var best_count: int = 0
	for dir: int in 4:
		var count: int = 0
		for cell: Vector2i in BuildingInstance.edge_cells(bounds.position, bounds.size, dir):
			if grid.is_access_road(cell + CityGrid.NEIGHBORS[dir]):
				count += 1
		if count > best_count:
			best_count = count
			best = dir
	if best == -1:
		var center := Vector2i(bounds.position.x + bounds.size.x / 2, bounds.position.y + bounds.size.y / 2)
		best = maxi(0, grid.find_nearest_road_dir(center))
	return best


## Какие ширины участков есть в зоне: [глубина 1, глубина 2] (по зданиям 1-го уровня).
static func _widths(zone_type: CityGrid.Zone) -> Array:
	var single: Array[int] = []
	var double: Array[int] = []
	for data: BuildingData in BuildingCatalog.growable_types(zone_type):
		if data.size.y == 1 and data.size.x not in single:
			single.append(data.size.x)
		elif data.size.y == 2 and data.size.x not in double:
			double.append(data.size.x)
	if 1 not in single:
		single.append(1)
	return [single, double]


## Ширина length — наименьшим числом кусков из widths; при равенстве — ровнее (самый узкий кусок
## пошире): 4 → 2 + 2, а не 3 + 1; 6 → 3 + 3. Крупные — вперёд.
## allow_split — можно ставить «0»: столбец из участков 1×1 (для полосы глубиной 2).
static func _split(length: int, widths: Array[int], allow_split: bool) -> Array[int]:
	var cost := PackedInt32Array()
	var narrowest := PackedInt32Array()
	var choice := PackedInt32Array()
	cost.resize(length + 1)
	narrowest.resize(length + 1)
	choice.resize(length + 1)
	cost.fill(1 << 20)
	cost[0] = 0
	narrowest[0] = 1 << 20
	var sorted: Array[int] = widths.duplicate()
	sorted.sort()
	sorted.reverse()
	for n: int in range(1, length + 1):
		for w: int in sorted:
			if w > n:
				continue
			var c: int = cost[n - w] + 1
			var m: int = mini(narrowest[n - w], w)
			if c < cost[n] or (c == cost[n] and m > narrowest[n]):
				cost[n] = c
				narrowest[n] = m
				choice[n] = w
		# Столбец из двух одиночных участков стоит дороже (два здания вместо одного).
		if allow_split and cost[n - 1] + 2 < cost[n]:
			cost[n] = cost[n - 1] + 2
			narrowest[n] = 1
			choice[n] = 0
	var pieces: Array[int] = []
	var n: int = length
	while n > 0:
		var w: int = choice[n]
		pieces.append(w)
		n -= maxi(1, w)
	return pieces


static func _column_full(bounds: Rect2i, dir: int, u: int, v: int, band: int,
		wanted: Dictionary[Vector2i, bool]) -> bool:
	for k: int in band:
		if not wanted.has(_local_cell(bounds, dir, u, v + k)):
			return false
	return true


## Клетка по местным координатам: u — вдоль фасада, v — вглубь от фасада.
static func _local_cell(bounds: Rect2i, dir: int, u: int, v: int) -> Vector2i:
	match posmod(dir, 4):
		0:
			return Vector2i(bounds.position.x + u, bounds.position.y + v)
		2:
			return Vector2i(bounds.position.x + u, bounds.end.y - 1 - v)
		1:
			return Vector2i(bounds.end.x - 1 - v, bounds.position.y + u)
		_:
			return Vector2i(bounds.position.x + v, bounds.position.y + u)


## Прямоугольник участка по местным координатам (ширина w вдоль фасада, глубина d).
static func _local_rect(bounds: Rect2i, dir: int, u: int, v: int, w: int, d: int) -> Rect2i:
	match posmod(dir, 4):
		0:
			return Rect2i(bounds.position.x + u, bounds.position.y + v, w, d)
		2:
			return Rect2i(bounds.position.x + u, bounds.end.y - v - d, w, d)
		1:
			return Rect2i(bounds.end.x - v - d, bounds.position.y + u, d, w)
		_:
			return Rect2i(bounds.position.x + v, bounds.position.y + u, d, w)
