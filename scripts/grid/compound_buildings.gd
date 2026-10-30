class_name CompoundBuildings
extends RefCounted
## Многоклеточные участки (2..7 клеток), собранные из моделей Kenney на общем основании:
## усадьбы и таунхаусы с садами (R), торговые дворики и рынки (C), промбазы с контейнерами и баками (I).
## Вход участка смотрит на −Z; ширина — вдоль X, глубина — вдоль Z.

const SUB := "res://assets/models/kenney/suburban/"
const COM := "res://assets/models/kenney/commercial/"
const IND := "res://assets/models/kenney/industrial/"
const ROADS := "res://assets/models/kenney/roads/"

const GRASS := Color(0.42, 0.65, 0.33)
const PAVING := Color(0.78, 0.75, 0.69)
const CONCRETE := Color(0.56, 0.56, 0.54)
const BASE_HEIGHT: float = 0.025
const BASE_MARGIN: float = 0.08


## Все составные многоклеточные типы для каталога.
static func types() -> Array[BuildingData]:
	var cache: Dictionary[String, Array] = {}
	var result: Array[BuildingData] = []
	for spec: Dictionary in _specs():
		var data := BuildingData.new()
		data.id = StringName(spec.id)
		data.display_name = "%s · ур. %d" % [spec.name, spec.level]
		data.grows = true
		LevelStats.apply(data, spec.zone, spec.level, spec.size)
		data.mesh = _build_lot(spec.size, spec.base, spec.parts, cache)
		result.append(data)
	for entry: Array in cache.values():
		if entry.size() >= 3 and entry[2] != null:
			(entry[2] as Node).free()
	return result


