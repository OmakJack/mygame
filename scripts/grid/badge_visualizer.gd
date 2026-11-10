extends Node3D
## Значки над зданиями (как в SimCity) — модели из Blender (tools/blender/make_badges.py):
## красная булавка с молнией (нет света), каплей (нет воды) или перечёркнутой дорогой (нет дороги —
## скоро опустеет, Decay), тёмная с досками крест-накрест — здание брошено. Значок висит над крышей,
## всегда смотрит в камеру и чуть покачивается; нет ни света, ни воды — два значка рядом. Без дороги —
## только значок дороги (свет и вода идут по ней), у брошенного — только его значок.
## Стройплощадкам значки не нужны. Обновляется по stats_changed — после каждого пересчёта.

enum Kind { POWER, WATER, ROAD, ABANDONED }

const MODELS: Dictionary[Kind, PackedScene] = {
	Kind.POWER: preload("res://assets/models/blender/badges/badge_power.glb"),
	Kind.WATER: preload("res://assets/models/blender/badges/badge_water.glb"),
	Kind.ROAD: preload("res://assets/models/blender/badges/badge_road.glb"),
	Kind.ABANDONED: preload("res://assets/models/blender/badges/badge_abandoned.glb"),
}
## Высота значка, метры (модель — 1 м).
const SIZE: float = 1.4
## Зазор между крышей и остриём значка, метры.
const GAP: float = 0.3
## Два значка рядом: сдвиг каждого вбок, метры.
const PAIR_OFFSET: float = 0.66
## Сдвиг вбок в шейдере: (INSTANCE_CUSTOM.g − 0.5) · SPREAD метров; g = 0.5 — значок по центру.
const SPREAD: float = 4.0
## Поворот к камере (как билборд) и покачивание. INSTANCE_CUSTOM: r — фаза покачивания, g — сдвиг вбок.
const SHADER: String = """
shader_type spatial;
render_mode shadows_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float spread = 4.0;
uniform float glow = 0.3;
const float BOB_HEIGHT = 0.15;
const float BOB_SPEED = 2.4;

void vertex() {
	VERTEX.x += (INSTANCE_CUSTOM.g - 0.5) * spread;
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
var _layers: Dictionary[Kind, MultiMeshInstance3D] = {}
# Для проверок.
var _power: MultiMeshInstance3D
var _water: MultiMeshInstance3D


func _ready() -> void:
	_shader.code = SHADER
	for kind: Kind in MODELS:
		_layers[kind] = _make_layer(MODELS[kind])
	_power = _layers[Kind.POWER]
	_water = _layers[Kind.WATER]
	Events.stats_changed.connect(refresh)
	refresh()


## Сколько значков сейчас висит: [свет, вода] (для проверок).
func counts() -> Vector2i:
	return Vector2i(_power.multimesh.instance_count, _water.multimesh.instance_count)


## Сколько значков упадка: [нет дороги, брошено] (для проверок).
func decay_counts() -> Vector2i:
	return Vector2i(_layers[Kind.ROAD].multimesh.instance_count, _layers[Kind.ABANDONED].multimesh.instance_count)


## Над какими зданиями висят значки — по флагам света и воды из последнего пересчёта и по упадку.
func refresh() -> void:
	var grid: CityGrid = GameState.grid
	var badges: Dictionary[Kind, Array] = {}
	for kind: Kind in MODELS:
		badges[kind] = []
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			continue
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		var kinds: Array[Kind] = []
		if building.abandoned:
			kinds.append(Kind.ABANDONED)
		elif building.no_road_ticks > 0:
			kinds.append(Kind.ROAD)
		else:
			if data.power_use > 0 and not building.powered:
				kinds.append(Kind.POWER)
			if data.water_use > 0 and not building.has_water:
				kinds.append(Kind.WATER)
		if kinds.is_empty():
			continue
		var top: Vector3 = grid.building_transform(building).origin \
				+ Vector3(0.0, BuildingMeshes.height_of(data) + GAP, 0.0)
		var phase: float = fposmod(building.id * 0.618034, 1.0)
		for i: int in kinds.size():
			# Один значок — по центру, два — по PAIR_OFFSET в стороны.
			var offset: float = (i - (kinds.size() - 1) * 0.5) * 2.0 * PAIR_OFFSET
			badges[kinds[i]].append([top, Color(phase, 0.5 + offset / SPREAD, 0.0, 0.0)])
	for kind: Kind in MODELS:
		_write(_layers[kind], badges[kind])


func _make_layer(scene: PackedScene) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	var mesh: ArrayMesh = ModelLoader.merge(scene, Transform3D(Basis.from_scale(Vector3.ONE * SIZE), Vector3.ZERO))
	# Цвета частей — из материалов модели; шейдер у всех один.
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface) as BaseMaterial3D
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter("albedo", source.albedo_color if source != null else Color.WHITE)
		material.set_shader_parameter("spread", SPREAD)
		mesh.surface_set_material(surface, material)
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = mesh
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Шейдер разворачивает значок к камере — запас, чтобы его не отсекало по краю экрана.
	layer.extra_cull_margin = SIZE + SPREAD * 0.5
	add_child(layer)
	return layer


## badges: [позиция острия, INSTANCE_CUSTOM].
func _write(layer: MultiMeshInstance3D, badges: Array) -> void:
	var multimesh: MultiMesh = layer.multimesh
	multimesh.instance_count = badges.size()
	for i: int in badges.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, badges[i][0]))
		multimesh.set_instance_custom_data(i, badges[i][1])
