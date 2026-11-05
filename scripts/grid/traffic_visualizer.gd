class_name TrafficVisualizer
extends MultiMeshInstance3D
## Машинки на дорогах — только визуал: на симуляцию не влияют и не сохраняются.
## Каждая едет по пути из выборки GameState.traffic.sample_paths (из дома на работу или обратно),
## у цели «паркуется» и берёт новую поездку. Внутри клетки — квадратичная кривая Безье
## от середины входного ребра к середине выходного (на прямой — прямая, на повороте — дуга).
## Правила (умный трафик): держат дистанцию до машины впереди в своей полосе и плавно тормозят
## и разгоняются; стоят на красный у перекрёстка (TrafficLights); на проспектах и шоссе — две
## полосы в каждую сторону.
## Пешеходы и велосипедисты (PeopleVisualizer) — тот же код без правил: переопределяют _paths,
## _target_count, _speed, _lane_offset, _slowdown, _obeys_rules, _load_layers, _dress и _bob.

const MAX_CARS: int = 300
## Сколько работников «изображает» одна машинка (≈ сколько людей в машине).
const WORKERS_PER_CAR: float = 1.3
## Скорость, клеток в секунду на ×1.
const SPEED: float = 2.0
## Сдвиг на правую полосу от оси дороги, метры (асфальт Kenney ×2 — полуширина ~0.8 м).
const LANE_OFFSET: float = 0.3
## На загруженной клетке машинка медленнее в (1 + JAM_SLOWDOWN · загрузка) раз (загрузка до 2).
const JAM_SLOWDOWN: float = 0.7
## Полосы проспекта и шоссе (две в каждую сторону): сдвиг от оси, метры.
const MULTI_LANES: Array[float] = [0.3, 0.62]
## Дистанция до машины впереди, доля клетки (машина ~0.7 м из 2 м).
const MIN_GAP: float = 0.5
## Стоп-линия перед перекрёстком: доля клетки, дальше которой на красный не заезжают.
const STOP_LINE: float = 0.8
## Разгон и торможение: доля полной скорости в секунду.
const ACCEL: float = 2.5
## Модели машин (Kenney Car Kit) и их вес при выборе. По одному MultiMesh на модель.
## Полиция — вес 0.25 из 9.25, около 3 % машин.
const CAR_MODELS: Dictionary[String, float] = {
	"res://assets/models/kenney/cars/sedan.glb": 1.0,
	"res://assets/models/kenney/cars/taxi.glb": 1.0,
	"res://assets/models/kenney/cars/suv.glb": 1.0,
	"res://assets/models/kenney/cars/van.glb": 1.0,
	"res://assets/models/kenney/cars/truck.glb": 1.0,
	"res://assets/models/kenney/cars/delivery.glb": 1.0,
	"res://assets/models/kenney/cars/hatchback-sports.glb": 1.0,
	"res://assets/models/kenney/cars/sedan-sports.glb": 1.0,
	"res://assets/models/kenney/cars/suv-luxury.glb": 1.0,
	"res://assets/models/kenney/cars/police.glb": 0.25,
}
## Масштаб моделей машин: седан 2.55 м → ~0.7 м, помещается в полосу.
const CAR_MODEL_SCALE: float = 0.28
## Поворот моделей: у Kenney перед машины на +Z, у нас «вперёд» — −Z.
const CAR_MODEL_TURNS: int = 2
## Верх асфальта (дороги Kenney — 0..0.02).
const ROAD_TOP: float = 0.02
## Заглушка, если моделей нет: коробочка своего цвета.
const CAR_SIZE := Vector3(0.45, 0.3, 0.8)
const CAR_COLORS: Array[Color] = [
	Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.85), Color(0.95, 0.85, 0.3),
	Color(0.9, 0.9, 0.9), Color(0.25, 0.25, 0.28), Color(0.3, 0.7, 0.4),
]


## Одна машинка: путь (индексы клеток), продвижение в клетках, направление, модель.
class Car extends RefCounted:
	var path := PackedInt32Array()
	## От 0 до path.size(): целая часть — номер клетки, дробная — доля пути по ней.
	var progress: float = 0.0
	## true — от дома к работе, false — обратно.
	var forward: bool = true
	## Номер слоя (модели) в _layers.
	var model: int = 0
	var color := Color.WHITE
	## Свой цвет одежды или рамы (INSTANCE_CUSTOM, BuildingPalette) — у пешеходов и велосипедистов.
	var custom := Color(0, 0, 0, 0)
	## Полоса на дорогах с двумя полосами (0 — ближе к оси, 1 — к тротуару).
	var lane: int = 0
	## Текущая скорость, доля полной (разгон и торможение — ACCEL).
	var speed: float = 1.0