## Описание участков: [модель, x, z, поворот_90, масштаб, макс_размер].
static func _specs() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	# --- ЖИЛАЯ ЗОНА (R): от 2 до 6 клеток, уровни 1..3 ---
	var r_houses: Array[Array] = [
		["a", "b", "c", "d"],
		["g", "h", "i", "k"],
		["o", "p", "r", "t"],
	]
	for lvl: int in [1, 2, 3]:
		var h: Array = r_houses[lvl - 1]
		var hs: float = 1.08 + lvl * 0.04
		# 2×1 (2 кл.) — коттедж с садом и дорожкой (2 варианта на уровень)
		list.append({
			"id": "res_lot_2x1_%d_a" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(2, 1), "name": "Дом с садом", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[0], -0.95, 0.05, 2, hs, 1.68],
				[SUB + "path-stones-long", -0.95, -0.72, 0, 1.6, 0.9],
				[SUB + "tree-large", 1.05, 0.35, 0, 2.3, 1.3],
				[SUB + "tree-small", 0.55, -0.35, 1, 2.0, 1.0],
				[SUB + "planter", 1.25, -0.45, 0, 1.7, 0.9],
			],
		})
		list.append({
			"id": "res_lot_2x1_%d_b" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(2, 1), "name": "Дуплекс", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[1], -0.95, 0.08, 2, hs, 1.62],
				[SUB + "building-type-" + h[2], 0.95, 0.08, 2, hs, 1.62],
				[SUB + "tree-small", 0.0, 0.55, 0, 2.1, 1.0],
				[SUB + "planter", 0.0, -0.58, 0, 1.6, 0.85],
			],
		})
		# 3×1 (3 кл.) — ряд из трёх коттеджей / усадьба с садом
		list.append({
			"id": "res_lot_3x1_%d_a" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(3, 1), "name": "Таунхаусы", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[0], -1.95, 0.08, 2, hs, 1.62],
				[SUB + "building-type-" + h[1], 0.0, 0.08, 2, hs, 1.62],
				[SUB + "building-type-" + h[2], 1.95, 0.08, 2, hs, 1.62],
				[SUB + "tree-small", -0.98, -0.62, 0, 1.9, 0.85],
				[SUB + "tree-small", 0.98, -0.62, 2, 1.9, 0.85],
			],
		})
		list.append({
			"id": "res_lot_3x1_%d_b" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(3, 1), "name": "Усадьба", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[3], 0.0, 0.1, 2, hs + 0.08, 1.75],
				[SUB + "path-long", 0.0, -0.68, 0, 1.7, 0.9],
				[SUB + "tree-large", -2.0, 0.25, 0, 2.5, 1.35],
				[SUB + "tree-small", -1.45, -0.45, 1, 2.1, 1.0],
				[SUB + "planter", -2.2, -0.45, 0, 1.8, 0.9],
				[SUB + "tree-large", 2.05, 0.3, 2, 2.4, 1.35],
				[SUB + "planter", 1.65, -0.45, 0, 1.8, 0.9],
			],
		})
		# 2×2 (4 кл.) — дворик с двумя домами и садом
		list.append({
			"id": "res_lot_2x2_%d" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(2, 2), "name": "Жилой дворик", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[1], -0.98, -0.92, 2, hs, 1.68],
				[SUB + "building-type-" + h[3], 0.98, -0.92, 2, hs, 1.68],
				[SUB + "building-type-" + h[0], -0.98, 0.98, 3, hs * 0.95, 1.55],
				[SUB + "tree-large", 0.95, 0.95, 0, 2.6, 1.45],
				[SUB + "tree-small", 0.35, 1.35, 1, 2.2, 1.05],
				[SUB + "planter", 0.95, 0.15, 0, 2.0, 1.0],
				[SUB + "path-stones-long", 0.0, -0.2, 0, 1.8, 1.0],
			],
		})
		# 5×1 (5 кл.) — зелёная жилая линия вдоль улицы
		list.append({
			"id": "res_lot_5x1_%d" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(5, 1), "name": "Коттеджный ряд", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[0], -3.9, 0.08, 2, hs, 1.62],
				[SUB + "building-type-" + h[2], -1.95, 0.08, 2, hs, 1.62],
				[SUB + "tree-large", 0.0, 0.25, 0, 2.5, 1.35],
				[SUB + "planter", 0.0, -0.5, 0, 2.0, 1.0],
				[SUB + "building-type-" + h[1], 1.95, 0.08, 2, hs, 1.62],
				[SUB + "building-type-" + h[3], 3.9, 0.08, 2, hs, 1.62],
				[SUB + "tree-small", -2.92, -0.62, 1, 1.9, 0.85],
				[SUB + "tree-small", 2.92, -0.62, 3, 1.9, 0.85],
			],
		})
		# 3×2 (6 кл.) — загородное подворье вокруг сада
		list.append({
			"id": "res_lot_3x2_%d" % lvl, "zone": CityGrid.Zone.RESIDENTIAL, "level": lvl,
			"size": Vector2i(3, 2), "name": "Жилое подворье", "base": GRASS,
			"parts": [
				[SUB + "building-type-" + h[3], 0.0, -0.95, 2, hs + 0.06, 1.72],
				[SUB + "building-type-" + h[0], -1.98, -0.92, 2, hs, 1.64],
				[SUB + "building-type-" + h[1], 1.98, -0.92, 2, hs, 1.64],
				[SUB + "building-type-" + h[2], -1.98, 0.98, 3, hs * 0.95, 1.55],
				[SUB + "building-type-" + h[0], 1.98, 0.98, 1, hs * 0.95, 1.55],
				[SUB + "tree-large", -0.55, 0.95, 0, 2.6, 1.4],
				[SUB + "tree-large", 0.65, 1.05, 2, 2.4, 1.35],
				[SUB + "planter", 0.0, 0.25, 0, 2.2, 1.1],
			],
		})

	# --- КОММЕРЦИЯ (C): 2×1 и 3×2 (остальные размеры — из Blender GLB) ---
	var c_shops: Array[Array] = [
		["a", "e"],
		["b", "d"],
		["i", "k"],
	]
	for lvl: int in [1, 2, 3]:
		var sh: Array = c_shops[lvl - 1]
		# 2×1 (2 кл.) — пара лавок с летней террасой
		list.append({
			"id": "com_lot_2x1_%d" % lvl, "zone": CityGrid.Zone.COMMERCIAL, "level": lvl,
			"size": Vector2i(2, 1), "name": "Торговый дворик", "base": PAVING,
			"parts": [
				[COM + "building-" + sh[0], -0.98, 0.08, 2, 1.35, 1.65],
				[COM + "building-" + sh[1], 0.98, 0.08, 2, 1.35, 1.65],
				[COM + "detail-parasol-a", 0.0, -0.55, 0, 1.6, 0.8],
				[SUB + "planter", -1.65, -0.68, 0, 1.5, 0.7],
				[SUB + "planter", 1.65, -0.68, 0, 1.5, 0.7],
			],
		})
		# 3×2 (6 кл.) — ярмарочная площадь с магазинами и сквером
		list.append({
			"id": "com_lot_3x2_%d" % lvl, "zone": CityGrid.Zone.COMMERCIAL, "level": lvl,
			"size": Vector2i(3, 2), "name": "Торговая площадь", "base": PAVING,
			"parts": [
				[COM + "building-" + sh[0], -1.98, -0.92, 2, 1.38, 1.68],
				[COM + "building-" + sh[1], 1.98, -0.92, 2, 1.38, 1.68],
				[COM + "building-" + sh[1], -1.98, 0.96, 3, 1.35, 1.65],
				[COM + "building-" + sh[0], 0.0, 0.98, 2, 1.38, 1.68],
				[COM + "building-" + sh[1], 1.98, 0.96, 1, 1.35, 1.65],
				[COM + "detail-parasol-a", -0.5, -0.55, 0, 1.7, 0.85],
				[COM + "detail-parasol-b", 0.5, -0.55, 1, 1.7, 0.85],
				[SUB + "planter", 0.0, -0.1, 0, 2.2, 1.1],
				[ROADS + "light-square", -0.85, -1.55, 0, 1.5, 0.7],
				[ROADS + "light-square", 0.85, -1.55, 0, 1.5, 0.7],
			],
		})

	# --- ПРОМЗОНА (I): 3×1 и 7×1 (2×1, 2×2, 5×1, 3×2 — из Blender GLB) ---
	var i_halls: Array[Array] = [
		["a", "b", "c"],
		["g", "h", "j"],
		["p", "r", "t"],
	]
	for lvl: int in [1, 2, 3]:
		var ih: Array = i_halls[lvl - 1]
		# 3×1 (3 кл.) — промбаза с цехами и баками
		list.append({
			"id": "ind_lot_3x1_%d" % lvl, "zone": CityGrid.Zone.INDUSTRIAL, "level": lvl,
			"size": Vector2i(3, 1), "name": "Промбаза", "base": CONCRETE,
			"parts": [
				[IND + "building-" + ih[0], -1.95, 0.05, 2, 1.0, 1.68],
				[IND + "building-" + ih[1], 0.1, 0.05, 2, 1.0, 1.68],
				[IND + "detail-tank-large", 1.75, 0.25, 0, 1.1, 1.1],
				[IND + "shipping-container-a", 2.15, -0.45, 1, 1.0, 1.1],
				[IND + ("chimney-small" if lvl == 1 else "chimney-medium"), 1.25, 0.45, 0, 1.0, 0.8],
			],
		})
		# 7×1 (7 кл.) — крупный логистический и заводской комплекс вдоль улицы
		list.append({
			"id": "ind_lot_7x1_%d" % lvl, "zone": CityGrid.Zone.INDUSTRIAL, "level": lvl,
			"size": Vector2i(7, 1), "name": "Промтерминал", "base": CONCRETE,
			"parts": [
				[IND + "building-" + ih[2], -5.85, 0.05, 2, 1.0, 1.72],
				[IND + "building-" + ih[0], -3.85, 0.05, 2, 1.0, 1.72],
				[IND + "shipping-container-a", -2.15, -0.35, 0, 1.05, 1.2],
				[IND + "shipping-container-b", -1.65, 0.35, 0, 1.05, 1.2],
				[IND + "building-" + ih[1], 0.0, 0.05, 2, 1.05, 1.74],
				[IND + "building-" + ih[2], 2.0, 0.05, 2, 1.05, 1.74],
				[IND + "detail-tank-large", 3.85, 0.2, 0, 1.15, 1.2],
				[IND + "detail-tank", 4.65, -0.35, 0, 1.1, 0.95],
				[IND + "building-" + ih[0], 5.9, 0.05, 2, 1.0, 1.7],
				[IND + ("chimney-medium" if lvl < 3 else "chimney-large"), 3.45, 0.48, 0, 0.95, 0.9],
			],
		})
	return list


