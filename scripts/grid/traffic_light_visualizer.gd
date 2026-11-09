extends Node3D
## Светофоры на перекрёстках (TrafficLights.is_junction): у каждого подхода (отрезка графа) — столб
## Kenney справа на тротуаре у стоп-линии и огонёк фазы этого подхода (TrafficLights.approach_green):
## зелёный, жёлтый перед красным или красный. Ведёт часы светофоров TrafficLights.time (на паузе
## стоят), по ним же машинки стоят на красный.

const MODEL: String = "res://assets/models/kenney/roads/traffic-light.glb"
const MODEL_SCALE: float = 2.0
const LAMP_SIZE := Vector3(0.12, 0.12, 0.12)
const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.2, 1.0, 0.35)
const AMBER := Color(1.0, 0.75, 0.1)

var _poles := MultiMeshInstance3D.new()
var _lamps := MultiMeshInstance3D.new()
## Подходы по порядку огоньков: [узел, отрезок].
var _lights: Array[Vector2i] = []
var _junctions: int = 0
var _seen_grid: CityGrid = null
var _seen_roads_version: int = -1
var _seen_graph_version: int = -1
var _lamp_height: float = 1.0


func _ready() -> void:
	_poles.multimesh = MultiMesh.new()
	_poles.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	if ResourceLoader.exists(MODEL):
		var scene: PackedScene = load(MODEL)
		_poles.multimesh.mesh = ModelLoader.fitted(scene, MODEL_SCALE, 0)
		_lamp_height = ModelLoader.bounds(scene).size.y * MODEL_SCALE + LAMP_SIZE.y * 0.5
	_poles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_poles)
	var lamp := BoxMesh.new()
	lamp.size = LAMP_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	lamp.material = material
	_lamps.multimesh = MultiMesh.new()
	_lamps.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_lamps.multimesh.use_colors = true
	_lamps.multimesh.mesh = lamp
	_lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamps)


func _process(delta: float) -> void:
	TrafficLights.time += delta * SimClock.speed
	var grid: CityGrid = GameState.grid
	grid.roads.sync(grid)
	if grid != _seen_grid or grid.roads_version != _seen_roads_version or grid.roads.version != _seen_graph_version:
		_rebuild(grid)
	for i: int in _lights.size():
		_lamps.multimesh.set_instance_color(i, _lamp_color(grid.roads, _lights[i].x, _lights[i].y))


## Огонёк подхода: зелёный, жёлтый (перед красным) или красный.
func _lamp_color(graph: RoadGraph, node: int, segment: int) -> Color:
	if TrafficLights.approach_green(graph, node, segment):
		return GREEN if TrafficLights.approach_green(graph, node, segment, TrafficLights.time + TrafficLights.ALL_RED) else AMBER
	return RED


func _rebuild(grid: CityGrid) -> void:
	_seen_grid = grid
	_seen_roads_version = grid.roads_version
	_lights.clear()
	_junctions = 0
	var graph: RoadGraph = grid.roads
	graph.sync(grid)
	_seen_graph_version = graph.version
	var poles: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	for node: RoadGraph.RoadNode in graph.nodes.values():
		if node.segments.size() < 3 or not TrafficLights.is_junction(grid, RoadGraph.cell_of(node.pos)):
			continue
		_junctions += 1
		for id: int in node.segments:
			var segment: RoadGraph.Segment = graph.segments[id]
			var s: float = RoadRoute.trim(graph, grid, node.id, id) + RoadRoute.STOP_BACK
			var frame: PackedVector2Array = RoadGeometry.frame_from(graph, segment, node.id, s)
			# Едем к узлу против направления из узла; столб — справа, на середине тротуара.
			var into: Vector2 = -frame[1]
			var half: float = (RoadTypes.ASPHALT_HALF.get(segment.type, 0.72) + RoadTypes.HALF_WIDTH.get(segment.type, 1.0)) * 0.5
			var point: Vector2 = frame[0] + Vector2(-into.y, into.x) * half
			var at := Vector3(point.x, 0.0, point.y)
			poles.append(Transform3D(Basis(Vector3.UP, PI * 0.25 + atan2(-into.x, -into.y)), at))
			lamps.append(Transform3D(Basis.IDENTITY, at + Vector3.UP * _lamp_height))
			_lights.append(Vector2i(node.id, id))
	_poles.multimesh.instance_count = poles.size()
	for i: int in poles.size():
		_poles.multimesh.set_instance_transform(i, poles[i])
	_lamps.multimesh.instance_count = lamps.size()
	for i: int in lamps.size():
		_lamps.multimesh.set_instance_transform(i, lamps[i])


## Сколько перекрёстков со светофорами (для проверок).
func junction_count() -> int:
	return _junctions
