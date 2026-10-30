class_name ModelLoader
extends RefCounted
## Собирает из сцены модели (GLB) один ArrayMesh: все MeshInstance3D со своими трансформами.
## Части с одним материалом склеиваются в одну поверхность (у Kenney это почти всегда одна
## палитра-текстура) — одна поверхность = один вызов отрисовки в MeshLibrary и MultiMesh.


## Габариты модели в её собственных координатах.
static func bounds(scene: PackedScene) -> AABB:
	var root: Node = scene.instantiate()
	var box: AABB = _bounds_of(_mesh_nodes(root, Transform3D.IDENTITY))
	root.free()
	return box


## Один меш из всех частей модели; transform применяется к вершинам («запекается»).
static func merge(scene: PackedScene, transform: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var root: Node = scene.instantiate()
	var mesh: ArrayMesh = _merge_parts(_mesh_nodes(root, Transform3D.IDENTITY), transform)
	root.free()
	return mesh


## Модель основанием в центр клетки, с поворотом; масштаб — scale, но основание не шире footprint
## (0 — без предела). Сцена загружается один раз.
static func fitted(scene: PackedScene, scale: float, turns: int, footprint: float = 0.0) -> ArrayMesh:
	return fitted_rect(scene, scale, turns, Vector2(footprint, footprint))


## Модель основанием в центр участка, с поворотом; масштаб ужимается под прямоугольник max_size (X, Z).
static func fitted_rect(scene: PackedScene, scale: float, turns: int, max_size: Vector2) -> ArrayMesh:
	var root: Node = scene.instantiate()
	var parts: Array[Array] = _mesh_nodes(root, Transform3D.IDENTITY)
	var box: AABB = _bounds_of(parts)
	var span_x: float = box.size.z if posmod(turns, 2) == 1 else box.size.x
	var span_z: float = box.size.x if posmod(turns, 2) == 1 else box.size.z
	if max_size.x > 0.0 and span_x > 0.0:
		scale = minf(scale, max_size.x / span_x)
	if max_size.y > 0.0 and span_z > 0.0:
		scale = minf(scale, max_size.y / span_z)
	var mesh: ArrayMesh = _merge_parts(parts, placement(box, scale, turns))
	root.free()
	return mesh


## Трансформ, который ставит модель основанием на землю в центр клетки, с поворотом и масштабом.
static func placement(box: AABB, scale: float, turns: int) -> Transform3D:
	var basis := Basis(Vector3.UP, -turns * PI * 0.5).scaled(Vector3.ONE * scale)
	var bottom_center := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
	return Transform3D(basis, -(basis * bottom_center))


static func _merge_parts(parts: Array[Array], transform: Transform3D) -> ArrayMesh:
	# Материал → SurfaceTool, куда складываются все части с этим материалом.
	var tools: Dictionary[Material, SurfaceTool] = {}
	var no_material := SurfaceTool.new()
	var has_no_material: bool = false
	for entry: Array in parts:
		var node: MeshInstance3D = entry[0]
		var xf: Transform3D = transform * (entry[1] as Transform3D)
		for surface: int in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material: Material = node.get_active_material(surface)
			var tool: SurfaceTool = no_material
			if material == null:
				has_no_material = true
			else:
				if not tools.has(material):
					tools[material] = SurfaceTool.new()
				tool = tools[material]
			# append_from сама переносит вершины и нормали трансформом.
			tool.append_from(node.mesh, surface, xf)
	var result := ArrayMesh.new()
	for material: Material in tools:
		tools[material].commit(result)
		result.surface_set_material(result.get_surface_count() - 1, material)
	if has_no_material:
		no_material.commit(result)
	return result


static func _bounds_of(parts: Array[Array]) -> AABB:
	var box := AABB()
	var first: bool = true
	for entry: Array in parts:
		var part: AABB = (entry[1] as Transform3D) * (entry[0] as MeshInstance3D).mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


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