static func _build_lot(plot_size: Vector2i, base_color: Color, parts: Array,
		cache: Dictionary[String, Array]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var w: float = plot_size.x * CityGrid.CELL_SIZE - BASE_MARGIN
	var d: float = plot_size.y * CityGrid.CELL_SIZE - BASE_MARGIN
	_add_slab(mesh, Vector3(w, BASE_HEIGHT, d), base_color)

	var tools: Dictionary[Material, SurfaceTool] = {}
	for part: Array in parts:
		var path: String = String(part[0]) + ".glb"
		var loaded: Array = _load_cached(path, cache)
		if loaded.is_empty():
			continue
		var nodes: Array[Array] = loaded[0]
		var box: AABB = loaded[1]
		var turns: int = part[3]
		var scale: float = part[4]
		var max_part: float = part[5]
		var widest: float = maxf(box.size.x, box.size.z)
		if max_part > 0.0 and widest > 0.0:
			scale = minf(scale, max_part / widest)
		var xf: Transform3D = ModelLoader.placement(box, scale, turns)
		xf.origin += Vector3(part[1], BASE_HEIGHT, part[2])
		for entry: Array in nodes:
			var node: MeshInstance3D = entry[0]
			var part_xf: Transform3D = xf * (entry[1] as Transform3D)
			for s: int in node.mesh.get_surface_count():
				if node.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var mat: Material = node.get_active_material(s)
				if mat == null:
					continue
				if not tools.has(mat):
					tools[mat] = SurfaceTool.new()
				tools[mat].append_from(node.mesh, s, part_xf)
	for mat: Material in tools:
		tools[mat].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func _load_cached(path: String, cache: Dictionary[String, Array]) -> Array:
	if cache.has(path):
		return cache[path]
	if not ResourceLoader.exists(path):
		cache[path] = []
		return []
	var scene: PackedScene = load(path)
	var root: Node = scene.instantiate()
	var nodes: Array[Array] = _collect_meshes(root, Transform3D.IDENTITY)
	var box := AABB()
	var first: bool = true
	for entry: Array in nodes:
		var part_box: AABB = (entry[1] as Transform3D) * (entry[0] as MeshInstance3D).mesh.get_aabb()
		box = part_box if first else box.merge(part_box)
		first = false
	cache[path] = [nodes, box, root]
	return cache[path]


static func _collect_meshes(node: Node, parent: Transform3D) -> Array[Array]:
	var found: Array[Array] = []
	var xf: Transform3D = parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append([node, xf])
	for child: Node in node.get_children():
		found.append_array(_collect_meshes(child, xf))
	return found


static func _add_slab(mesh: ArrayMesh, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in vertices.size():
		vertices[i].y += size.y * 0.5
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
