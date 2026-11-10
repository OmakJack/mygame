extends Node3D
## Полотно дорог по графу GameState.grid.roads (RoadGeometry): по мешу на отрезок и на перекрёсток
## или тупик. Перестраивает только то, у чего изменилась форма (концы, кривая, тип, обрезки у узлов).
## До 2026-11-09 — GridMap из кусков Kenney по маске соседей клетки.
## В слоях карты «Свет» и «Вода» полотно подкрашено (ZoneVisualizer.road_tint): тот же меш вторым
## проходом (material_overlay) — цвет идёт по кривой, а не по клеткам. В слое «Трафик» загрузка вдоль
## отрезка разная (у перекрёстка — пробка, дальше свободно), поэтому поверх полотна лежит лента с цветом
## по клетке под осью (_band_mesh), а узел подкрашен по своей клетке.

## Лента слоя «Трафик»: высота над землёй (выше тротуара) и шаг сечений, м.
const BAND_Y: float = RoadGeometry.SIDEWALK_Y + 0.02
const BAND_STEP: float = 1.0

var _segments: Dictionary[int, MeshInstance3D] = {}
var _segment_keys: Dictionary[int, int] = {}
var _nodes: Dictionary[int, MeshInstance3D] = {}
var _node_keys: Dictionary[int, int] = {}
var _seen_grid: CityGrid = null
var _seen_version: int = -1
## Слой карты (ZoneVisualizer.Overlay) и материалы подкраски по цвету.
var _overlay: int = 0
var _tints: Dictionary[Color, StandardMaterial3D] = {}
## Обрезки отрезков у узлов (начало, конец) и ленты слоя «Трафик».
var _trims: Dictionary[int, Vector2] = {}
var _bands: Dictionary[int, MeshInstance3D] = {}
var _band_material := StandardMaterial3D.new()


func _ready() -> void:
	_band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_band_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_band_material.vertex_color_use_as_albedo = true
	_band_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	Events.grid_reset.connect(_clear)
	Events.overlay_changed.connect(func(mode: int) -> void:
		_overlay = mode
		_retint())
	# Свет, вода и трафик меняются на пересчёте.
	Events.stats_changed.connect(func() -> void:
		if _overlay != 0:
			_retint())


func _process(_delta: float) -> void:
	var grid: CityGrid = GameState.grid
	grid.roads.sync(grid)
	if grid != _seen_grid:
		_clear()
	if grid != _seen_grid or grid.roads.version != _seen_version:
		_refresh(grid)


func _clear() -> void:
	for instance: MeshInstance3D in _segments.values():
		instance.queue_free()
	for instance: MeshInstance3D in _nodes.values():
		instance.queue_free()
	for instance: MeshInstance3D in _bands.values():
		instance.queue_free()
	_bands.clear()
	_trims.clear()
	_segments.clear()
	_segment_keys.clear()
	_nodes.clear()
	_node_keys.clear()
	_seen_grid = null


func _refresh(grid: CityGrid) -> void:
	_seen_grid = grid
	var graph: RoadGraph = grid.roads
	_seen_version = graph.version
	var junctions: Dictionary[int, RoadGeometry.Junction] = {}
	for id: int in graph.nodes:
		junctions[id] = RoadGeometry.junction(graph, id, grid.world_size())
	for id: int in graph.segments:
		var segment: RoadGraph.Segment = graph.segments[id]
		var ja: RoadGeometry.Junction = junctions[segment.a]
		var jb: RoadGeometry.Junction = junctions[segment.b]
		var trim_a: float = ja.trim_of(id)
		var trim_b: float = jb.trim_of(id)
		_trims[id] = Vector2(trim_a, trim_b)
		var key: int = hash([graph.curve(segment), segment.type, trim_a, trim_b, ja.crosswalks, jb.crosswalks])
		if _segment_keys.get(id, 0) == key and _segments.has(id):
			continue
		var st := _begin()
		RoadGeometry.add_segment(st, graph, segment, trim_a, trim_b, ja.crosswalks, jb.crosswalks, grid)
		_put(_segments, id, st)
		_segment_keys[id] = key
	for id: int in graph.nodes:
		var j: RoadGeometry.Junction = junctions[id]
		var shape: Array = [graph.nodes[id].pos, j.cap, j.edge]
		for end: Dictionary in j.ends:
			shape.append_array([end.id, end.dir, end.type, end.trim, graph.curve(graph.segments[end.id])])
		var key: int = hash(shape)
		if _node_keys.get(id, 0) == key and _nodes.has(id):
			continue
		var st := _begin()
		RoadGeometry.add_junction(st, graph, j)
		_put(_nodes, id, st)
		_node_keys[id] = key
	_drop_missing(_segments, _segment_keys, graph.segments)
	_drop_missing(_nodes, _node_keys, graph.nodes)
	_retint()


