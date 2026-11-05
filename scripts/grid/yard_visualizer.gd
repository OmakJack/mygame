class_name YardVisualizer
extends Node3D
## Дворы за домами (застройщик по месту, Р2): клетки участка позади дома. Только визуал.
## Жильё — газон (тон земли рисует ZoneVisualizer), низкий светлый штакетник по краю двора, деревья и клумбы;
## многоэтажки — двор-сквер с деревьями без забора; магазины и офисы — парковка с разметкой
## и машинами; промзона — площадка с контейнерами. Модели — Kenney (suburban, industrial, cars).
## Расстановка детерминированная по клетке; пересобирается, когда меняются участки или дома
## (lots_version, buildings_version: смена плотности меняет вид двора).

const TREE := "res://assets/models/kenney/suburban/tree-small.glb"
const PLANTER := "res://assets/models/kenney/suburban/planter.glb"
const CONTAINERS: Array[String] = [
	"res://assets/models/kenney/industrial/shipping-container-a.glb",
	"res://assets/models/kenney/industrial/shipping-container-b.glb",
	"res://assets/models/kenney/industrial/shipping-container-c.glb",
]
const CARS: Array[String] = [
	"res://assets/models/kenney/cars/sedan.glb",
	"res://assets/models/kenney/cars/suv.glb",
	"res://assets/models/kenney/cars/hatchback-sports.glb",
	"res://assets/models/kenney/cars/van.glb",
]
## Масштабы моделей — как у домов Kenney (≈1.5), деревьев (TreeVisualizer) и машин (TrafficVisualizer).
const TREE_SCALE_MIN: float = 1.7
const TREE_SCALE_MAX: float = 2.5
const PLANTER_SCALE: float = 1.5
const CONTAINER_SCALE: float = 1.4
const CAR_SCALE: float = 0.28
## Штакетник: брус на весь край клетки (модель Kenney в масштабе домов — толстая оранжевая сетка).
const FENCE_HEIGHT: float = 0.22
const FENCE_THICKNESS: float = 0.035
const FENCE_COLOR := Color(0.95, 0.93, 0.86)
## Забор чуть внутрь двора от края клетки, метры.
const FENCE_INSET: float = 0.05
## Парковка: мест в клетке поперёк улицы, длина линии разметки, доля занятых мест.
const STALLS_PER_CELL: int = 3
const STALL_LINE_LENGTH: float = 1.1
const STALL_LINE_WIDTH: float = 0.05
const CAR_SHARE: float = 0.3
const STRIPE_HEIGHT: float = 0.012
## Доли: дерево и клумба во дворе дома, дерево во дворе многоэтажки, контейнер на площадке завода.
const HOME_TREE_SHARE: float = 0.55
const HOME_PLANTER_SHARE: float = 0.25
const COURT_TREE_SHARE: float = 0.8
const CONTAINER_SHARE: float = 0.7

var _fence: MultiMeshInstance3D
var _trees: MultiMeshInstance3D
var _planters: MultiMeshInstance3D
var _stripes: MultiMeshInstance3D
var _containers: Array[MultiMeshInstance3D] = []
var _cars: Array[MultiMeshInstance3D] = []
var _lots_version: int = -1
var _buildings_version: int = -1


func _ready() -> void:
	var rail := BoxMesh.new()
	rail.size = Vector3(CityGrid.CELL_SIZE, FENCE_HEIGHT, FENCE_THICKNESS)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = FENCE_COLOR
	wood.roughness = 0.9
	rail.material = wood
	_fence = _make_layer(rail)
	_trees = _make_layer(ModelLoader.fitted(load(TREE), 1.0, 0))
	_planters = _make_layer(ModelLoader.fitted(load(PLANTER), PLANTER_SCALE, 0))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(STALL_LINE_WIDTH, 0.002, STALL_LINE_LENGTH)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.92, 0.92, 0.88)
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stripe.material = paint
	_stripes = _make_layer(stripe)
	_stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for path: String in CONTAINERS:
		_containers.append(_make_layer(ModelLoader.fitted(load(path), CONTAINER_SCALE, 0)))
	for path: String in CARS:
		_cars.append(_make_layer(ModelLoader.fitted(load(path), CAR_SCALE, 0)))
	Events.cells_changed.connect(func(_cells: Array[Vector2i]) -> void:
		var grid: CityGrid = GameState.grid
		if grid.lots_version != _lots_version or grid.buildings_version != _buildings_version:
			_rebuild())
	Events.grid_reset.connect(_rebuild)
	_rebuild()


## Сколько предметов во дворах: {забор, деревья, клумбы, разметка, контейнеры, машины} (для проверок).
func counts() -> Dictionary:
	var containers: int = 0
	for layer: MultiMeshInstance3D in _containers:
		containers += layer.multimesh.instance_count
	var cars: int = 0
	for layer: MultiMeshInstance3D in _cars:
		cars += layer.multimesh.instance_count
	return {
		"fence": _fence.multimesh.instance_count,
		"trees": _trees.multimesh.instance_count,
		"planters": _planters.multimesh.instance_count,
		"stripes": _stripes.multimesh.instance_count,
		"containers": containers,
		"cars": cars,
	}


