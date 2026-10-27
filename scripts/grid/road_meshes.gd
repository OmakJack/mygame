class_name RoadMeshes
extends RefCounted
## Куски дорог: модели Kenney, а если их нет — заглушки, сгенерированные кодом.
## road_visualizer зависит только от номеров кусков (Piece).

## Номера кусков в MeshLibrary. Каждый нарисован в «базовом» повороте (BASE_MASKS).
enum Piece { END, STRAIGHT, CORNER, T, CROSS }

## Маска соседей каждого куска в базовом повороте (N=1, E=2, S=4, W=8).
const BASE_MASKS: Array[int] = [
	CityGrid.DIR_N,
	CityGrid.DIR_N | CityGrid.DIR_S,
	CityGrid.DIR_N | CityGrid.DIR_E,
	CityGrid.DIR_N | CityGrid.DIR_E | CityGrid.DIR_S,
	CityGrid.DIR_N | CityGrid.DIR_E | CityGrid.DIR_S | CityGrid.DIR_W,
]

const ASPHALT_COLOR := Color(0.22, 0.22, 0.24)
const SIDEWALK_COLOR := Color(0.62, 0.62, 0.6)
const MARKING_COLOR := Color(0.95, 0.95, 0.9)

# Размеры в долях половины клетки: клетка от −1 до 1, умножаем на CELL_SIZE / 2.
const ROAD_HALF_WIDTH: float = 0.7
const SIDEWALK_HALF_WIDTH: float = 0.85
const MARKING_HALF_WIDTH: float = 0.035
# Высоты слоёв над землёй (сетка — 0.01, превью — 0.05, курсор — 0.06).
const SIDEWALK_Y: float = 0.02
const ASPHALT_Y: float = 0.03
const MARKING_Y: float = 0.035


## Модели Kenney для кусков (плитка 1×1, у нас клетка 2 м).
const MODELS: Array[String] = [
	"res://assets/models/kenney/roads/road-end.glb",
	"res://assets/models/kenney/roads/road-straight.glb",
	"res://assets/models/kenney/roads/road-bend.glb",
	"res://assets/models/kenney/roads/road-intersection.glb",
	"res://assets/models/kenney/roads/road-crossroad.glb",
]
## Поворот каждой модели (шаги по 90° по часовой), чтобы её рукава совпали с BASE_MASKS.
## Модели Kenney: тупик открыт на E, прямая — E–W, поворот — S–W, T закрыт с N.
## Таблицу проверяет тест через native_mask (см. ниже) — эвристика только в тесте.
const MODEL_TURNS: Array[int] = [3, 1, 2, 3, 0]
## Мост через воду (фаза 9): отдельный кусок после Piece. Модель Kenney — настил на опорах,
## идёт с N на S; опускаем настил до высоты асфальта, опоры уходят под воду.
const BRIDGE_ITEM: int = 5
const BRIDGE_MODEL: String = "res://assets/models/kenney/roads/road-bridge.glb"
const BRIDGE_DROP: float = 0.49
## Вершина «у середины края» плитки 1×1: на краю (±0.5) и не дальше этого от середины.
const EDGE_EPSILON: float = 0.02
const EDGE_MIDDLE: float = 0.12


static func build_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	for piece: int in BASE_MASKS.size():
		library.create_item(piece)
		library.set_item_name(piece, Piece.keys()[piece])
		var mesh: Mesh = _model_piece(piece)
		if mesh == null:
			mesh = _build_piece(BASE_MASKS[piece], piece, material)
		library.set_item_mesh(piece, mesh)
	library.create_item(BRIDGE_ITEM)
	library.set_item_name(BRIDGE_ITEM, "BRIDGE")
	var bridge: Mesh = _model_piece(Piece.STRAIGHT)
	if ResourceLoader.exists(BRIDGE_MODEL):
		var scale := Vector3(CityGrid.CELL_SIZE, 1.0, CityGrid.CELL_SIZE)
		bridge = ModelLoader.merge(load(BRIDGE_MODEL), Transform3D(Basis.from_scale(scale), Vector3.DOWN * BRIDGE_DROP))
	library.set_item_mesh(BRIDGE_ITEM, bridge)
	return library