var _cars: Array[Car] = []
## Слои MultiMesh: по одному на модель машины; без моделей — один слой-заглушка (сам узел).
var _layers: Array[MultiMeshInstance3D] = []
## Вес выбора каждого слоя (как в CAR_MODELS).
var _weights := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _seen_grid: CityGrid = null
var _seen_roads_version: int = -1
## Кто где едет в этом кадре: ключ «клетка · направление · полоса» → продвижения по клетке (0..1).
var _occupancy: Dictionary[int, PackedFloat32Array] = {}


func _ready() -> void:
	_rng.randomize()
	_load_layers()


## Слои моделей: по MultiMesh на модель машины (пешеходы — свои модели).
func _load_layers() -> void:
	for path: String in CAR_MODELS:
		if not ResourceLoader.exists(path):
			continue
		var mesh: ArrayMesh = ModelLoader.fitted(load(path), CAR_MODEL_SCALE, CAR_MODEL_TURNS)
		var layer := MultiMeshInstance3D.new()
		layer.multimesh = _new_multimesh(mesh, false)
		# Машины мелкие и их много: тени от них почти не видны, а стоят дорого.
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(layer)
		_layers.append(layer)
		_weights.append(CAR_MODELS[path])
	if _layers.is_empty():
		multimesh = _new_multimesh(_placeholder_mesh(), true)
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_layers.append(self)
		_weights.append(1.0)


func _process(delta: float) -> void:
	_check_roads()
	_sync_car_count()
	var grid: CityGrid = GameState.grid
	var step: float = _speed() * SimClock.speed * delta
	var counts := PackedInt32Array()
	counts.resize(_layers.size())
	counts.fill(0)
	if step > 0.0 and _obeys_rules():
		_fill_occupancy(grid)
	for car: Car in _cars:
		if step > 0.0:
			_advance(car, grid, step, delta * SimClock.speed)
		var layer: MultiMesh = _layers[car.model].multimesh
		var index: int = counts[car.model]
		counts[car.model] += 1
		layer.set_instance_transform(index, _car_transform(car, grid))
		if layer.use_colors:
			layer.set_instance_color(index, car.color)
		if layer.use_custom_data:
			layer.set_instance_custom_data(index, car.custom)
	for i: int in _layers.size():
		_layers[i].multimesh.visible_instance_count = counts[i]


## Сколько машинок видно (для проверок).
func visible_car_count() -> int:
	var total: int = 0
	for layer: MultiMeshInstance3D in _layers:
		total += layer.multimesh.visible_instance_count
	return total


## Положение i-й машинки (для проверок).
func car_origin(i: int) -> Vector3:
	return _car_transform(_cars[i], GameState.grid).origin


static func _new_multimesh(mesh: Mesh, colored: bool) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_3D
	result.use_colors = colored
	result.mesh = mesh
	result.instance_count = MAX_CARS
	result.visible_instance_count = 0
	return result


## Коробочка, стоящая на асфальте (центр основания — в начале координат).
static func _placeholder_mesh() -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = CAR_SIZE
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in vertices.size():
		vertices[i].y += CAR_SIZE.y * 0.5
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	mesh.surface_set_material(0, material)
	return mesh


## Сколько машинок нужно: по числу работников на машинах, не больше MAX_CARS; без путей — ни одной.
func _target_count() -> int:
	var traffic: Traffic = GameState.traffic
	if _paths().is_empty():
		return 0
	var drivers: float = maxf(0.0, traffic.total_workers - traffic.walkers - traffic.cyclists)
	if is_nan(drivers):
		return 0
	return mini(MAX_CARS, roundi(drivers / WORKERS_PER_CAR))


## Откуда брать пути (машины — sample_paths).
func _paths() -> Array[PackedInt32Array]:
	return GameState.traffic.sample_paths


## Скорость, клеток в секунду на ×1.
func _speed() -> float:
	return SPEED


## Сдвиг от оси дороги вправо, метры (обычная улица; проспект и шоссе — MULTI_LANES).
func _lane_offset() -> float:
	return LANE_OFFSET


## Соблюдают ли правила: дистанция, светофоры, полосы (машины — да; пешеходы и велосипеды — нет).
func _obeys_rules() -> bool:
	return true


## Во сколько раз медленнее на клетке с загрузкой ratio.
func _slowdown(ratio: float) -> float:
	return 1.0 + JAM_SLOWDOWN * minf(ratio, 2.0)


## Подпрыгивание при ходьбе, метры (у машин нет).
func _bob(_car: Car) -> float:
	return 0.0


