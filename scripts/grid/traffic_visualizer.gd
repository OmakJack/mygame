class_name TrafficVisualizer
extends MultiMeshInstance3D
## Машинки на дорогах — только визуал: на симуляцию не влияют и не сохраняются.
## Каждая едет по пути из выборки GameState.traffic.sample_paths (из дома на работу или обратно),
## у цели «паркуется» и берёт новую поездку. С этапа C2 путь клеток превращается в маршрут по графу
## дорог (RoadRoute): по кривым отрезков на своей полосе справа, в узлах — дугой поворота.
## Правила (умный трафик): держат дистанцию до машины впереди в своей полосе (и на въезде в следующий
## отрезок), плавно тормозят и разгоняются; стоят на красный у стоп-линии подхода (TrafficLights);
## на проспектах и шоссе — две полосы в каждую сторону (RoadGeometry.lane_offsets).
## Пешеходы и велосипедисты (PeopleVisualizer) — тот же код без правил: переопределяют _paths,
## _target_count, _speed, _offset, _slowdown, _obeys_rules, _load_layers, _dress и _bob.

const MAX_CARS: int = 300
## Сколько работников «изображает» одна машинка (≈ сколько людей в машине).
const WORKERS_PER_CAR: float = 1.3
## Скорость, м в секунду на ×1 (клетка — 2 м).
const SPEED: float = 4.0
## На загруженной клетке машинка медленнее в (1 + JAM_SLOWDOWN · загрузка) раз (загрузка до 2).
const JAM_SLOWDOWN: float = 0.7
## Дистанция до машины впереди (между центрами), м: машина ~0.7 м.
const MIN_GAP: float = 1.0
## Насколько вперёд смотреть на машины и светофоры следующих отрезков, м.
const LOOK_AHEAD: float = 4.0
## Разгон и торможение: доля полной скорости в секунду.
const ACCEL: float = 2.5
## Маршрут короче — поездку не берём, м.
const MIN_ROUTE: float = 0.5
## Стоит на месте дольше (затор по кругу, «пробка намертво») — уезжает с карты и берёт новую поездку, с.
const STUCK_TIME: float = 30.0
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
## Верх асфальта (RoadGeometry.ASPHALT_Y).
const ROAD_TOP: float = 0.02
## Заглушка, если моделей нет: коробочка своего цвета.
const CAR_SIZE := Vector3(0.45, 0.3, 0.8)
const CAR_COLORS: Array[Color] = [
	Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.85), Color(0.95, 0.85, 0.3),
	Color(0.9, 0.9, 0.9), Color(0.25, 0.25, 0.28), Color(0.3, 0.7, 0.4),
]
## Больше маршрутов в запасе не держим (выборки путей — до сотни с небольшим).
const MAX_ROUTES: int = 2000


## Одна машинка: путь (индексы клеток), маршрут по графу и сколько по нему проехано.
class Car extends RefCounted:
	var path := PackedInt32Array()
	## true — от дома к работе, false — обратно.
	var forward: bool = true
	var route: RoadRoute = null
	## Пройдено по маршруту, м.
	var distance: float = 0.0
	## Номер слоя (модели) в _layers.
	var model: int = 0
	var color := Color.WHITE
	## Свой цвет одежды или рамы (INSTANCE_CUSTOM, BuildingPalette) — у пешеходов и велосипедистов.
	var custom := Color(0, 0, 0, 0)
	## Полоса на дорогах с двумя полосами (0 — ближе к оси, 1 — к тротуару).
	var lane: int = 0
	## Текущая скорость, доля полной (разгон и торможение — ACCEL).
	var speed: float = 1.0
	## Сколько стоит на месте, с игрового времени.
	var stuck: float = 0.0