## Подкраска полотна под слой карты. Свет и вода: отрезок — своим цветом, узел — цветом самой заметной
## из его дорог. Трафик: лента с цветом вдоль отрезка, узел — по загрузке своей клетки.
func _retint() -> void:
	var grid: CityGrid = GameState.grid
	var graph: RoadGraph = grid.roads
	var traffic: bool = _overlay == ZoneVisualizer.Overlay.TRAFFIC and GameState.traffic != null
	var node_colors: Dictionary[int, Color] = {}
	for id: int in _segments:
		var segment: RoadGraph.Segment = graph.segments.get(id)
		var color: Color = ZoneVisualizer.road_tint(_overlay, grid, segment)
		_segments[id].material_overlay = _tint(color)
		_set_band(id, _band_mesh(grid, graph, segment) if traffic and segment != null else null)
		if segment == null:
			continue
		for node: int in [segment.a, segment.b]:
			if not node_colors.has(node) or color.a > node_colors[node].a:
				node_colors[node] = color
	for id: int in _bands.keys():
		if not _segments.has(id):
			_set_band(id, null)
	for id: int in _nodes:
		var color: Color = node_colors.get(id, Color(0, 0, 0, 0))
		if traffic and graph.nodes.has(id):
			color = _load_color(grid, graph.nodes[id].pos)
		_nodes[id].material_overlay = _tint(color)


## Цвет слоя «Трафик» в точке дороги: по загрузке клетки под ней.
func _load_color(grid: CityGrid, pos: Vector2) -> Color:
	var cell: Vector2i = grid.clamp_to_bounds(RoadGraph.cell_of(pos))
	return ZoneVisualizer.traffic_road_color(GameState.traffic.load_ratio(grid, grid.index_of(cell)))


## Лента поверх полотна отрезка между обрезками у узлов: в каждом сечении цвет — по клетке под осью.
func _band_mesh(grid: CityGrid, graph: RoadGraph, segment: RoadGraph.Segment) -> ArrayMesh:
	var curve: PackedVector2Array = graph.curve(segment)
	var table: PackedFloat32Array = RoadGeometry.arc_table(curve[0], curve[1], curve[2])
	var trims: Vector2 = _trims.get(segment.id, Vector2.ZERO)
	var from: float = trims.x
	var to: float = table[table.size() - 1] - trims.y
	if to - from < 0.05:
		return null
	var half: float = RoadTypes.HALF_WIDTH.get(segment.type, 1.0)
	var steps: int = maxi(1, ceili((to - from) / BAND_STEP))
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var left := Vector3.ZERO
	var right := Vector3.ZERO
	var color := Color()
	for i: int in steps + 1:
		var t: float = RoadGeometry.t_at(table, lerpf(from, to, float(i) / steps))
		var p: Vector2 = RoadGraph.bezier(curve[0], curve[1], curve[2], t)
		var tangent: Vector2 = RoadGraph.bezier_tangent(curve[0], curve[1], curve[2], t)
		if tangent.length_squared() < 1e-10:
			tangent = curve[2] - curve[0]
		var across: Vector2 = Vector2(tangent.y, -tangent.x).normalized() * half
		var next_left := Vector3(p.x + across.x, BAND_Y, p.y + across.y)
		var next_right := Vector3(p.x - across.x, BAND_Y, p.y - across.y)
		var next_color: Color = _load_color(grid, p)
		if i > 0:
			points.append_array([left, right, next_right, left, next_right, next_left])
			colors.append_array([color, color, next_color, color, next_color, next_color])
		left = next_left
		right = next_right
		color = next_color
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_band(id: int, mesh: ArrayMesh) -> void:
	if mesh == null:
		if _bands.has(id):
			_bands[id].queue_free()
			_bands.erase(id)
		return
	if not _bands.has(id):
		var instance := MeshInstance3D.new()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.material_override = _band_material
		add_child(instance)
		_bands[id] = instance
	_bands[id].mesh = mesh


func _tint(color: Color) -> StandardMaterial3D:
	if color.a <= 0.0:
		return null
	if not _tints.has(color):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		_tints[color] = material
	return _tints[color]


## Цвет подкраски полотна в клетке дороги (для проверок); прозрачный — не подкрашено.
func tint_at(cell: Vector2i) -> Color:
	for id: int in GameState.grid.roads.owners_of(cell):
		if _bands.has(id):
			return _load_color(GameState.grid, RoadGraph.cell_center(cell))
		if _segments.has(id) and _segments[id].material_overlay != null:
			return (_segments[id].material_overlay as StandardMaterial3D).albedo_color
	return Color(0, 0, 0, 0)


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _put(instances: Dictionary[int, MeshInstance3D], id: int, st: SurfaceTool) -> void:
	var mesh: ArrayMesh = st.commit()
	if not instances.has(id):
		var instance := MeshInstance3D.new()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.material_override = RoadGeometry.material()
		add_child(instance)
		instances[id] = instance
	instances[id].mesh = mesh if mesh.get_surface_count() > 0 else null


func _drop_missing(instances: Dictionary[int, MeshInstance3D], keys: Dictionary[int, int], alive: Dictionary) -> void:
	for id: int in instances.keys():
		if not alive.has(id):
			instances[id].queue_free()
			instances.erase(id)
			keys.erase(id)


## Сколько отрезков и узлов нарисовано (для проверок).
func segment_mesh_count() -> int:
	var count: int = 0
	for instance: MeshInstance3D in _segments.values():
		if instance.mesh != null:
			count += 1
	return count


func node_mesh_count() -> int:
	var count: int = 0
	for instance: MeshInstance3D in _nodes.values():
		if instance.mesh != null:
			count += 1
	return count
