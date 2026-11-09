extends Node3D
## Полотно дорог по графу GameState.grid.roads (RoadGeometry): по мешу на отрезок и на перекрёсток
## или тупик. Перестраивает только то, у чего изменилась форма (концы, кривая, тип, обрезки у узлов).
## До 2026-11-09 — GridMap из кусков Kenney по маске соседей клетки.

var _segments: Dictionary[int, MeshInstance3D] = {}
var _segment_keys: Dictionary[int, int] = {}
var _nodes: Dictionary[int, MeshInstance3D] = {}
var _node_keys: Dictionary[int, int] = {}
var _seen_grid: CityGrid = null
var _seen_version: int = -1


func _ready() -> void:
	Events.grid_reset.connect(_clear)


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
