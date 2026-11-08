class_name YardVisualizer
extends Node3D
## Дворы за домами (застройщик по месту, Р2): клетки участка позади дома. Только визуал.
## Жильё — газон (тон земли рисует ZoneVisualizer), низкий светлый штакетник по краю двора, деревья и клумбы;
## многоэтажки — двор-сквер с деревьями без забора; магазины и офисы — парковка с разметкой
## и машинами; промзона — двор одного вида на участок за бетонным забором (Works: склад — ряды контейнеров
## у задней границы, погрузка — бетон с грузовиками задом к цеху, баки, зелёный двор с деревьями; до 2026-11-08
## — контейнеры вразнобой на 70 % клеток, и промзона превращалась в контейнерную стоянку).
## Модели — Kenney (suburban, industrial, cars).
## Расстановка детерминированная по клетке; пересобирается, когда меняются участки или дома
## (lots_version, buildings_version: смена плотности меняет вид двора).

const TREE := "res://assets/models/kenney/suburban/tree-small.glb"
const PLANTER := "res://assets/models/kenney/suburban/planter.glb"
const CONTAINERS: Array[String] = [
	"res://assets/models/kenney/industrial/shipping-container-a.glb",
	"res://assets/models/kenney/industrial/shipping-container-b.glb",
	"res://assets/models/kenney/industrial/shipping-container-c.glb",
]
const TRUCKS: Array[String] = [
	"res://assets/models/kenney/cars/truck.glb",
	"res://assets/models/kenney/cars/truck-flat.glb",
	"res://assets/models/kenney/cars/delivery.glb",
	"res://assets/models/kenney/cars/delivery-flat.glb",
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
const CONTAINER_SCALE: float = 1.1
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
## Двор завода — один вид на участок (works_kind): доли видов по порядку Works.
enum Works { STORAGE, LOADING, TANKS, GREEN }
const WORKS_SHARES: Array[float] = [0.35, 0.3, 0.15, 0.2]
const TRUCK_SCALE: float = 0.4
## Баки — цилиндры из кода, как силосы на зданиях заводов: радиус и высота корпуса, м; пояс и крыша-конус.
const TANK_SIZE := Vector2(0.36, 0.8)
const TANK_LARGE_SIZE := Vector2(0.62, 1.25)
const TANK_COLOR := Color(0.9, 0.91, 0.92)
const TANK_BAND_COLOR := Color(0.88, 0.56, 0.36)
const TANK_ROOF_COLOR := Color(0.74, 0.76, 0.8)
## Склад: в задней клетке — два ряда контейнеров (сдвиг от середины клетки вглубь, м), ярусы.
const STORAGE_ROW_OFFSET: float = 0.38
const STACK_TWO_SHARE: float = 0.45
const STACK_THREE_SHARE: float = 0.12
## Погрузка: доля мест у цеха с грузовиком; склад — доля мест у цеха с грузовиком.
const DOCK_TRUCK_SHARE: float = 0.7
const STORAGE_TRUCK_SHARE: float = 0.25
## Бетонный забор вокруг двора завода.
const WALL_HEIGHT: float = 0.3
const WALL_THICKNESS: float = 0.06
const WALL_COLOR := Color(0.7, 0.69, 0.66)

var _fence: MultiMeshInstance3D
var _trees: MultiMeshInstance3D
var _planters: MultiMeshInstance3D
var _stripes: MultiMeshInstance3D
var _containers: Array[MultiMeshInstance3D] = []
var _cars: Array[MultiMeshInstance3D] = []
var _trucks: Array[MultiMeshInstance3D] = []
var _tanks: MultiMeshInstance3D
var _tanks_large: MultiMeshInstance3D
var _walls: MultiMeshInstance3D
## Высота контейнера (ярусы склада) и поворот, кладущий его длинной стороной вдоль оси X.
var _container_height: float = 0.0
var _container_turn: float = 0.0
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
	var box: AABB = _containers[0].multimesh.mesh.get_aabb()
	_container_height = box.size.y
	_container_turn = PI * 0.5 if box.size.z > box.size.x else 0.0
	for path: String in TRUCKS:
		_trucks.append(_make_layer(ModelLoader.fitted(load(path), TRUCK_SCALE, 0)))
	_tanks = _make_layer(_tank_mesh(TANK_SIZE.x, TANK_SIZE.y))
	_tanks_large = _make_layer(_tank_mesh(TANK_LARGE_SIZE.x, TANK_LARGE_SIZE.y))
	var slab := BoxMesh.new()
	slab.size = Vector3(CityGrid.CELL_SIZE, WALL_HEIGHT, WALL_THICKNESS)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = WALL_COLOR
	concrete.roughness = 0.95
	slab.material = concrete
	_walls = _make_layer(slab)
	for path: String in CARS:
		_cars.append(_make_layer(ModelLoader.fitted(load(path), CAR_SCALE, 0)))
	Events.cells_changed.connect(func(_cells: Array[Vector2i]) -> void:
		var grid: CityGrid = GameState.grid
		if grid.lots_version != _lots_version or grid.buildings_version != _buildings_version:
			_rebuild())
	Events.grid_reset.connect(_rebuild)
	_rebuild()


## Сколько предметов во дворах: {забор, деревья, клумбы, разметка, контейнеры, машины, грузовики, баки,
## бетонный забор} (для проверок).
func counts() -> Dictionary:
	var containers: int = 0
	for layer: MultiMeshInstance3D in _containers:
		containers += layer.multimesh.instance_count
	var cars: int = 0
	for layer: MultiMeshInstance3D in _cars:
		cars += layer.multimesh.instance_count
	var trucks: int = 0
	for layer: MultiMeshInstance3D in _trucks:
		trucks += layer.multimesh.instance_count
	return {
		"trucks": trucks,
		"tanks": _tanks.multimesh.instance_count + _tanks_large.multimesh.instance_count,
		"walls": _walls.multimesh.instance_count,
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
	var works := {"walls": [] as Array[Transform3D], "trucks": [] as Array[Array], "tanks": [] as Array[Transform3D],
			"tanks_large": [] as Array[Transform3D], "containers": containers, "trees": trees, "stripes": stripes}
	for i: int in _trucks.size():
		works.trucks.append([])
	# Общий край двух дворов — один забор.
	var fenced: Dictionary[Vector3i, bool] = {}
	for lot: CityGrid.Lot in grid.lots.values():
		var building: BuildingInstance = grid.building_on_lot(lot)
		if building == null:
			continue
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		if data.zone == CityGrid.Zone.INDUSTRIAL:
			_works_yard(grid, lot, works, fenced)
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
	for i: int in _trucks.size():
		_write(_trucks[i], works.trucks[i])
	_write(_tanks, works.tanks)
	_write(_tanks_large, works.tanks_large)
	_write(_walls, works.walls)


## Вид двора завода: один на участок, по зерну его угла (тот же после загрузки; ZoneVisualizer красит
## землю двора по нему же).
static func works_kind(lot: CityGrid.Lot) -> Works:
	var roll: float = _roll(lot.rect.position, 40)
	var sum: float = 0.0
	for kind: int in WORKS_SHARES.size():
		sum += WORKS_SHARES[kind]
		if roll < sum:
			return kind as Works
	return Works.GREEN


## Двор завода: бетонный забор по краю и вещи рядами по виду двора (works_kind). Ряды считаются от цеха:
## первый ряд двора — у здания, задний — у дальней границы участка.
func _works_yard(grid: CityGrid, lot: CityGrid.Lot, works: Dictionary, fenced: Dictionary[Vector3i, bool]) -> void:
	var street: Vector2i = CityGrid.NEIGHBORS[lot.dir]
	var toward := Vector3(street.x, 0.0, street.y)
	var side: Vector2i = CityGrid.NEIGHBORS[(lot.dir + 1) % 4]
	var along := Vector3(side.x, 0.0, side.y)
	# Поворот, кладущий ось X модели вдоль улицы, и «носом к дому», как у машин на парковке.
	var along_turn: float = atan2(-along.z, along.x)
	var facing: float = -lot.dir * PI * 0.5
	var yard: Array[Vector2i] = []
	var near: int = 1 << 30
	var far: int = -(1 << 30)
	for cell: Vector2i in lot.cells():
		if not grid.is_yard(cell):
			continue
		yard.append(cell)
		var depth: int = -(cell.x * street.x + cell.y * street.y)
		near = mini(near, depth)
		far = maxi(far, depth)
	if yard.is_empty():
		return
	var kind: Works = works_kind(lot)
	var containers: Array[Array] = works.containers
	for cell: Vector2i in yard:
		_fence_cell(grid, lot, cell, works.walls, fenced, WALL_HEIGHT)
		var center: Vector3 = grid.grid_to_world(cell)
		var depth: int = -(cell.x * street.x + cell.y * street.y)
		var lateral: int = cell.x * side.x + cell.y * side.y
		var back: bool = depth == far
		var front: bool = depth == near and far > near
		match kind:
			Works.STORAGE:
				# Задний ряд — два ряда контейнеров, предпоследний — один ряд через раз; у цеха — грузовик.
				var lines: Array[float] = []
				if back:
					lines = [-STORAGE_ROW_OFFSET, STORAGE_ROW_OFFSET]
				elif not front and _roll(cell, 21) < 0.5:
					lines = [0.0]
				for k: int in lines.size():
					var floors: int = 1
					var stack: float = _roll(cell, 22 + k)
					if stack < STACK_THREE_SHARE:
						floors = 3
					elif stack < STACK_THREE_SHARE + STACK_TWO_SHARE:
						floors = 2
					for level: int in floors:
						var model: int = int(_roll(cell, 30 + k * 4 + level) * containers.size())
						var pos: Vector3 = center - toward * lines[k] + Vector3.UP * (_container_height * level)
						containers[model].append(Transform3D(Basis(Vector3.UP, along_turn + _container_turn), pos))
				if front and _roll(cell, 24) < STORAGE_TRUCK_SHARE:
					_add_truck(works.trucks, cell, center + toward * 0.15, facing + PI)
			Works.LOADING:
				# У цеха — места погрузки с разметкой, грузовики задом к воротам; сзади — пустой бетон.
				if depth == near:
					for edge: float in [-0.5, 0.5]:
						var line: Vector3 = center + along * (CityGrid.CELL_SIZE * edge) + Vector3.UP * STRIPE_HEIGHT
						works.stripes.append(Transform3D(Basis(Vector3.UP, facing), line))
					if _roll(cell, 25) < DOCK_TRUCK_SHARE:
						_add_truck(works.trucks, cell, center + toward * 0.15, facing + PI)
				elif back and _roll(cell, 26) < 0.3:
					var model: int = int(_roll(cell, 27) * containers.size())
					containers[model].append(Transform3D(Basis(Vector3.UP, along_turn + _container_turn), center))
			Works.TANKS:
				# Баки в ряд у задней границы: большой через клетку, между ними — малый.
				if back:
					if posmod(lateral, 2) == 0:
						works.tanks_large.append(Transform3D(Basis.IDENTITY, center))
					elif _roll(cell, 28) < 0.6:
						works.tanks.append(Transform3D(Basis.IDENTITY, center))
				elif not front and _roll(cell, 29) < 0.3:
					works.tanks.append(Transform3D(Basis.IDENTITY, center))
			Works.GREEN:
				# Газон и ряд деревьев у задней границы (зелёная полоса между цехами и соседями).
				if back or _roll(cell, 3) < 0.2:
					var scale: float = lerpf(TREE_SCALE_MIN, TREE_SCALE_MAX, _roll(cell, 4))
					var basis := Basis(Vector3.UP, _roll(cell, 5) * TAU).scaled(Vector3.ONE * scale)
					works.trees.append(Transform3D(basis, center + _offset(cell, 0.2)))


## Бак: белый цилиндр на земле, оранжевый пояс на 2/3 высоты, пологая крыша-конус. Три поверхности.
static func _tank_mesh(radius: float, height: float) -> ArrayMesh:
	var body := CylinderMesh.new()
	body.top_radius = radius
	body.bottom_radius = radius
	body.height = height
	body.radial_segments = 20
	var band := CylinderMesh.new()
	band.top_radius = radius * 1.03
	band.bottom_radius = radius * 1.03
	band.height = height * 0.08
	band.radial_segments = 20
	var roof := CylinderMesh.new()
	roof.top_radius = radius * 0.15
	roof.bottom_radius = radius * 1.02
	roof.height = radius * 0.32
	roof.radial_segments = 20
	var mesh := ArrayMesh.new()
	var parts: Array[Array] = [[body, height * 0.5, TANK_COLOR], [band, height * 0.66, TANK_BAND_COLOR],
			[roof, height + radius * 0.16, TANK_ROOF_COLOR]]
	for part: Array in parts:
		var arrays: Array = (part[0] as PrimitiveMesh).get_mesh_arrays()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in points.size():
			points[i].y += part[1]
		arrays[Mesh.ARRAY_VERTEX] = points
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = part[2]
		material.roughness = 0.6
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func _add_truck(trucks: Array, cell: Vector2i, pos: Vector3, turn: float) -> void:
	trucks[int(_roll(cell, 12) * trucks.size())].append(Transform3D(Basis(Vector3.UP, turn), pos))


## Забор по краям клетки двора, за которыми не этот участок (соседний двор, пустая земля, дорога).
## Край к своему дому забора не получает. height — высота бруса слоя: штакетник у домов, бетон у заводов.
func _fence_cell(grid: CityGrid, lot: CityGrid.Lot, cell: Vector2i, fence: Array[Transform3D],
		fenced: Dictionary[Vector3i, bool], height: float = FENCE_HEIGHT) -> void:
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
		fence.append(Transform3D(basis, edge + Vector3.UP * height * 0.5))


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
