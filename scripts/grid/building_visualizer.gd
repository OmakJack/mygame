extends Node3D
## Показывает здания из GameState.grid: по мультимешу на тип здания. Стройку (construction_ticks > 0)
## рисует ConstructionVisualizer; здесь у неё только номер куска (_construction_item) для get_cell_item.
## Мультимеш, а не GridMap, — чтобы у каждого здания был свой цвет (BuildingPalette, INSTANCE_CUSTOM).
## Поворот — по BuildingInstance.orientation (по часовой, как у дорог).
## Брошенные здания (Decay) — в своём слое на тип (создаётся при первом брошенном доме) с наложенным
## материалом упадка: тот же дом, но темнее, бурее, с потёками по стенам и грязью у земли.

## Наложение упадка: умножает цвет дома (blend_mul) — тусклый бурый тон, вертикальные потёки на стенах,
## пятна на крыше, грязь снизу. Работает поверх любых материалов (Kenney, пак Gemini, башни из кода).
const DECAY_SHADER: String = """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 tone = vec3(0.56, 0.5, 0.44);
	float wall = 1.0 - smoothstep(0.5, 0.8, abs(world_normal.y));
	// Потёки: узкие вертикальные полосы вдоль стены, к низу темнее.
	float across = dot(world_pos.xz, vec2(world_normal.z, -world_normal.x));
	float streak = hash(vec2(floor(across * 7.0), 3.0));
	float drip = step(0.55, streak) * (0.5 + 0.5 * hash(vec2(floor(across * 7.0), 9.0)));
	float streaks = wall * drip * (0.18 + 0.12 * clamp(1.0 - fract(world_pos.y * 0.6), 0.0, 1.0));
	// Грязь у земли и пятна на крыше.
	float grime = (1.0 - smoothstep(0.0, 0.9, world_pos.y)) * 0.22;
	float moss = (1.0 - wall) * step(0.6, hash(floor(world_pos.xz * 2.5))) * 0.2;
	ALBEDO = tone * (1.0 - streaks) * (1.0 - grime) * (1.0 - moss);
}
"""

## Номер «куска» стройплощадки — после всех типов (его слой пустой).
var _construction_item: int = 0
var _item_for_type: Dictionary[StringName, int] = {}
var _layers: Array[MultiMeshInstance3D] = []
## Клетка → номер куска, который там нарисован (все клетки многоклеточного здания).
var _item_at: Dictionary[Vector2i, int] = {}
## Клетка → id здания, которое там нарисовано.
var _building_at_vis: Dictionary[Vector2i, int] = {}
## id здания → номер куска, которым оно сейчас нарисовано.
var _drawn_item: Dictionary[int, int] = {}
## id здания → массив его клеток на момент отрисовки.
var _drawn_cells: Dictionary[int, Array] = {}
## Номер куска → список id зданий в этом слое.
var _ids_of: Array[Array] = []
## Номер первого куска брошенных зданий: брошенный дом типа N — кусок _abandoned_base + N.
var _abandoned_base: int = 0
var _decay_material := ShaderMaterial.new()


func _ready() -> void:
	var types: Array[BuildingData] = BuildingCatalog.all_types()
	for item: int in types.size():
		_item_for_type[types[item].id] = item
		_add_layer(BuildingPalette.convert(BuildingMeshes.mesh_for(types[item])))
	_construction_item = types.size()
	_add_layer(ArrayMesh.new())
	# Слои брошенных зданий — пустые места до первого брошенного дома такого типа (_layer_for).
	_abandoned_base = _layers.size()
	var decay_shader := Shader.new()
	decay_shader.code = DECAY_SHADER
	_decay_material.shader = decay_shader
	for item: int in types.size():
		_layers.append(null)
		_ids_of.append([])
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _add_layer(mesh: Mesh) -> void:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = mesh
	add_child(layer)
	_layers.append(layer)
	_ids_of.append([])


## Номер куска в клетке (как GridMap.get_cell_item); −1 — пусто.
func get_cell_item(map_cell: Vector3i) -> int:
	return _item_at.get(Vector2i(map_cell.x, map_cell.z), -1)


