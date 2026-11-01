class_name BuildingMeshes
extends RefCounted
## MeshLibrary зданий из BuildingCatalog. Номер куска = номер типа в списке.
## Тип с моделью (GLB) — модель, вписанная в клетку фасадом на −Z; без модели — mesh;
## без того и другого — коробка-заглушка с дверью на фасаде (−Z).

## Наибольшая сторона основания модели, метры (клетка — CityGrid.CELL_SIZE = 2).
const FOOTPRINT: float = 1.8
## Ширина заглушки, метры.
const BODY_WIDTH: float = 1.5
const DOOR_SIZE := Vector3(0.45, 0.8, 0.08)
const DOOR_COLOR := Color(0.25, 0.18, 0.12)
## Вывеска служебного здания: табличка на столбике над крышей, у фасада.
const SIGN_SIZE := Vector3(0.8, 0.32, 0.06)
const SIGN_POST := Vector3(0.06, 0.3, 0.06)
const SIGN_POST_COLOR := Color(0.3, 0.3, 0.32)
const CONSTRUCTION_GROUND := Color(0.55, 0.44, 0.32)
const FOUNDATION_COLOR := Color(0.72, 0.72, 0.7)
const KENNEY_ROADS := "res://assets/models/kenney/roads/"
## Детали стройплощадки: [модель, x, z, поворот, масштаб] (дорожный набор Kenney: 1 ед. ≈ 0.4 м забора).
const CONSTRUCTION_PARTS: Array = [
	[KENNEY_ROADS + "construction-fence", -0.85, -0.45, 0, 2.5],
	[KENNEY_ROADS + "construction-fence", -0.85, 0.45, 0, 2.5],
	[KENNEY_ROADS + "construction-fence", 0.85, -0.45, 0, 2.5],
	[KENNEY_ROADS + "construction-fence", 0.85, 0.45, 0, 2.5],
	[KENNEY_ROADS + "construction-fence", -0.45, 0.85, 1, 2.5],
	[KENNEY_ROADS + "construction-fence", 0.45, 0.85, 1, 2.5],
	[KENNEY_ROADS + "construction-barrier", -0.45, -0.85, 1, 2.5],
	[KENNEY_ROADS + "construction-cone", 0.3, -0.8, 0, 2.5],
	[KENNEY_ROADS + "construction-cone", 0.55, -0.8, 0, 2.5],
	[KENNEY_ROADS + "construction-light", 0.8, -0.8, 0, 2.5],
]

## Высота меша по типу здания (BadgeVisualizer вешает значок над крышей).
static var _heights: Dictionary[StringName, float] = {}


## Стройплощадка (фаза 10): земля, фундамент с опорами, заборчики, конусы и фонарь Kenney.
static func construction_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = ParkMeshes.build_layout(CONSTRUCTION_PARTS, CONSTRUCTION_GROUND)
	_add_box(mesh, Vector3(1.2, 0.12, 1.2), Vector3(0.0, 0.09, 0.05), FOUNDATION_COLOR)
	for corner: Vector2 in [Vector2(-0.5, -0.45), Vector2(0.5, -0.45), Vector2(-0.5, 0.55), Vector2(0.5, 0.55)]:
		_add_box(mesh, Vector3(0.1, 0.7, 0.1), Vector3(corner.x, 0.5, corner.y), FOUNDATION_COLOR)
	return mesh


## Высота здания типа (верх меша), метры; меш строится один раз на тип.
static func height_of(data: BuildingData) -> float:
	if not _heights.has(data.id):
		_heights[data.id] = mesh_for(data).get_aabb().end.y
	return _heights[data.id]


## Меш типа здания в координатах клетки: центр основания — в начале координат, фасад на −Z.
static func mesh_for(data: BuildingData) -> Mesh:
	if data.park != BuildingData.Park.NONE:
		return ParkMeshes.build(data.park)
	if data.model != null:
		return _from_model(data)
	if data.mesh != null:
		return data.mesh
	return _placeholder(data)


static func _from_model(data: BuildingData) -> ArrayMesh:
	# Масштаб типа, но основание не шире участка (size клеток с отступом 0.2 м); модель загружается один раз.
	var margin: float = CityGrid.CELL_SIZE - FOOTPRINT
	var max_size := Vector2(
		data.size.x * CityGrid.CELL_SIZE - margin,
		data.size.y * CityGrid.CELL_SIZE - margin
	)
	var mesh: ArrayMesh = ModelLoader.fitted_rect(data.model, data.model_scale, data.model_turns, max_size)
	if data.sign_color.a > 0.0:
		_add_sign(mesh, data.sign_color, data.sign_cross, max_size.y)
	return mesh


## Вывеска цвета службы над крышей у фасада — чтобы службы отличались от обычных домов.
## Столбик стоит на реальной крыше в точке крепления, а не на верхушке трубы или шпиля.
static func _add_sign(mesh: ArrayMesh, color: Color, cross: bool, depth: float = FOOTPRINT) -> void:
	var front: float = -depth * 0.25
	var roof: float = _roof_height(mesh, Vector2(0.0, front))
	var center := Vector3(0.0, roof + SIGN_POST.y + SIGN_SIZE.y * 0.5, front)
	_add_box(mesh, SIGN_POST, Vector3(0.0, roof + SIGN_POST.y * 0.5, front), SIGN_POST_COLOR)
	if not cross:
		_add_box(mesh, SIGN_SIZE, center, color)
		return
	# Крест цвета службы на белой подложке — узнаётся без подписей.
	var plate := Vector3(SIGN_SIZE.y * 1.6, SIGN_SIZE.y * 1.6, SIGN_SIZE.z)
	_add_box(mesh, plate, center + Vector3(0.0, plate.y * 0.5 - SIGN_SIZE.y * 0.5, 0.0), Color.WHITE)
	var arm: float = plate.x * 0.7
	var thick: float = plate.x * 0.22
	var bar_center: Vector3 = center + Vector3(0.0, plate.y * 0.5 - SIGN_SIZE.y * 0.5, -SIGN_SIZE.z)
	_add_box(mesh, Vector3(arm, thick, SIGN_SIZE.z), bar_center, color)
	_add_box(mesh, Vector3(thick, arm, SIGN_SIZE.z), bar_center, color)


## Высота модели над точкой at (x, z): наибольшая высота вершин рядом с ней;
## если рядом вершин нет — половина высоты модели.
static func _roof_height(mesh: ArrayMesh, at: Vector2) -> float:
	var reach: float = 0.25
	var best: float = -1.0
	for surface: int in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in vertices:
			if absf(v.x - at.x) < reach and absf(v.z - at.y) < reach:
				best = maxf(best, v.y)
	return best if best >= 0.0 else mesh.get_aabb().size.y * 0.5


static func _placeholder(data: BuildingData) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var height: float = data.placeholder_height
	var margin: float = CityGrid.CELL_SIZE - BODY_WIDTH
	var body_x: float = data.size.x * CityGrid.CELL_SIZE - margin
	var body_z: float = data.size.y * CityGrid.CELL_SIZE - margin
	_add_box(mesh, Vector3(body_x, height, body_z), Vector3(0.0, height * 0.5, 0.0), data.placeholder_color)
	# Дверь чуть выступает из фасада, чтобы было видно, куда смотрит дом.
	var door_z: float = -(body_z + DOOR_SIZE.z) * 0.5
	_add_box(mesh, DOOR_SIZE, Vector3(0.0, DOOR_SIZE.y * 0.5, door_z), DOOR_COLOR)
	return mesh


static func _add_box(mesh: ArrayMesh, size: Vector3, center: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in vertices.size():
		vertices[i] += center
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
