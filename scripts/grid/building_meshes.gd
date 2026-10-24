class_name BuildingMeshes
extends RefCounted
## MeshLibrary зданий из BuildingCatalog. Номер куска = номер типа в списке.
## Тип без модели получает коробку-заглушку с дверью на фасаде (−Z).

## Ширина заглушки, метры (клетка — CityGrid.CELL_SIZE).
const BODY_WIDTH: float = 1.5
const DOOR_SIZE := Vector3(0.45, 0.8, 0.08)
const DOOR_COLOR := Color(0.25, 0.18, 0.12)


static func build_library(types: Array[BuildingData]) -> MeshLibrary:
	var library := MeshLibrary.new()
	for item: int in types.size():
		var data: BuildingData = types[item]
		library.create_item(item)
		library.set_item_name(item, String(data.id))
		library.set_item_mesh(item, data.mesh if data.mesh != null else _placeholder(data))
	return library


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