var _cars: Array[Car] = []
## Слои MultiMesh: по одному на модель машины; без моделей — один слой-заглушка (сам узел).
var _layers: Array[MultiMeshInstance3D] = []
## Вес выбора каждого слоя (как в CAR_MODELS).
var _weights := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _seen_grid: CityGrid = null
var _seen_roads_version: int = -1
var _seen_graph_version: int = -1
## Маршруты по путям: hash([путь, туда или обратно, полоса]) → RoadRoute; новая версия графа — заново.
var _routes: Dictionary[int, RoadRoute] = {}
## Кто где едет в этом кадре: ключ очереди участка (RoadRoute.Leg.key) → координаты вдоль отрезка.
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
	var grid: CityGrid = GameState.grid
	grid.roads.sync(grid)
	_check_roads()
	_sync_car_count()
	var step: float = _speed() * SimClock.speed * delta
	var counts := PackedInt32Array()
	counts.resize(_layers.size())
	counts.fill(0)
	if step > 0.0 and _obeys_rules():
		_fill_occupancy()
	for car: Car in _cars:
		if step > 0.0:
			_advance(car, grid, step, delta * SimClock.speed)
		var layer: MultiMesh = _layers[car.model].multimesh
		var index: int = counts[car.model]
		counts[car.model] += 1
		layer.set_instance_transform(index, _car_transform(car))
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
	return _car_transform(_cars[i]).origin


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


## Скорость, м в секунду на ×1.
func _speed() -> float:
	return SPEED


## Сдвиг вправо от оси на дороге типа type, м: машины — середина своей полосы.
func _offset(type: int, lane: int) -> float:
	var lanes: PackedFloat32Array = RoadGeometry.lane_offsets(type)
	return lanes[mini(lane, lanes.size() - 1)]


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
			car.distance = _rng.randf() * car.route.length()
			car.speed = 1.0
		_cars.append(car)


## Новый путь из выборки и маршрут по нему. false — подходящих путей нет.
func _assign_path(car: Car) -> bool:
	var paths: Array[PackedInt32Array] = _paths()
	var grid: CityGrid = GameState.grid
	# Пустая выборка (дорогу только что снесли, трафик ещё не пересчитан) — путей нет.
	if paths.is_empty():
		return false
	for attempt: int in 8:
		var path: PackedInt32Array = paths[_rng.randi_range(0, paths.size() - 1)]
		# Выборка может отстать от дорог (пересчёт трафика ещё не случился) — сломанный путь не берём.
		if path.size() < 2 or not _path_is_intact(path, grid):
			continue
		car.path = path
		# Из дома на работу или с работы домой.
		car.forward = _rng.randf() < 0.5
		car.lane = _rng.randi_range(0, 1)
		car.route = _route_for(car, grid)
		if car.route.length() < MIN_ROUTE:
			continue
		car.distance = 0.0
		car.speed = 0.0
		return true
	return false


## Маршрут по пути машинки (из запаса или новый).
func _route_for(car: Car, grid: CityGrid) -> RoadRoute:
	var lane: int = car.lane if _obeys_rules() else 0
	var key: int = hash([car.path, car.forward, lane])
	var route: RoadRoute = _routes.get(key)
	if route != null:
		return route
	if _routes.size() >= MAX_ROUTES:
		_routes.clear()
	var cells: Array[Vector2i] = []
	for k: int in car.path.size():
		cells.append(_cell_of(_path_index(car, k), grid))
	var offsets: Dictionary = {}
	for type: int in [RoadTypes.Type.STREET, RoadTypes.Type.AVENUE, RoadTypes.Type.HIGHWAY]:
		offsets[type] = _offset(type, lane)
	route = RoadRoute.build(grid.roads, grid, cells, offsets, lane)
	_routes[key] = route
	return route


## Дороги изменились — маршруты строятся заново (машинка остаётся, где была), машинки со сломанным
## путём сразу берут новый; новый город — все заново.
func _check_roads() -> void:
	var grid: CityGrid = GameState.grid
	if grid != _seen_grid:
		_cars.clear()
		_routes.clear()
	elif grid.roads_version != _seen_roads_version or grid.roads.version != _seen_graph_version:
		_routes.clear()
		for car: Car in _cars:
			var pos: Vector2 = car.route.point_at(car.distance) if car.route != null else Vector2.ZERO
			if _path_is_intact(car.path, grid):
				car.route = _route_for(car, grid)
				car.distance = car.route.nearest(pos)
			elif not _assign_path(car):
				car.path = PackedInt32Array()
		_cars = _cars.filter(func(car: Car) -> bool: return car.path.size() >= 2 and car.route != null)
	_seen_grid = grid
	_seen_roads_version = grid.roads_version
	_seen_graph_version = grid.roads.version


