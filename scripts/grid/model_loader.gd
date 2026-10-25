class_name ModelLoader
extends RefCounted
## Собирает из сцены модели (GLB) один ArrayMesh: все MeshInstance3D со своими трансформами,
## с материалами (общая палитра-текстура Kenney). Нужен для MeshLibrary и MultiMesh,
## которые принимают один меш, а не сцену.


## Габариты модели в её собственных координатах.
static func bounds(scene: PackedScene) -> AABB:
	var root: Node = scene.instantiate()
	var box := AABB()
	var first: bool = true
	for entry: Array in _mesh_nodes(root, Transform3D.IDENTITY):
		var part: AABB = (entry[1] as Transform3D) * (entry[0] as MeshInstance3D).mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	root.free()
	return box


## Один меш из всех частей модели; transform применяется к вершинам («запекается»).
static func merge(scene: PackedScene, transform: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var root: Node = scene.instantiate()
	var result := ArrayMesh.new()
	for entry: Array in _mesh_nodes(root, Transform3D.IDENTITY):
		var node: MeshInstance3D = entry[0]
		var xf: Transform3D = transform * (entry[1] as Transform3D)
		var normal_basis: Basis = xf.basis.inverse().transposed()
		for surface: int in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i: int in vertices.size():
				vertices[i] = xf * vertices[i]
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i: int in normals.size():
					normals[i] = (normal_basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			# Касательные после поворота неверны; у моделей Kenney нет карт нормалей — убираем.
			arrays[Mesh.ARRAY_TANGENT] = null
			result.add_surface_from_arrays(node.mesh.surface_get_primitive_type(surface), arrays)
			result.surface_set_material(result.get_surface_count() - 1, node.get_active_material(surface))
	root.free()
	return result


## Трансформ, который ставит модель основанием на землю в центр клетки, с поворотом и масштабом.
static func placement(box: AABB, scale: float, turns: int) -> Transform3D:
	var basis := Basis(Vector3.UP, -turns * PI * 0.5).scaled(Vector3.ONE * scale)
	var bottom_center := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
	return Transform3D(basis, -(basis * bottom_center))


## Пары [MeshInstance3D, трансформ относительно корня модели].
static func _mesh_nodes(node: Node, parent: Transform3D) -> Array[Array]:
	var found: Array[Array] = []
	var xf: Transform3D = parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append([node, xf])
	for child: Node in node.get_children():
		found.append_array(_mesh_nodes(child, xf))
	return found