## Кусок из модели с поворотом из MODEL_TURNS. null — модели нет (тогда — заглушка из кода).
static func _model_piece(piece: int) -> ArrayMesh:
	if not ResourceLoader.exists(MODELS[piece]):
		return null
	# Поворот на −90° вокруг Y — шаг по часовой (N → E), как в road_visualizer.
	# По высоте не растягиваем: асфальт остаётся тонким (0..0.02).
	var scale := Vector3(CityGrid.CELL_SIZE, 1.0, CityGrid.CELL_SIZE)
	var basis := Basis(Vector3.UP, -MODEL_TURNS[piece] * PI * 0.5) * Basis.from_scale(scale)
	return ModelLoader.merge(load(MODELS[piece]), Transform3D(basis, Vector3.ZERO))


## Рукава плитки по геометрии: вершины у середины края есть только там, где дорога выходит
## за край (на закрытых сторонах там тротуар без вершин посередине). Биты: N=1, E=2, S=4, W=8.
## half — половина стороны плитки (0.5 у модели, CELL_SIZE / 2 у готового куска).
static func native_mask(mesh: Mesh, half: float = 0.5) -> int:
	var k: float = half / 0.5
	var epsilon: float = EDGE_EPSILON * k
	var middle: float = EDGE_MIDDLE * k
	var mask: int = 0
	for surface: int in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in vertices:
			if absf(v.z + half) < epsilon and absf(v.x) < middle:
				mask |= CityGrid.DIR_N
			elif absf(v.x - half) < epsilon and absf(v.z) < middle:
				mask |= CityGrid.DIR_E
			elif absf(v.z - half) < epsilon and absf(v.x) < middle:
				mask |= CityGrid.DIR_S
			elif absf(v.x + half) < epsilon and absf(v.z) < middle:
				mask |= CityGrid.DIR_W
	return mask




static func _build_piece(mask: int, piece: int, material: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# Перекрёсток у T и CROSS: разметку рисуем только вдали от центра.
	var is_junction: bool = piece == Piece.CORNER or piece == Piece.T or piece == Piece.CROSS

	_add_rect(st, Rect2(-SIDEWALK_HALF_WIDTH, -SIDEWALK_HALF_WIDTH, SIDEWALK_HALF_WIDTH * 2, SIDEWALK_HALF_WIDTH * 2), 0, SIDEWALK_Y, SIDEWALK_COLOR)
	_add_rect(st, Rect2(-ROAD_HALF_WIDTH, -ROAD_HALF_WIDTH, ROAD_HALF_WIDTH * 2, ROAD_HALF_WIDTH * 2), 0, ASPHALT_Y, ASPHALT_COLOR)
	for dir: int in 4:
		if mask & (1 << dir) == 0:
			continue
		# Рукав в сторону N: от края клетки (z = −1) до центрального квадрата, поворачиваем на dir.
		# Рукав стыкуется с квадратом встык, без наложения.
		_add_rect(st, Rect2(-SIDEWALK_HALF_WIDTH, -1.0, SIDEWALK_HALF_WIDTH * 2, 1.0 - SIDEWALK_HALF_WIDTH), dir, SIDEWALK_Y, SIDEWALK_COLOR)
		_add_rect(st, Rect2(-ROAD_HALF_WIDTH, -1.0, ROAD_HALF_WIDTH * 2, 1.0 - ROAD_HALF_WIDTH), dir, ASPHALT_Y, ASPHALT_COLOR)
		# Пунктир: штрих 0.3, промежуток 0.2 — стыкуется между соседними клетками.
		_add_rect(st, Rect2(-MARKING_HALF_WIDTH, -0.9, MARKING_HALF_WIDTH * 2, 0.3), dir, MARKING_Y, MARKING_COLOR)
		if not is_junction:
			_add_rect(st, Rect2(-MARKING_HALF_WIDTH, -0.4, MARKING_HALF_WIDTH * 2, 0.3), dir, MARKING_Y, MARKING_COLOR)

	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, material)
	return mesh


## Прямоугольник в координатах «рукава на север» (x, z в долях половины клетки),
## повёрнутый на dir шагов по часовой стрелке (вид сверху).
static func _add_rect(st: SurfaceTool, rect: Rect2, dir: int, y: float, color: Color) -> void:
	var half_cell: float = CityGrid.CELL_SIZE * 0.5
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var points: Array[Vector3] = []
	for corner: Vector2 in corners:
		var p: Vector2 = corner
		for i: int in dir:
			# Поворот на 90° по часовой: N(0,−1) → E(1,0).
			p = Vector2(-p.y, p.x)
		points.append(Vector3(p.x * half_cell, y, p.y * half_cell))
	st.set_color(color)
	# Обход по часовой стрелке при виде сверху — у Godot это лицевая сторона.
	for index: int in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(points[index])