static func _path_is_intact(path: PackedInt32Array, grid: CityGrid) -> bool:
	for index: int in path:
		if index >= grid.tile_type.size() or grid.tile_type[index] != CityGrid.Tile.ROAD:
			return false
	return true


func _advance(car: Car, grid: CityGrid, step: float, dt: float) -> void:
	var ratio: float = GameState.traffic.load_ratio(grid, _index_at(car, grid))
	var target: float = 1.0 / _slowdown(ratio)
	var allowed: float = INF
	if _obeys_rules():
		allowed = _free_ahead(car, grid)
	# Перед помехой — тормозим, иначе плавно разгоняемся до скорости улицы.
	car.speed = move_toward(car.speed, target if allowed > step else 0.0, ACCEL * dt)
	var moved: float = clampf(step * car.speed, 0.0, maxf(0.0, allowed))
	car.distance += moved
	car.stuck = car.stuck + dt if moved < 0.001 else 0.0
	if car.distance < car.route.length() and car.stuck < STUCK_TIME:
		return
	car.stuck = 0.0
	# Доехали (или застряли): машина «паркуется», вместо неё — новая поездка.
	if not _assign_path(car):
		car.distance = 0.0


## Клетка под машинкой (индекс в слоях сетки) — для загрузки дороги.
static func _index_at(car: Car, grid: CityGrid) -> int:
	var cell: Vector2i = RoadGraph.cell_of(car.route.point_at(car.distance))
	return grid.index_of(grid.clamp_to_bounds(cell))


## Сколько можно проехать, м: до машины впереди в своей полосе (с дистанцией) — на своём отрезке
## и на въезде в следующие (в пределах LOOK_AHEAD) — и до стоп-линии подхода на красный.
func _free_ahead(car: Car, grid: CityGrid) -> float:
	var route: RoadRoute = car.route
	var d: float = car.distance
	var current: int = route.leg_at(d)
	var free: float = INF
	for k: int in range(current, route.legs.size()):
		var leg: RoadRoute.Leg = route.legs[k]
		var ahead: float = leg.start - d
		if k > current and ahead > LOOK_AHEAD:
			break
		if leg.key != -1 and _occupancy.has(leg.key):
			var mine: float = leg.frame + d - leg.start
			for other: float in _occupancy[leg.key]:
				if k == current:
					if other > mine + 0.001:
						free = minf(free, other - mine - MIN_GAP)
				elif other >= leg.frame - 0.001:
					free = minf(free, ahead + other - leg.frame - MIN_GAP)
		if leg.stop >= 0.0 and d <= leg.stop + 0.001 \
				and not TrafficLights.approach_green(grid.roads, leg.light_node, leg.light_segment):
			free = minf(free, leg.stop - d)
	return free


func _fill_occupancy() -> void:
	_occupancy.clear()
	for car: Car in _cars:
		if car.route == null or car.route.legs.is_empty():
			continue
		var leg: RoadRoute.Leg = car.route.legs[car.route.leg_at(car.distance)]
		if leg.key == -1:
			continue
		if not _occupancy.has(leg.key):
			_occupancy[leg.key] = PackedFloat32Array()
		_occupancy[leg.key].append(leg.frame + car.distance - leg.start)


## Индекс клетки пути с учётом направления (обратно — путь задом наперёд).
func _path_index(car: Car, k: int) -> int:
	return car.path[k] if car.forward else car.path[car.path.size() - 1 - k]


func _car_transform(car: Car) -> Transform3D:
	var point: Vector2 = car.route.point_at(car.distance)
	var dir: Vector2 = car.route.dir_at(car.distance)
	var origin := Vector3(point.x, ROAD_TOP + _bob(car), point.y)
	if dir.length_squared() < 1e-6:
		return Transform3D(Basis.IDENTITY, origin)
	return Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP), origin)


@warning_ignore("integer_division")
static func _cell_of(index: int, grid: CityGrid) -> Vector2i:
	return Vector2i(index % grid.size, index / grid.size)
