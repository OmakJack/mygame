extends Node3D
## Трасса за картой (как в Cities: Skylines): дорога от въезда через лес до края поля,
## знак трассы у въезда и поток машин в обе стороны. Машин тем больше, чем больше город.
## Только вид: сами поездки приезжих считает Traffic (дом-«въезд»), их машинки — TrafficVisualizer.

## Сколько клеток трассы рисовать за краем (до конца поля вокруг карты).
const OUTSIDE_CELLS: int = 30
## Машин в каждую сторону: пустой город — немного, дальше +1 на POPULATION_PER_CAR жителей.
const MIN_CARS: int = 3
const MAX_CARS: int = 14
const POPULATION_PER_CAR: int = 40
## Скорость машин, м/с на ×1, и сдвиг от оси дороги к своей полосе.
const SPEED: float = 3.0
const LANE_OFFSET: float = 0.3
const CAR_MODELS: Array[String] = [
	"res://assets/models/kenney/cars/sedan.glb", "res://assets/models/kenney/cars/suv.glb",
	"res://assets/models/kenney/cars/van.glb", "res://assets/models/kenney/cars/truck.glb",
	"res://assets/models/kenney/cars/delivery.glb", "res://assets/models/kenney/cars/taxi.glb",
]
const SIGN_MODEL: String = "res://assets/models/kenney/roads/sign-highway.glb"

var _road := MultiMeshInstance3D.new()
var _sign := MeshInstance3D.new()
var _cars: Array[MultiMeshInstance3D] = []
## Положение каждой машины вдоль трассы (0..длина, м), её полоса (+1 — в город, −1 — из города) и модель.
var _progress: Array[float] = []
var _lane: Array[int] = []
var _model: Array[int] = []
var _start := Vector3.ZERO
var _dir := Vector3.ZERO
var _length: float = 0.0


func _ready() -> void:
	_road.multimesh = MultiMesh.new()
	_road.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_road.multimesh.mesh = RoadMeshes.highway_straight_mesh()
	_road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_road)
	if ResourceLoader.exists(SIGN_MODEL):
		_sign.mesh = ModelLoader.fitted(load(SIGN_MODEL), 2.0, 0)
	add_child(_sign)
	for path: String in CAR_MODELS:
		if not ResourceLoader.exists(path):
			continue
		var layer := MultiMeshInstance3D.new()
		layer.multimesh = MultiMesh.new()
		layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		layer.multimesh.mesh = ModelLoader.fitted(load(path), TrafficVisualizer.CAR_MODEL_SCALE, TrafficVisualizer.CAR_MODEL_TURNS)
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(layer)
		_cars.append(layer)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	var grid: CityGrid = GameState.grid
	visible = grid.has_entry()
	if not visible:
		return
	var cells: Array[Vector2i] = grid.outside_highway(OUTSIDE_CELLS)
	_road.multimesh.instance_count = cells.size()
	# Прямой кусок идёт с N на S; для трассы E–W — поворот на 90°.
	var along_x: bool = grid.entry_dir == 1 or grid.entry_dir == 3
	var basis := Basis(Vector3.UP, PI * 0.5) if along_x else Basis.IDENTITY
	for i: int in cells.size():
		_road.multimesh.set_instance_transform(i, Transform3D(basis, grid.grid_to_world(cells[i])))
	var outward := Vector2(CityGrid.NEIGHBORS[grid.entry_dir])
	_dir = Vector3(-outward.x, 0.0, -outward.y)
	_start = grid.grid_to_world(grid.entry) - _dir * (OUTSIDE_CELLS + 0.5) * CityGrid.CELL_SIZE
	_length = (OUTSIDE_CELLS + 1) * CityGrid.CELL_SIZE
	# Знак — справа от въезда, лицом к едущим в город.
	var side := Vector3(-_dir.z, 0.0, _dir.x)
	_sign.transform = Transform3D(Basis.looking_at(-_dir, Vector3.UP), grid.grid_to_world(grid.entry)
			- _dir * CityGrid.CELL_SIZE * 1.5 + side * CityGrid.CELL_SIZE * 0.7)
	_spawn_cars()


func _spawn_cars() -> void:
	_progress.clear()
	_lane.clear()
	_model.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(GameState.grid.entry)
	for lane: int in [1, -1]:
		for i: int in MAX_CARS:
			_progress.append((i + rng.randf_range(0.0, 0.6)) * _length / MAX_CARS)
			_lane.append(lane)
			_model.append(rng.randi_range(0, maxi(0, _cars.size() - 1)))


func _process(delta: float) -> void:
	if not visible or _cars.is_empty():
		return
	var shown: int = clampi(MIN_CARS + GameState.population / POPULATION_PER_CAR, MIN_CARS, MAX_CARS)
	var step: float = SPEED * SimClock.speed * delta
	var per_layer: Array[Array] = []
	for layer: MultiMeshInstance3D in _cars:
		per_layer.append([])
	for i: int in _progress.size():
		_progress[i] = fposmod(_progress[i] + step, _length)
		# В каждой полосе видны первые shown машин — поток густеет с ростом города.
		if i % MAX_CARS >= shown:
			continue
		var t: float = _progress[i] if _lane[i] > 0 else _length - _progress[i]
		var heading: Vector3 = _dir * _lane[i]
		var side := Vector3(-heading.z, 0.0, heading.x)
		var pos: Vector3 = _start + _dir * t + side * LANE_OFFSET + Vector3.UP * TrafficVisualizer.ROAD_TOP
		per_layer[_model[i]].append(Transform3D(Basis.looking_at(heading, Vector3.UP), pos))
	for k: int in _cars.size():
		var list: Array = per_layer[k]
		_cars[k].multimesh.instance_count = list.size()
		for j: int in list.size():
			_cars[k].multimesh.set_instance_transform(j, list[j])


func car_count() -> int:
	var total: int = 0
	for layer: MultiMeshInstance3D in _cars:
		total += layer.multimesh.instance_count
	return total