## Новому агенту — свой вид (пешеходам — цвет одежды).
func _dress(_car: Car) -> void:
	pass


func _sync_car_count() -> void:
	# Не меньше нуля: roundi(NaN) — самое малое целое, и цикл ниже снимал бы машинки с пустого списка вечно.
	var target: int = maxi(0, _target_count())
	while _cars.size() > target:
		_cars.pop_back()
	while _cars.size() < target:
		var car := Car.new()
		car.color = CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)]
		car.model = _rng.rand_weighted(_weights)
		_dress(car)
		if not _assign_path(car):
			break
		# Первые машинки — по всему пути, чтобы город не пустовал; потом — выезжают от начала.
		if _cars.is_empty() or target - _cars.size() > 10:
			car.progress = _rng.randf() * car.path.size()
			car.speed = 1.0
		_cars.append(car)


## Новый путь из выборки (не короче двух клеток). false — подходящих путей нет.
func _assign_path(car: Car) -> bool:
	var paths: Array[PackedInt32Array] = _paths()
	var grid: CityGrid = GameState.grid
	# Пустая выборка (дорогу только что снесли, трафик ещё не пересчитан) — путей нет.
	if paths.is_empty():
		return false
	for attempt: int in 8:
		var path: PackedInt32Array = paths[_rng.randi_range(0, paths.size() - 1)]
		# Выборка может отстать от дорог (пересчёт трафика ещё не случился) — сломанный путь не берём.
		if path.size() >= 2 and _path_is_intact(path, grid):
			car.path = path
			car.progress = 0.0
			# Из дома на работу или с работы домой.
			car.forward = _rng.randf() < 0.5
			car.lane = _rng.randi_range(0, 1)
			car.speed = 0.0
			return true
	return false


## Дороги изменились — машинки со сломанным путём сразу берут новый; новый город — все заново.
func _check_roads() -> void:
	var grid: CityGrid = GameState.grid
	if grid != _seen_grid:
		_cars.clear()
	elif grid.roads_version != _seen_roads_version:
		for car: Car in _cars:
			if not _path_is_intact(car.path, grid) and not _assign_path(car):
				car.path = PackedInt32Array()
		_cars = _cars.filter(func(car: Car) -> bool: return car.path.size() >= 2)
	_seen_grid = grid
	_seen_roads_version = grid.roads_version


static func _path_is_intact(path: PackedInt32Array, grid: CityGrid) -> bool:
	for index: int in path:
		if index >= grid.tile_type.size() or grid.tile_type[index] != CityGrid.Tile.ROAD:
			return false
	return true


func _advance(car: Car, grid: CityGrid, step: float, dt: float) -> void:
	var k: int = mini(int(car.progress), car.path.size() - 1)
	var ratio: float = GameState.traffic.load_ratio(grid, _path_index(car, k))
	var target: float = 1.0 / _slowdown(ratio)
	var allowed: float = INF
	if _obeys_rules():
		allowed = _free_ahead(car, grid, k)
	# Перед помехой — тормозим, иначе плавно разгоняемся до скорости улицы.
	car.speed = move_toward(car.speed, target if allowed > step else 0.0, ACCEL * dt)
	car.progress += clampf(step * car.speed, 0.0, maxf(0.0, allowed))
	if car.progress < car.path.size():
		return
	# Доехали: машина «паркуется», вместо неё — новая поездка.
	if not _assign_path(car):
		car.progress = 0.0


## Сколько можно проехать (доля клеток): до машины впереди в своей полосе (с дистанцией)
## и до стоп-линии, если на следующем перекрёстке красный.
func _free_ahead(car: Car, grid: CityGrid, k: int) -> float:
	var t: float = car.progress - k
	var free: float = INF
	var own: PackedFloat32Array = _occupancy.get(_occupancy_key(car, grid, k), PackedFloat32Array())
	for other: float in own:
		if other > t + 0.001:
			free = minf(free, other - t - MIN_GAP)
	if k + 1 < car.path.size():
		var ahead: PackedFloat32Array = _occupancy.get(_occupancy_key(car, grid, k + 1), PackedFloat32Array())
		for other: float in ahead:
			free = minf(free, 1.0 - t + other - MIN_GAP)
		# Светофор: следующая клетка — перекрёсток, мы ещё до стоп-линии, по нашей оси красный.
		var here: Vector2i = _cell_of(_path_index(car, k), grid)
		var next: Vector2i = _cell_of(_path_index(car, k + 1), grid)
		if t <= STOP_LINE and TrafficLights.is_junction(grid, next) \
				and not TrafficLights.is_green(next, TrafficLights.axis_of(next - here)):
			free = minf(free, STOP_LINE - t)
	return free


