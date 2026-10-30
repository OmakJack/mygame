class_name TreeVisualizer
extends Node3D
## Деревья — только визуал: рощами по шуму на свободных клетках (нет дороги, здания и зоны)
## и лесом вокруг карты. Исчезают, когда клетку занимают, и возвращаются, когда освобождают.
## Расстановка детерминированная: одна и та же клетка всегда даёт те же деревья.

const MODELS: Array[String] = [
	"res://assets/models/kenney/suburban/tree-large.glb",
	"res://assets/models/kenney/suburban/tree-small.glb",
]
## Лес вокруг карты, клеток (земля тянется на 60 м = 30 клеток).
const MARGIN_CELLS: int = 30
## Порог шума: выше — роща. Вокруг карты лес гуще, внутри — реже, чтобы не мешать строить.
const INSIDE_THRESHOLD: float = 0.2
const OUTSIDE_THRESHOLD: float = 0.0
const MAX_PER_CELL: int = 4
## Предел деревьев. Деревья на карте не прореживаются; лес вокруг прореживается равномерно
## по всей площади, чтобы уложиться в предел (раньше предел обрывал проход по строкам —
## и нижняя половина поля оставалась голой).
const MAX_TREES: int = 9000
const SCALE_MIN: float = 1.6
const SCALE_MAX: float = 2.4
## Насколько дерево может сдвинуться от центра клетки, метры.
const JITTER: float = 0.7

var _layers: Array[MultiMeshInstance3D] = []
var _noise := FastNoiseLite.new()
## Свободна ли клетка карты (по индексу) — чтобы перестраивать только при настоящих изменениях.
var _free := PackedByteArray()


func _ready() -> void:
	_noise.seed = 1337
	_noise.frequency = 0.13
	for path: String in MODELS:
		if not ResourceLoader.exists(path):
			continue
		var layer := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = ModelLoader.fitted(load(path), 1.0, 0)
		layer.multimesh = multimesh
		add_child(layer)
		_layers.append(layer)
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	var grid: CityGrid = GameState.grid
	for cell: Vector2i in cells:
		if grid.is_in_bounds(cell) and _is_free(grid, cell) != (_free[grid.index_of(cell)] == 1):
			_rebuild()
			return


func _rebuild() -> void:
	if _layers.is_empty():
		return
	var grid: CityGrid = GameState.grid
	_free.resize(grid.size * grid.size)
	var transforms: Array[Array] = []
	for layer: MultiMeshInstance3D in _layers:
		transforms.append([])
	var rng := RandomNumberGenerator.new()
	# Полоса трассы за картой (и по клетке с боков) — без деревьев.
	var highway: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in grid.outside_highway(MARGIN_CELLS):
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			highway[cell + offset] = true
	# Первый проход — сколько деревьев хочется на карте и вокруг; из этого — доля леса вокруг.
	# Деревья карты считаются так, будто все клетки свободны: доля леса вокруг не зависит
	# от стройки, и лес не перетасовывается при каждой новой зоне.
	var wanted_inside: int = 0
	var wanted_outside: int = 0
	for y: int in range(-MARGIN_CELLS, grid.size + MARGIN_CELLS):
		for x: int in range(-MARGIN_CELLS, grid.size + MARGIN_CELLS):
			var cell := Vector2i(x, y)
			var inside: bool = grid.is_in_bounds(cell)
			if highway.has(cell):
				continue
			if inside:
				_free[grid.index_of(cell)] = 1 if _is_free(grid, cell) else 0
			var count: int = _count_at(cell, inside)
			if inside:
				wanted_inside += count
			else:
				wanted_outside += count
	var keep_outside: float = 1.0
	if wanted_outside > 0:
		keep_outside = clampf(float(MAX_TREES - wanted_inside) / wanted_outside, 0.0, 1.0)
	for y: int in range(-MARGIN_CELLS, grid.size + MARGIN_CELLS):
		for x: int in range(-MARGIN_CELLS, grid.size + MARGIN_CELLS):
			var cell := Vector2i(x, y)
			var inside: bool = grid.is_in_bounds(cell)
			if highway.has(cell) or (inside and _free[grid.index_of(cell)] == 0):
				continue
			var count: int = _count_at(cell, inside)
			if count == 0:
				continue
			rng.seed = hash(cell)
			for i: int in count:
				var offset := Vector3(rng.randf_range(-JITTER, JITTER), 0.0, rng.randf_range(-JITTER, JITTER))
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(SCALE_MIN, SCALE_MAX))
				var layer: int = rng.randi_range(0, _layers.size() - 1)
				# Лес вокруг — равномерно прореженный (решение по своему зерну клетки — стабильно).
				if not inside and rng.randf() >= keep_outside:
					continue
				var center := Vector3((x + 0.5) * CityGrid.CELL_SIZE, 0.0, (y + 0.5) * CityGrid.CELL_SIZE)
				transforms[layer].append(Transform3D(basis, center + offset))
	for i: int in _layers.size():
		var multimesh: MultiMesh = _layers[i].multimesh
		var list: Array = transforms[i]
		multimesh.instance_count = list.size()
		for k: int in list.size():
			multimesh.set_instance_transform(k, list[k])


## Сколько деревьев хочет клетка: по шуму; на карте порог выше (рощи реже), вокруг — лес.
func _count_at(cell: Vector2i, inside: bool) -> int:
	var threshold: float = INSIDE_THRESHOLD if inside else OUTSIDE_THRESHOLD
	var density: float = _noise.get_noise_2d(cell.x, cell.y)
	if density < threshold:
		return 0
	return clampi(1 + int((density - threshold) * 8.0), 1, MAX_PER_CELL)


## Сколько деревьев сейчас (для проверок).
func tree_count() -> int:
	var total: int = 0
	for layer: MultiMeshInstance3D in _layers:
		total += layer.multimesh.instance_count
	return total


static func _is_free(grid: CityGrid, cell: Vector2i) -> bool:
	var i: int = grid.index_of(cell)
	return grid.tile_type[i] == CityGrid.Tile.EMPTY and grid.zone[i] == CityGrid.Zone.NONE and grid.water[i] == 0