func _rebuild() -> void:
	var grid: CityGrid = GameState.grid
	_lots_version = grid.lots_version
	_buildings_version = grid.buildings_version
	var fence: Array[Transform3D] = []
	var trees: Array[Transform3D] = []
	var planters: Array[Transform3D] = []
	var stripes: Array[Transform3D] = []
	var containers: Array[Array] = []
	for i: int in _containers.size():
		containers.append([])
	var cars: Array[Array] = []
	for i: int in _cars.size():
		cars.append([])
	# Общий край двух дворов — один забор.
	var fenced: Dictionary[Vector3i, bool] = {}
	for lot: CityGrid.Lot in grid.lots.values():
		var building: BuildingInstance = grid.building_on_lot(lot)
		if building == null:
			continue
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		var along := Vector3(CityGrid.NEIGHBORS[(lot.dir + 1) % 4].x, 0.0, CityGrid.NEIGHBORS[(lot.dir + 1) % 4].y)
		var facing: float = -lot.dir * PI * 0.5
		for cell: Vector2i in lot.cells():
			if not grid.is_yard(cell):
				continue
			var center: Vector3 = grid.grid_to_world(cell)
			var roll: float = _roll(cell, 0)
			match data.zone:
				CityGrid.Zone.RESIDENTIAL:
					_fence_cell(grid, lot, cell, fence, fenced)
					if roll < HOME_TREE_SHARE:
						trees.append(_tree_at(cell, center))
					elif roll < HOME_TREE_SHARE + HOME_PLANTER_SHARE:
						planters.append(Transform3D(Basis(Vector3.UP, facing), center + _offset(cell, 0.4)))
				CityGrid.Zone.RESIDENTIAL_HIGH:
					if roll < COURT_TREE_SHARE:
						trees.append(_tree_at(cell, center))
				CityGrid.Zone.INDUSTRIAL:
					if roll < CONTAINER_SHARE:
						var turn: float = facing + (PI * 0.5 if _roll(cell, 1) < 0.5 else 0.0)
						containers[int(_roll(cell, 2) * containers.size())].append(
								Transform3D(Basis(Vector3.UP, turn), center + _offset(cell, 0.25)))
				_:
					# Магазины и офисы: парковка — места поперёк улицы, машины носом к дому.
					var stall: float = CityGrid.CELL_SIZE / STALLS_PER_CELL
					for k: int in STALLS_PER_CELL + 1:
						var pos: Vector3 = center + along * (stall * k - CityGrid.CELL_SIZE * 0.5)
						stripes.append(Transform3D(Basis(Vector3.UP, facing), pos + Vector3.UP * STRIPE_HEIGHT))
					for k: int in STALLS_PER_CELL:
						if _roll(cell, 3 + k) < CAR_SHARE:
							var pos: Vector3 = center + along * (stall * (k + 0.5) - CityGrid.CELL_SIZE * 0.5)
							var model: int = int(_roll(cell, 10 + k) * cars.size())
							cars[model].append(Transform3D(Basis(Vector3.UP, facing), pos))
	_write(_fence, fence)
	_write(_trees, trees)
	_write(_planters, planters)
	_write(_stripes, stripes)
	for i: int in _containers.size():
		_write(_containers[i], containers[i])
	for i: int in _cars.size():
		_write(_cars[i], cars[i])


## Забор по краям клетки двора, за которыми не этот участок (соседний двор, пустая земля, дорога).
## Край к своему дому забора не получает.
func _fence_cell(grid: CityGrid, lot: CityGrid.Lot, cell: Vector2i, fence: Array[Transform3D],
		fenced: Dictionary[Vector3i, bool]) -> void:
	for dir: int in 4:
		var other: Vector2i = cell + CityGrid.NEIGHBORS[dir]
		if grid.get_lot(other) == lot:
			continue
		# Ключ края: клетка с меньшими координатами и ось (0 — край по X, 1 — по Y).
		var key := Vector3i(maxi(cell.x, other.x), maxi(cell.y, other.y), dir % 2)
		if fenced.has(key):
			continue
		fenced[key] = true
		var normal := Vector3(CityGrid.NEIGHBORS[dir].x, 0.0, CityGrid.NEIGHBORS[dir].y)
		var edge: Vector3 = grid.grid_to_world(cell) + normal * (CityGrid.CELL_SIZE * 0.5 - FENCE_INSET)
		# Брус вытянут по X: края N/S — без поворота, E/W — на четверть оборота.
		var basis := Basis(Vector3.UP, PI * 0.5 if dir % 2 == 1 else 0.0)
		fence.append(Transform3D(basis, edge + Vector3.UP * FENCE_HEIGHT * 0.5))


func _tree_at(cell: Vector2i, center: Vector3) -> Transform3D:
	var scale: float = lerpf(TREE_SCALE_MIN, TREE_SCALE_MAX, _roll(cell, 4))
	var basis := Basis(Vector3.UP, _roll(cell, 5) * TAU).scaled(Vector3.ONE * scale)
	return Transform3D(basis, center + _offset(cell, 0.45))


## Случайный сдвиг от центра клетки до spread метров (детерминированный).
func _offset(cell: Vector2i, spread: float) -> Vector3:
	return Vector3((_roll(cell, 6) - 0.5) * 2.0 * spread, 0.0, (_roll(cell, 7) - 0.5) * 2.0 * spread)


## Детерминированное «случайное» число 0..1 по клетке и номеру броска.
static func _roll(cell: Vector2i, salt: int) -> float:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(posmod(h ^ (h >> 16), 10007)) / 10007.0


func _make_layer(mesh: Mesh) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.mesh = mesh
	add_child(layer)
	return layer


func _write(layer: MultiMeshInstance3D, transforms: Array) -> void:
	layer.multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		layer.multimesh.set_instance_transform(i, transforms[i])