## Ключ занятости: клетка, направление движения в ней и полоса.
func _occupancy_key(car: Car, grid: CityGrid, k: int) -> int:
	var index: int = _path_index(car, k)
	var here: Vector2i = _cell_of(index, grid)
	var step := Vector2i.ZERO
	if k + 1 < car.path.size():
		step = _cell_of(_path_index(car, k + 1), grid) - here
	elif k > 0:
		step = here - _cell_of(_path_index(car, k - 1), grid)
	var heading: int = maxi(0, CityGrid.NEIGHBORS.find(step))
	var lane: int = car.lane if _lanes_at(grid, index) == 2 else 0
	return (index * 4 + heading) * 2 + lane


## Сколько полос в каждую сторону на клетке.
static func _lanes_at(grid: CityGrid, index: int) -> int:
	var road_type: int = grid.road_type[index] if index < grid.road_type.size() else 0
	return 2 if road_type == RoadTypes.Type.AVENUE or road_type == RoadTypes.Type.HIGHWAY else 1


func _fill_occupancy(grid: CityGrid) -> void:
	_occupancy.clear()
	for car: Car in _cars:
		var k: int = mini(int(car.progress), car.path.size() - 1)
		var key: int = _occupancy_key(car, grid, k)
		if not _occupancy.has(key):
			_occupancy[key] = PackedFloat32Array()
		_occupancy[key].append(car.progress - k)


## Сдвиг от оси для машины на клетке: на проспекте и шоссе — по её полосе.
func _lane_for(car: Car, grid: CityGrid, index: int) -> float:
	if _obeys_rules() and _lanes_at(grid, index) == 2:
		return MULTI_LANES[car.lane]
	return _lane_offset()


## Индекс клетки пути с учётом направления (обратно — путь задом наперёд).
func _path_index(car: Car, k: int) -> int:
	return car.path[k] if car.forward else car.path[car.path.size() - 1 - k]


func _car_transform(car: Car, grid: CityGrid) -> Transform3D:
	var count: int = car.path.size()
	var k: int = mini(int(car.progress), count - 1)
	var t: float = clampf(car.progress - k, 0.0, 1.0)
	var cell: Vector2i = _cell_of(_path_index(car, k), grid)
	var center: Vector3 = grid.grid_to_world(cell) + Vector3.UP * (ROAD_TOP + _bob(car))
	var half: float = CityGrid.CELL_SIZE * 0.5
	var has_prev: bool = k > 0
	var has_next: bool = k < count - 1
	var prev_cell: Vector2i = _cell_of(_path_index(car, k - 1), grid) if has_prev else cell
	var next_cell: Vector2i = _cell_of(_path_index(car, k + 1), grid) if has_next else cell
	# Полоса: на входе — как на этой клетке, на выходе — как на следующей (плавная смена полос).
	var lane_in: float = _lane_for(car, grid, _path_index(car, k))
	var lane_out: float = _lane_for(car, grid, _path_index(car, k + 1)) if has_next else lane_in
	var dir_in: Vector3 = _dir(cell - prev_cell) if has_prev else _dir(next_cell - cell)
	var dir_out: Vector3 = _dir(next_cell - cell) if has_next else dir_in
	var right_in := Vector3(-dir_in.z, 0.0, dir_in.x)
	var right_out := Vector3(-dir_out.z, 0.0, dir_out.x)
	# Середина входного и выходного рёбер клетки (на концах пути — центр), на правой полосе.
	var p0: Vector3 = (center - dir_in * half if has_prev else center) + right_in * lane_in
	var p2: Vector3 = (center + dir_out * half if has_next else center) + right_out * lane_out
	var p1: Vector3 = center + (right_in * lane_in + right_out * lane_out) * 0.5
	var point: Vector3 = p0 * (1.0 - t) * (1.0 - t) + p1 * 2.0 * (1.0 - t) * t + p2 * t * t
	var tangent: Vector3 = (p1 - p0) * 2.0 * (1.0 - t) + (p2 - p1) * 2.0 * t
	if tangent.length_squared() < 0.0001:
		tangent = dir_out
	return Transform3D(Basis.looking_at(tangent.normalized(), Vector3.UP), point)


@warning_ignore("integer_division")
static func _cell_of(index: int, grid: CityGrid) -> Vector2i:
	return Vector2i(index % grid.size, index / grid.size)


static func _dir(offset: Vector2i) -> Vector3:
	return Vector3(offset.x, 0.0, offset.y).normalized()
