extends Node3D
## Значки над зданиями без света или воды (как в SimCity): красная булавка с молнией или каплей —
## модели из Blender (tools/blender/make_badges.py). Значок висит над крышей, всегда смотрит в камеру
## и чуть покачивается; нет ни света, ни воды — два значка рядом. Стройплощадкам значки не нужны.
## Обновляется по stats_changed — после каждого пересчёта света и воды (Utilities.distribute).

const POWER_MODEL: PackedScene = preload("res://assets/models/blender/badges/badge_power.glb")
const WATER_MODEL: PackedScene = preload("res://assets/models/blender/badges/badge_water.glb")
## Высота значка, метры (модель — 1 м).
const SIZE: float = 1.4
## Зазор между крышей и остриём значка, метры.
const GAP: float = 0.3
## Два значка рядом: сдвиг каждого вбок, метры.
const PAIR_OFFSET: float = 0.66
## Поворот к камере (как билборд) и покачивание. INSTANCE_CUSTOM: r — фаза покачивания,
## g — место в паре: 0 — слева, 0.5 — один значок, 1 — справа.
const SHADER: String = """
shader_type spatial;
render_mode shadows_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float pair_offset = 0.66;
uniform float glow = 0.3;
const float BOB_HEIGHT = 0.15;
const float BOB_SPEED = 2.4;

void vertex() {
	VERTEX.x += (INSTANCE_CUSTOM.g - 0.5) * 2.0 * pair_offset;
	VERTEX.y += (sin(TIME * BOB_SPEED + INSTANCE_CUSTOM.r * TAU) * 0.5 + 0.5) * BOB_HEIGHT;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.5;
	EMISSION = albedo.rgb * glow;
}
"""

var _shader := Shader.new()
var _power := MultiMeshInstance3D.new()
var _water := MultiMeshInstance3D.new()


func _ready() -> void:
	_shader.code = SHADER
	_setup(_power, POWER_MODEL)
	_setup(_water, WATER_MODEL)
	Events.stats_changed.connect(refresh)
	refresh()


## Сколько значков сейчас висит: [свет, вода] (для проверок).
func counts() -> Vector2i:
	return Vector2i(_power.multimesh.instance_count, _water.multimesh.instance_count)


## Над какими зданиями висят значки — по флагам света и воды из последнего пересчёта.
func refresh() -> void:
	var grid: CityGrid = GameState.grid
	var power: Array[Array] = []
	var water: Array[Array] = []
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			continue
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		var no_power: bool = data.power_use > 0 and not building.powered
		var no_water: bool = data.water_use > 0 and not building.has_water
		if not no_power and not no_water:
			continue
		var top: Vector3 = grid.footprint_center(building.cell, building.size) \
				+ Vector3(0.0, BuildingMeshes.height_of(data) + GAP, 0.0)
		var phase: float = fposmod(building.id * 0.618034, 1.0)
		var pair: bool = no_power and no_water
		if no_power:
			power.append([top, Color(phase, 0.0 if pair else 0.5, 0.0, 0.0)])
		if no_water:
			water.append([top, Color(phase, 1.0 if pair else 0.5, 0.0, 0.0)])
	_write(_power, power)
	_write(_water, water)


func _setup(layer: MultiMeshInstance3D, scene: PackedScene) -> void:
	var mesh: ArrayMesh = ModelLoader.merge(scene, Transform3D(Basis.from_scale(Vector3.ONE * SIZE), Vector3.ZERO))
	# Цвета частей — из материалов модели; шейдер у всех один.
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface) as BaseMaterial3D
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter("albedo", source.albedo_color if source != null else Color.WHITE)
		material.set_shader_parameter("pair_offset", PAIR_OFFSET)
		mesh.surface_set_material(surface, material)
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = mesh
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Шейдер разворачивает значок к камере — запас, чтобы его не отсекало по краю экрана.
	layer.extra_cull_margin = SIZE
	add_child(layer)


## badges: [позиция острия, INSTANCE_CUSTOM].
func _write(layer: MultiMeshInstance3D, badges: Array[Array]) -> void:
	var multimesh: MultiMesh = layer.multimesh
	multimesh.instance_count = badges.size()
	for i: int in badges.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, badges[i][0]))
		multimesh.set_instance_custom_data(i, badges[i][1])