## Клетки со зданиями (как GridMap.get_used_cells).
func get_used_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: Vector2i in _item_at:
		result.append(Vector3i(cell.x, 0, cell.y))
	return result


func _rebuild() -> void:
	_item_at.clear()
	_building_at_vis.clear()
	_drawn_item.clear()
	_drawn_cells.clear()
	for ids: Array in _ids_of:
		ids.clear()
	for building: BuildingInstance in GameState.grid.buildings.values():
		_register_building(building)
	for item: int in _layers.size():
		_write_layer(item)


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	var dirty: Dictionary[int, bool] = {}
	var affected: Dictionary[int, bool] = {}
	var grid: CityGrid = GameState.grid
	for cell: Vector2i in cells:
		if not grid.is_in_bounds(cell):
			continue
		if _building_at_vis.has(cell):
			affected[_building_at_vis[cell]] = true
		var current: BuildingInstance = grid.get_building_at(cell)
		if current != null:
			affected[current.id] = true
	for id: int in affected:
		var building: BuildingInstance = grid.buildings.get(id)
		var new_item: int = _item_for(building) if building != null else -1
		if _drawn_item.has(id):
			var old_item: int = _drawn_item[id]
			if building != null and new_item == old_item and building.cells() == _drawn_cells[id]:
				dirty[old_item] = true
				continue
			_unregister_building(id)
			dirty[old_item] = true
		if building != null and new_item >= 0:
			_register_building(building)
			dirty[new_item] = true
	for item: int in dirty:
		_write_layer(item)


func _register_building(building: BuildingInstance) -> void:
	var item: int = _item_for(building)
	if item < 0:
		return
	var occupied: Array[Vector2i] = building.cells()
	_drawn_item[building.id] = item
	_drawn_cells[building.id] = occupied
	_ids_of[item].append(building.id)
	for c: Vector2i in occupied:
		_building_at_vis[c] = building.id
		_item_at[c] = item


func _unregister_building(id: int) -> void:
	var old_item: int = _drawn_item[id]
	_ids_of[old_item].erase(id)
	for c: Vector2i in _drawn_cells[id]:
		if _building_at_vis.get(c, -1) == id:
			_building_at_vis.erase(c)
			_item_at.erase(c)
	_drawn_item.erase(id)
	_drawn_cells.erase(id)


func _item_for(building: BuildingInstance) -> int:
	if building.construction_ticks > 0:
		return _construction_item
	if not _item_for_type.has(building.type_id):
		push_warning("BuildingVisualizer: неизвестный тип %s" % building.type_id)
		return -1
	if building.abandoned:
		return _abandoned_base + _item_for_type[building.type_id]
	return _item_for_type[building.type_id]


## Слой куска; слой брошенных зданий типа создаётся при первом таком доме: тот же меш и наложение упадка.
func _layer_for(item: int) -> MultiMeshInstance3D:
	if _layers[item] == null:
		var layer := MultiMeshInstance3D.new()
		layer.multimesh = MultiMesh.new()
		layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		layer.multimesh.use_custom_data = true
		layer.multimesh.mesh = _layers[item - _abandoned_base].multimesh.mesh
		layer.material_overlay = _decay_material
		add_child(layer)
		_layers[item] = layer
	return _layers[item]


## Переписывает все экземпляры куска: позиция (по центру участка), поворот и цвет каждого здания.
func _write_layer(item: int) -> void:
	var grid: CityGrid = GameState.grid
	var ids: Array = _ids_of[item]
	if _layers[item] == null and ids.is_empty():
		return
	var multimesh: MultiMesh = _layer_for(item).multimesh
	if item == _construction_item:
		multimesh.instance_count = 0
		return
	multimesh.instance_count = ids.size()
	for i: int in ids.size():
		var building: BuildingInstance = grid.buildings.get(ids[i])
		if building == null:
			continue
		multimesh.set_instance_transform(i, grid.building_transform(building))
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		multimesh.set_instance_custom_data(i, BuildingPalette.custom_for(building, data) if data != null else Color())
