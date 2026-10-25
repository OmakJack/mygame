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


static func build_library(types: Array[BuildingData]) -> MeshLibrary:
	var library := MeshLibrary.new()
	for item: int in types.size():
		var data: BuildingData = types[item]
		library.create_item(item)
		library.set_item_name(item, String(data.id))
		library.set_item_mesh(item, mesh_for(data))
	return library


## Меш типа здания в координатах клетки: центр основания — в начале координат, фасад на −Z.
static func mesh_for(data: BuildingData) -> Mesh:
	if data.model != null:
		return _from_model(data)
	if data.mesh != null:
		return data.mesh
	return _placeholder(data)


static func _from_model(data: BuildingData) -> ArrayMesh:
	var box: AABB = ModelLoader.bounds(data.model)
	# Масштаб типа, но не больше, чем позволяет клетка.
	var widest: float = maxf(box.size.x, box.size.z)
	var scale: float = minf(data.model_scale, FOOTPRINT / widest) if widest > 0.0 else data.model_scale
	var mesh: ArrayMesh = ModelLoader.merge(data.model, ModelLoader.placement(box, scale, data.model_turns))
	if data.sign_color.a > 0.0:
		_add_sign(mesh, box.size.y * scale, data.sign_color)
	return mesh


## Табличка цвета службы над крышей у фасада — чтобы службы отличались от обычных домов.
static func _add_sign(mesh: ArrayMesh, roof: float, color: Color) -> void:
	var front: float = -FOOTPRINT * 0.25
	_add_box(mesh, SIGN_POST, Vector3(0.0, roof + SIGN_POST.y * 0.5, front), SIGN_POST_COLOR)
	_add_box(mesh, SIGN_SIZE, Vector3(0.0, roof + SIGN_POST.y + SIGN_SIZE.y * 0.5, front), color)


static func _placeholder(data: BuildingData) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var height: float = data.placeholder_height
	_add_box(mesh, Vector3(BODY_WIDTH, height, BODY_WIDTH), Vector3(0.0, height * 0.5, 0.0), data.placeholder_color)
	# Дверь чуть выступает из фасада, чтобы было видно, куда смотрит дом.
	var door_z: float = -(BODY_WIDTH + DOOR_SIZE.z) * 0.5
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
