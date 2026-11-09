extends Node3D
## Светофоры на перекрёстках (TrafficLights.is_junction): два столба Kenney на углах и над каждым —
## огонёк своей оси, красный или зелёный. Ведёт часы светофоров TrafficLights.time (на паузе стоят),
## по ним же машинки стоят на красный.

const MODEL: String = "res://assets/models/kenney/roads/traffic-light.glb"
const MODEL_SCALE: float = 2.0
## Столб дальше середины тротуара от узла на столько (по каждой оси), м: там скруглённый угол.
const CORNER: float = 0.12
const LAMP_SIZE := Vector3(0.12, 0.12, 0.12)
const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.2, 1.0, 0.35)
const AMBER := Color(1.0, 0.75, 0.1)

var _poles := MultiMeshInstance3D.new()
var _lamps := MultiMeshInstance3D.new()
## Перекрёстки и их оси по порядку огоньков: [клетка, ось].
var _lights: Array[Array] = []
var _seen_grid: CityGrid = null
var _seen_roads_version: int = -1
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
	if grid != _seen_grid or grid.roads_version != _seen_roads_version:
		_rebuild(grid)
	for i: int in _lights.size():
		_lamps.multimesh.set_instance_color(i, _lamp_color(_lights[i][0], _lights[i][1]))


## Огонёк оси: зелёный, жёлтый (перед красным) или красный.
func _lamp_color(cell: Vector2i, axis: int) -> Color:
	if TrafficLights.is_green(cell, axis):
		return GREEN if TrafficLights.is_green(cell, axis, TrafficLights.time + TrafficLights.ALL_RED) else AMBER
	return RED


func _rebuild(grid: CityGrid) -> void:
	_seen_grid = grid
	_seen_roads_version = grid.roads_version
	_lights.clear()
	var poles: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	for cell: Vector2i in grid.road_cells:
		if not TrafficLights.is_junction(grid, cell):
			continue
		# Столб — на углу тротуара перекрёстка: середина тротуара и чуть дальше от узла.
		var road_type: int = grid.get_road_type(cell)
		var half: float = (RoadTypes.ASPHALT_HALF.get(road_type, 0.72) + RoadTypes.HALF_WIDTH.get(road_type, 1.0)) * 0.5 + CORNER
		var point: Vector2 = grid.roads.anchor(cell)
		var center := Vector3(point.x, 0.0, point.y)
		# Ось N–S — столб на юго-восточном углу, ось E–W — на северо-западном.
		for axis: int in 2:
			var corner := Vector3(half, 0.0, half) if axis == 0 else Vector3(-half, 0.0, -half)
			var basis := Basis(Vector3.UP, PI * 0.25 + (PI if axis == 1 else 0.0))
			poles.append(Transform3D(basis, center + corner))
			lamps.append(Transform3D(Basis.IDENTITY, center + corner + Vector3.UP * _lamp_height))
			_lights.append([cell, axis])
	_poles.multimesh.instance_count = poles.size()
	for i: int in poles.size():
		_poles.multimesh.set_instance_transform(i, poles[i])
	_lamps.multimesh.instance_count = lamps.size()
	for i: int in lamps.size():
		_lamps.multimesh.set_instance_transform(i, lamps[i])


## Сколько перекрёстков со светофорами (для проверок).
func junction_count() -> int:
	return _lights.size() / 2
