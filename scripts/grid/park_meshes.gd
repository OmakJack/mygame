class_name ParkMeshes
extends RefCounted
## Модели парков (фаза 9): основание (газон или плитка) и детали Kenney — деревья, клумбы,
## дорожки, заборчик, фонари. Координаты — в клетке: центр в начале, фасад (вход) на −Z.

const SUBURBAN := "res://assets/models/kenney/suburban/"
const ROADS := "res://assets/models/kenney/roads/"
const GRASS := Color(0.42, 0.66, 0.32)
const PAVING := Color(0.8, 0.77, 0.7)
## Основание чуть меньше клетки и чуть выше зон (0.006) и земли.
const BASE_SIZE: float = 1.92
const BASE_HEIGHT: float = 0.03

## Детали: [модель, x, z, поворот в шагах по 90°, масштаб].
const LAYOUTS: Dictionary = {
	BuildingData.Park.SQUARE: [
		[SUBURBAN + "path-stones-long", 0.0, -0.4, 0, 2.0],
		[SUBURBAN + "tree-large", 0.45, 0.35, 0, 2.6],
		[SUBURBAN + "tree-small", -0.55, 0.5, 1, 2.4],
		[SUBURBAN + "tree-small", -0.6, -0.5, 0, 2.2],
		[SUBURBAN + "tree-small", 0.6, -0.55, 2, 2.0],
		[SUBURBAN + "planter", -0.05, 0.25, 0, 1.8],
	],
	BuildingData.Park.GARDEN: [
		[SUBURBAN + "fence-2x2", 0.0, 0.0, 0, 0.95],
		[SUBURBAN + "path-long", 0.0, -0.3, 0, 2.0],
		[SUBURBAN + "planter", -0.45, -0.4, 0, 1.7],
		[SUBURBAN + "planter", 0.45, -0.4, 0, 1.7],
		[SUBURBAN + "planter", -0.45, 0.2, 0, 1.7],
		[SUBURBAN + "planter", 0.45, 0.2, 0, 1.7],
		[SUBURBAN + "tree-large", -0.5, 0.6, 0, 2.2],
		[SUBURBAN + "tree-small", 0.5, 0.62, 1, 2.2],
	],
	BuildingData.Park.PLAZA: [
		[SUBURBAN + "planter", 0.0, 0.05, 0, 3.0],
		[SUBURBAN + "tree-small", -0.65, -0.65, 0, 2.2],
		[SUBURBAN + "tree-small", 0.65, -0.65, 1, 2.2],
		[SUBURBAN + "tree-large", -0.62, 0.62, 2, 2.4],
		[SUBURBAN + "tree-large", 0.62, 0.62, 3, 2.4],
		[ROADS + "light-square", -0.8, 0.0, 1, 1.6],
		[ROADS + "light-square", 0.8, 0.0, 3, 1.6],
	],
}


static func build(park: BuildingData.Park) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_base(mesh, PAVING if park == BuildingData.Park.PLAZA else GRASS)
	for part: Array in LAYOUTS.get(park, []):
		var path: String = part[0] + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		var box: AABB = ModelLoader.bounds(scene)
		# Модель основанием на газон, с поворотом и масштабом (размер модели Kenney — в метрах клетки).
		var placement: Transform3D = ModelLoader.placement(box, part[4], part[3])
		placement.origin += Vector3(part[1], BASE_HEIGHT, part[2])
		_append(mesh, ModelLoader.merge(scene, placement))
	return mesh


static func _add_base(mesh: ArrayMesh, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(BASE_SIZE, BASE_HEIGHT, BASE_SIZE)
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in vertices.size():
		vertices[i].y += BASE_HEIGHT * 0.5
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## Переносит поверхности part в mesh вместе с материалами.
static func _append(mesh: ArrayMesh, part: ArrayMesh) -> void:
	for surface: int in part.get_surface_count():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(surface))
		mesh.surface_set_material(mesh.get_surface_count() - 1, part.surface_get_material(surface))
