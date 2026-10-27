class_name TrafficVisualizer
extends MultiMeshInstance3D
## Машинки на дорогах — только визуал: на симуляцию не влияют и не сохраняются.
## Каждая едет по пути из выборки GameState.traffic.sample_paths: дом → работа → дом,
## потом берёт новый путь. Правая полоса; внутри клетки — квадратичная кривая Безье
## от середины входного ребра к середине выходного (на прямой — прямая, на повороте — дуга).

const MAX_CARS: int = 300
## Сколько работников «изображает» одна машинка.
const WORKERS_PER_CAR: float = 4.0
## Скорость, клеток в секунду на ×1.
const SPEED: float = 2.0
## Сдвиг на правую полосу от оси дороги, метры (асфальт Kenney ×2 — полуширина ~0.8 м).
const LANE_OFFSET: float = 0.3
## На загруженной клетке машинка медленнее в (1 + JAM_SLOWDOWN · загрузка) раз (загрузка до 2).
const JAM_SLOWDOWN: float = 0.7
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


var _cars: Array[Car] = []
## Слои MultiMesh: по одному на модель машины; без моделей — один слой-заглушка (сам узел).
var _layers: Array[MultiMeshInstance3D] = []
## Вес выбора каждого слоя (как в CAR_MODELS).
var _weights := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _seen_grid: CityGrid = null
var _seen_roads_version: int = -1


func _ready() -> void:
	_rng.randomize()
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
	var step: float = SPEED * SimClock.speed * delta
	var counts := PackedInt32Array()
	counts.resize(_layers.size())
	counts.fill(0)
	for car: Car in _cars:
		if step > 0.0:
			_advance(car, grid, step)
		var layer: MultiMesh = _layers[car.model].multimesh
		var index: int = counts[car.model]
		counts[car.model] += 1
		layer.set_instance_transform(index, _car_transform(car, grid))
		if layer.use_colors:
			layer.set_instance_color(index, car.color)
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


## Сколько машинок нужно: по числу работников, не больше MAX_CARS; без путей — ни одной.
func _target_count() -> int:
	var traffic: Traffic = GameState.traffic
	if traffic.sample_paths.is_empty():
		return 0
	return mini(MAX_CARS, roundi(traffic.total_workers / WORKERS_PER_CAR))


func _sync_car_count() -> void:
	var target: int = _target_count()
	while _cars.size() > target:
		_cars.pop_back()
	while _cars.size() < target:
		var car := Car.new()
		car.color = CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)]
		car.model = _rng.rand_weighted(_weights)
		if not _assign_path(car):
			break
		# Новые машинки — в случайном месте пути и в случайную сторону, чтобы не ехали стаей.
		car.progress = _rng.randf() * car.path.size()
		car.forward = _rng.randf() < 0.5
		_cars.append(car)


## Новый путь из выборки (не короче двух клеток). false — подходящих путей нет.
func _assign_path(car: Car) -> bool:
	var paths: Array[PackedInt32Array] = GameState.traffic.sample_paths
	var grid: CityGrid = GameState.grid
	for attempt: int in 8:
		var path: PackedInt32Array = paths[_rng.randi_range(0, paths.size() - 1)]
		# Выборка может отстать от дорог (пересчёт трафика ещё не случился) — сломанный путь не берём.
		if path.size() >= 2 and _path_is_intact(path, grid):
			car.path = path
			car.progress = 0.0
			car.forward = true
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


func _advance(car: Car, grid: CityGrid, step: float) -> void:
	var index: int = _path_index(car, mini(int(car.progress), car.path.size() - 1))
	var ratio: float = GameState.traffic.load_ratio(grid, index)
	car.progress += step / (1.0 + JAM_SLOWDOWN * minf(ratio, 2.0))
	if car.progress < car.path.size():
		return
	if car.forward:
		# Доехали до работы — разворот на встречную полосу и обратно.
		car.forward = false
		car.progress = 0.0
	elif not _assign_path(car):
		car.progress = 0.0
		car.forward = true


## Индекс клетки пути с учётом направления (обратно — путь задом наперёд).
func _path_index(car: Car, k: int) -> int:
	return car.path[k] if car.forward else car.path[car.path.size() - 1 - k]


func _car_transform(car: Car, grid: CityGrid) -> Transform3D:
	var count: int = car.path.size()
	var k: int = mini(int(car.progress), count - 1)
	var t: float = clampf(car.progress - k, 0.0, 1.0)
	var cell: Vector2i = _cell_of(_path_index(car, k), grid)
	var center: Vector3 = grid.grid_to_world(cell) + Vector3.UP * ROAD_TOP
	var half: float = CityGrid.CELL_SIZE * 0.5
	var has_prev: bool = k > 0
	var has_next: bool = k < count - 1
	var prev_cell: Vector2i = _cell_of(_path_index(car, k - 1), grid) if has_prev else cell
	var next_cell: Vector2i = _cell_of(_path_index(car, k + 1), grid) if has_next else cell
	var dir_in: Vector3 = _dir(cell - prev_cell) if has_prev else _dir(next_cell - cell)
	var dir_out: Vector3 = _dir(next_cell - cell) if has_next else dir_in
	var right_in := Vector3(-dir_in.z, 0.0, dir_in.x)
	var right_out := Vector3(-dir_out.z, 0.0, dir_out.x)
	# Середина входного и выходного рёбер клетки (на концах пути — центр), на правой полосе.
	var p0: Vector3 = (center - dir_in * half if has_prev else center) + right_in * LANE_OFFSET
	var p2: Vector3 = (center + dir_out * half if has_next else center) + right_out * LANE_OFFSET
	var p1: Vector3 = center + (right_in + right_out) * 0.5 * LANE_OFFSET
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
