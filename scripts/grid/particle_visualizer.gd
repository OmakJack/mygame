class_name ParticleVisualizer
extends Node3D
## Эффекты из пака Argon (assets/models/blender/particles/, tools/blender/pack_particles.py): дым из труб
## заводов и ТЭЦ, печной дымок домов и пекарен, пар кофеен и вентиляции, фонтаны, листва и птицы
## в парках, пыль и сварка на стройках; вспышки — пыль с обломками, когда здание снесли, и салют,
## когда дом достроили на уровень выше. Только визуал, ничего не сохраняется.
## Каждый эффект — один составной меш (клубы, капли, искры) и один MultiMesh на весь город; анимация —
## в вершинном шейдере по запечённым в меш атрибутам: UV.x — фаза t от устья к верхушке, UV.y — зерно
## элемента, NORMAL — наружу от центра клуба. INSTANCE_CUSTOM: r — фаза источника, b — начало вспышки.
## Время эффектов (fx_time) на паузе стоит; вспышки идут по своим часам (fx_clock) — снос на паузе виден.
## Дым идёт только у работающих зданий: не стройка, не брошено, есть свет. Ветер у всего города один — по +X.
## Где труба: у зданий из таблицы манифеста — её точки (сверены с мешем: дальше SNAP от вершин — нет),
## у остальных — середина самых верхних вершин меша (chimney_top), если вершина узкая, как труба.

enum Anim { PLUME, SWIRL, FLICKER, SPARKS, BILLOW, FOUNTAIN, ORBIT, LEAVES, DUST_BURST, CONFETTI }

const DIR := "res://assets/models/blender/particles/"
const MANIFEST := DIR + "manifest.json"
## Эффект: анимация, скорость, раскачивание, подъём, пульсация клубов, свечение, длительность вспышки, с.
## Свечение у дыма — только у горячих частей (отблеск жара у устья): WARM_GLOW.
const EFFECTS: Dictionary[StringName, Dictionary] = {
	&"fx_smoke_chimney_light": {"anim": Anim.PLUME, "speed": 1.5, "sway": 0.12, "bob": 0.06, "pulse": 0.03},
	&"fx_smoke_factory_heavy": {"anim": Anim.PLUME, "speed": 1.2, "sway": 0.2, "bob": 0.08, "pulse": 0.05},
	&"fx_smoke_twin_stacks": {"anim": Anim.PLUME, "speed": 1.2, "sway": 0.2, "bob": 0.08, "pulse": 0.05},
	&"fx_steam_cooling_tower": {"anim": Anim.PLUME, "speed": 0.9, "sway": 0.14, "bob": 0.1, "pulse": 0.06},
	&"fx_steam_vent_puff": {"anim": Anim.PLUME, "speed": 2.0, "sway": 0.08, "bob": 0.05, "pulse": 0.03},
	&"fx_cafe_aroma_swirl": {"anim": Anim.SWIRL, "speed": 1.1, "bob": 0.04, "pulse": 0.02},
	&"fx_fire_refinery_flare": {"anim": Anim.FLICKER, "speed": 1.0, "sway": 0.05, "pulse": 0.03, "glow": 1.4},
	&"fx_sparks_welding_burst": {"anim": Anim.SPARKS, "speed": 1.6, "pulse": 0.02, "glow": 1.8},
	&"fx_dust_construction_site": {"anim": Anim.BILLOW, "speed": 1.0, "sway": 0.1, "pulse": 0.04},
	&"fx_fountain_park_jets": {"anim": Anim.FOUNTAIN, "speed": 1.4, "pulse": 0.02, "glow": 0.15},
	&"fx_nature_falling_leaves": {"anim": Anim.LEAVES, "speed": 1.0, "sway": 0.3, "bob": 0.12},
	&"fx_nature_flock_birds": {"anim": Anim.ORBIT, "speed": 1.0, "bob": 0.12},
	&"fx_dust_bulldoze_burst": {"anim": Anim.DUST_BURST, "duration": 1.3, "pulse": 0.04},
	&"fx_celebrate_levelup_confetti": {"anim": Anim.CONFETTI, "duration": 2.2, "glow": 0.35},
}
## Отблеск жара: части дыма тёплого цвета (красный заметно больше синего) светятся.
const WARM_GLOW: float = 1.3
## Точка из таблицы манифеста дальше этого от вершин меша здания — не та, берём chimney_top.
const SNAP: float = 0.3
## Верх меша «узкий, как труба», если верхние вершины укладываются в этот размер по X и Z, м.
const STACK_SPREAD: float = 0.95
## Какая доля домов (по id) топит печь, а у офисов и торговых домов работает вентиляция на крыше.
const HOUSE_SMOKE_SHARE: float = 0.4
const VENT_SHARE: float = 0.35
## Птицы — над каждым N-м парком; высота стайки над парком, м.
const BIRDS_EVERY: int = 2
const BIRDS_HEIGHT: float = 2.2
## Масштабы эффектов у источников.
const HOUSE_SMOKE_SCALE: float = 0.75
const FOUNTAIN_SCALE: float = 0.55
const LEAVES_SCALE: float = 0.7
## Стройка: пыль до этой доли готовности, искры — у зданий не ниже SPARKS_MIN_HEIGHT, пока растут стены.
const DUST_UNTIL: float = 0.55
const SPARKS_MIN_HEIGHT: float = 1.8
## Стены растут в этих долях стройки (как в ConstructionVisualizer).
const WALLS_FROM: float = 0.12
const WALLS_TO: float = 0.9
## Не дальше этого от камеры эффекты не рисуются, м.
const VISIBLE_RANGE: float = 160.0

const SHADER: String = """
shader_type spatial;
render_mode shadows_disabled;
global uniform float fx_time;
global uniform float fx_clock;
uniform vec4 albedo : source_color = vec4(1.0);
uniform int anim = 0;
uniform float glow = 0.0;
uniform float speed = 1.5;
uniform float sway = 0.15;
uniform float bob = 0.08;
uniform float pulse = 0.04;
uniform float duration = 1.4;

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void vertex() {
	float t = UV.x;
	float seed = UV.y;
	float tm = fx_time * speed + INSTANCE_CUSTOM.r * TAU;
	if (anim == 0) {
		// Шлейф: бегущая волна подъёма и сноса по ветру, к верхушке сильнее; клубы дышат.
		VERTEX.x += sin(tm - t * 4.5 + seed * 2.0) * sway * t;
		VERTEX.z += cos(tm * 0.85 - t * 4.0 + seed * TAU) * sway * 0.65 * t;
		VERTEX.y += sin(tm * 1.2 - t * 5.0 + seed * TAU) * bob * (0.15 + t);
		VERTEX += NORMAL * (sin(tm * 1.5 + seed * TAU) * pulse * (0.4 + t));
	} else if (anim == 1) {
		// Спираль аромата: вращается вокруг оси, верх быстрее.
		VERTEX = rot_y(VERTEX, tm * (0.6 + t));
		NORMAL = rot_y(NORMAL, tm * (0.6 + t));
		VERTEX.y += sin(tm * 1.3 + seed * TAU) * bob * t;
		VERTEX += NORMAL * sin(tm * 1.7 + seed * TAU) * pulse;
	} else if (anim == 2) {
		// Пламя: дрожит и вытягивается.
		float f = sin(tm * 7.0 + seed * TAU) * 0.5 + sin(tm * 11.0 + seed * 5.0) * 0.3;
		VERTEX.y *= 1.0 + f * 0.12 * t;
		VERTEX.x += sin(tm * 3.0 + t * 3.0) * sway * t;
		VERTEX += NORMAL * f * pulse;
	} else if (anim == 3) {
		// Сварка: искры снова и снова разлетаются от дуги и падают.
		float age = fract(fx_time * speed * 0.5 + INSTANCE_CUSTOM.r + seed * 0.15);
		VERTEX *= 0.35 + age * 0.9;
		VERTEX.y -= age * age * 0.35 * t;
		VERTEX += NORMAL * (-age * pulse);
	} else if (anim == 4) {
		// Пыль у земли: медленно клубится и стелется.
		VERTEX.xz *= 1.0 + sin(tm * 0.7 + seed * TAU) * 0.08;
		VERTEX.x += sin(tm * 0.5 + seed * 3.0) * sway * t;
		VERTEX += NORMAL * sin(tm + seed * TAU) * pulse;
	} else if (anim == 5) {
		// Фонтан: струи то выше, то ниже.
		float p = sin(tm * 2.0 + seed * 1.2) * 0.5 + 0.5;
		VERTEX.y *= 0.8 + 0.3 * p;
		VERTEX += NORMAL * sin(tm * 3.0 + seed * TAU) * pulse;
	} else if (anim == 6) {
		// Стайка кружит над парком, птицы машут крыльями.
		VERTEX = rot_y(VERTEX, tm * 0.5);
		NORMAL = rot_y(NORMAL, tm * 0.5);
		VERTEX.y += sin(tm * 1.1 + seed * TAU) * bob;
		VERTEX.y += sin(tm * 9.0 + seed * TAU) * 0.05 * abs(NORMAL.x);
	} else if (anim == 7) {
		// Листва кружится и покачивается.
		VERTEX = rot_y(VERTEX, tm * 0.4 + t * 1.5);
		NORMAL = rot_y(NORMAL, tm * 0.4 + t * 1.5);
		VERTEX.y += sin(tm * 0.9 + seed * TAU) * bob;
		VERTEX.x += sin(tm * 1.3 + seed * 5.0) * sway * 0.3;
	} else {
		// Вспышки — один раз: от INSTANCE_CUSTOM.b по часам fx_clock, duration секунд.
		float age = clamp((fx_clock - INSTANCE_CUSTOM.b) / duration, 0.0, 1.0);
		float size = smoothstep(0.0, 0.18, age) * (1.0 - smoothstep(0.6, 1.0, age));
		if (anim == 8) {
			// Пыль сноса: кольцо расходится, обломки взлетают и падают.
			VERTEX.xz *= 0.35 + 0.95 * sqrt(age);
			VERTEX.y += t * age * 0.4 - age * age * 0.3 * seed;
		} else {
			// Салют: звёзды и конфетти взлетают, крутятся и разлетаются.
			VERTEX = rot_y(VERTEX, age * 3.0 + seed);
			VERTEX.xz *= 0.3 + age * 1.1;
			VERTEX.y += age * 0.9 - age * age * 0.5;
		}
		VERTEX *= size;
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.85;
	EMISSION = albedo.rgb * glow;
}
"""

## Один источник эффекта у типа здания: эффект, точка в координатах здания, масштаб.
class Emitter extends RefCounted:
	var effect: StringName
	var local: Vector3
	var scale: float = 1.0

	func _init(effect_id: StringName, at: Vector3, size: float = 1.0) -> void:
		effect = effect_id
		local = at
		scale = size


var _shader := Shader.new()
var _layers: Dictionary[StringName, MultiMeshInstance3D] = {}
## Источники по типу здания (кэш; считаются по мешу один раз).
var _type_emitters: Dictionary[StringName, Array] = {}
## Таблица манифеста: id типа → [[эффект, Vector3], …].
var _explicit: Dictionary[String, Array] = {}
var _dirty: bool = true
## Время эффектов (стоит на паузе) и часы вспышек.
var _fx_time: float = 0.0
var _fx_clock: float = 0.0
## Вспышки: [эффект, позиция, масштаб, начало по fx_clock].
var _bursts: Array[Array] = []
## Что знали о зданиях к прошлому обновлению: id → [середина участка, размер для пыли, уровень готового].
var _seen: Dictionary[int, Array] = {}
var _seen_grid: CityGrid = null
## Стройки с искрами: [id здания, номер экземпляра в слое искр] — высоту искр двигаем каждый кадр.
var _spark_sites: Array[Array] = []


func _ready() -> void:
	# Глобальные часы эффектов fx_time и fx_clock заведены в project.godot ([shader_globals]).
	_shader.code = SHADER
	_load_manifest()
	for effect: StringName in EFFECTS:
		_layers[effect] = _make_layer(effect)
	Events.cells_changed.connect(func(_cells: Array[Vector2i]) -> void: _dirty = true)
	Events.stats_changed.connect(func() -> void: _dirty = true)
	Events.grid_reset.connect(func() -> void:
		_dirty = true
		_bursts.clear())


func _process(delta: float) -> void:
	if SimClock.speed > 0:
		_fx_time += delta
	_fx_clock += delta
	RenderingServer.global_shader_parameter_set(&"fx_time", _fx_time)
	RenderingServer.global_shader_parameter_set(&"fx_clock", _fx_clock)
	var expired: bool = false
	for burst: Array in _bursts:
		if _fx_clock - burst[3] > EFFECTS[burst[0]].duration:
			expired = true
	if expired:
		_bursts = _bursts.filter(func(burst: Array) -> bool: return _fx_clock - burst[3] <= EFFECTS[burst[0]].duration)
		_dirty = true
	if _dirty:
		refresh()
	else:
		_move_sparks()


## Сколько экземпляров у эффекта (для проверок).
func count(effect: StringName) -> int:
	return _layers[effect].multimesh.instance_count if _layers.has(effect) else 0


## Позиции экземпляров эффекта (для проверок).
func positions(effect: StringName) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var multimesh: MultiMesh = _layers[effect].multimesh
	for i: int in multimesh.instance_count:
		result.append(multimesh.get_instance_transform(i).origin)
	return result


## Пересобирает все источники по городу: дым, пар, парки, стройки; вспышки сноса и повышения.
func refresh() -> void:
	_dirty = false
	var grid: CityGrid = GameState.grid
	var items: Dictionary[StringName, Array] = {}
	for effect: StringName in EFFECTS:
		items[effect] = []
	_spark_sites.clear()
	var fresh_grid: bool = grid != _seen_grid
	if fresh_grid:
		_seen.clear()
		_seen_grid = grid
	var park_index: int = 0
	var present: Dictionary[int, bool] = {}
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null:
			continue
		present[building.id] = true
		var xf: Transform3D = grid.building_transform(building)
		var phase: float = fposmod(building.id * 0.618034, 1.0)
		_track(building, data, xf, fresh_grid)
		if building.construction_ticks > 0:
			_add_construction(items, building, data, xf, phase)
			continue
		if building.abandoned:
			continue
		if data.park != BuildingData.Park.NONE:
			_add_park(items, data, xf, phase, park_index)
			park_index += 1
			continue
		# Без света печи, станки и кофемашины не работают.
		if data.power_use > 0 and not building.powered:
			continue
		for emitter: Emitter in _emitters_for(data):
			if not _picked(building, data, emitter):
				continue
			items[emitter.effect].append([xf * emitter.local, emitter.scale, Color(phase, 0.0, 0.0, 0.0)])
	# Пропавшие здания — снесли (бульдозер, перестройка участка): облако пыли с обломками.
	for id: int in _seen.keys():
		if not present.has(id):
			var gone: Array = _seen[id]
			_bursts.append([&"fx_dust_bulldoze_burst", gone[0], gone[1], _fx_clock])
			_seen.erase(id)
	for burst: Array in _bursts:
		items[burst[0]].append([burst[1], burst[2], Color(0.0, 0.0, burst[3], 0.0)])
	for effect: StringName in EFFECTS:
		_write(_layers[effect], items[effect])
	_move_sparks()


## Запоминает здание; дом, достроенный на уровень выше, — салют над крышей.
func _track(building: BuildingInstance, data: BuildingData, xf: Transform3D, fresh_grid: bool) -> void:
	var center: Vector3 = xf.origin
	var dust: float = clampf(sqrt(float(data.area())) * 0.75, 0.7, 2.6)
	var known: Array = _seen.get(building.id, [])
	var level: int = known[2] if not known.is_empty() else -1
	if building.construction_ticks == 0 and not building.abandoned:
		if not fresh_grid and level > 0 and data.level > level and data.zone != CityGrid.Zone.NONE:
			var top := center + Vector3(0.0, BuildingMeshes.height_of(data) + 0.15, 0.0)
			_bursts.append([&"fx_celebrate_levelup_confetti", top, clampf(dust * 0.8, 0.8, 1.6), _fx_clock])
		level = data.level
	_seen[building.id] = [center, dust, level]


## Стройка: пыль у фундамента, пока он и низ стен; у высоких — сварка на верху растущих стен.
func _add_construction(items: Dictionary[StringName, Array], building: BuildingInstance, data: BuildingData,
		xf: Transform3D, phase: float) -> void:
	var p: float = _progress(building)
	var dust: float = clampf(sqrt(float(data.area())) * 0.7, 0.6, 2.2)
	if p < DUST_UNTIL:
		items[&"fx_dust_construction_site"].append([xf.origin, dust, Color(phase, 0.0, 0.0, 0.0)])
	if BuildingMeshes.height_of(data) >= SPARKS_MIN_HEIGHT and p > WALLS_FROM and p < WALLS_TO:
		_spark_sites.append([building.id, items[&"fx_sparks_welding_burst"].size()])
		items[&"fx_sparks_welding_burst"].append([_spark_point(building, data, xf, p), 0.6, Color(phase, 0.0, 0.0, 0.0)])


## Доля готовности стройки с долей текущего тика (как ConstructionVisualizer.progress_of).
static func _progress(building: BuildingInstance) -> float:
	var total: int = maxi(1, maxi(building.construction_total, building.construction_ticks))
	return clampf((total - building.construction_ticks + SimClock.tick_progress()) / total, 0.0, 1.0)


## Искры — у переднего угла дома на верху растущих стен.
static func _spark_point(building: BuildingInstance, data: BuildingData, xf: Transform3D, p: float) -> Vector3:
	var box: AABB = BuildingMeshes.mesh_for(data).get_aabb()
	var cut: float = box.size.y * (p - WALLS_FROM) / (WALLS_TO - WALLS_FROM)
	var corner := Vector3(box.position.x + box.size.x * 0.8, cut + 0.05, box.position.z + 0.1)
	return xf * corner


## Высота искр идёт за стенами каждый кадр.
func _move_sparks() -> void:
	if _spark_sites.is_empty():
		return
	var grid: CityGrid = GameState.grid
	var multimesh: MultiMesh = _layers[&"fx_sparks_welding_burst"].multimesh
	for site: Array in _spark_sites:
		var building: BuildingInstance = grid.buildings.get(site[0])
		if building == null or site[1] >= multimesh.instance_count:
			continue
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		var xf: Transform3D = multimesh.get_instance_transform(site[1])
		xf.origin = _spark_point(building, data, grid.building_transform(building), _progress(building))
		multimesh.set_instance_transform(site[1], xf)


## Парки: на площади — фонтан, в скверах и садах — листва; над каждым вторым — птицы.
func _add_park(items: Dictionary[StringName, Array], data: BuildingData, xf: Transform3D, phase: float,
		index: int) -> void:
	var custom := Color(phase, 0.0, 0.0, 0.0)
	if data.park == BuildingData.Park.PLAZA:
		var mesh: Mesh = BuildingMeshes.mesh_for(data)
		items[&"fx_fountain_park_jets"].append([xf * Vector3(0.0, surface_top(mesh, Vector2.ZERO, 0.25), 0.0),
				FOUNTAIN_SCALE, custom])
	else:
		items[&"fx_nature_falling_leaves"].append([xf * Vector3(0.2, 0.15, 0.2), LEAVES_SCALE, custom])
	if index % BIRDS_EVERY == 0:
		items[&"fx_nature_flock_birds"].append([xf * Vector3(0.0, BIRDS_HEIGHT, 0.0), 1.0, custom])


## Работает ли этот источник у этого здания: печь — у части домов, вентиляция — у части высоких (по id).
static func _picked(building: BuildingInstance, data: BuildingData, emitter: Emitter) -> bool:
	var roll: float = fposmod(building.id * 0.754877 + 0.31, 1.0)
	if emitter.effect == &"fx_smoke_chimney_light" and CityGrid.is_residential(data.zone):
		return roll < HOUSE_SMOKE_SHARE
	if emitter.effect == &"fx_steam_vent_puff" and data.zone != CityGrid.Zone.INDUSTRIAL:
		return roll < VENT_SHARE
	return true


## Источники типа здания (по таблице манифеста или по мешу), с кэшем.
func _emitters_for(data: BuildingData) -> Array:
	if _type_emitters.has(data.id):
		return _type_emitters[data.id]
	var result: Array[Emitter] = []
	var mesh: Mesh = BuildingMeshes.mesh_for(data)
	# У вариантов уровня (…_l1, _l2, _l3) — та же модель, что у основного типа, и те же трубы.
	var key: String = String(data.id)
	if not _explicit.has(key) and key.length() > 3 and key.substr(key.length() - 3, 2) == "_l":
		key = key.substr(0, key.length() - 3)
	if _explicit.has(key):
		for entry: Array in _explicit[key]:
			var effect: StringName = entry[0]
			var at: Vector3 = entry[1]
			if not EFFECTS.has(effect):
				continue
			if nearest_vertex(mesh, at) <= SNAP:
				result.append(Emitter.new(effect, at))
			elif result.is_empty():
				# Точка таблицы мимо меша — у самой высокой трубы.
				result.append(Emitter.new(effect, chimney_top(mesh)))
	else:
		var top: Vector3 = chimney_top(mesh)
		var spread: Vector2 = top_spread(mesh)
		var narrow: bool = spread.x <= STACK_SPREAD and spread.y <= STACK_SPREAD
		match data.zone:
			CityGrid.Zone.INDUSTRIAL:
				result.append(Emitter.new(&"fx_smoke_factory_heavy" if narrow else &"fx_steam_vent_puff", top))
			CityGrid.Zone.RESIDENTIAL:
				result.append(Emitter.new(&"fx_smoke_chimney_light", top, HOUSE_SMOKE_SCALE))
			CityGrid.Zone.OFFICE, CityGrid.Zone.COMMERCIAL_HIGH:
				result.append(Emitter.new(&"fx_steam_vent_puff", top, 0.8))
			CityGrid.Zone.NONE:
				# Старая угольная ТЭЦ дымит; ветряки, насосы и службы — нет.
				if data.power_supply > 0 and String(data.id).begins_with("power_plant"):
					result.append(Emitter.new(&"fx_smoke_factory_heavy", top))
	_type_emitters[data.id] = result
	return result


func _load_manifest() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	if file == null:
		return
	var root: Variant = JSON.parse_string(file.get_as_text())
	if not root is Dictionary:
		return
	var table: Variant = (root as Dictionary).get("building_emitters", {}).get("explicit_building_emitters_godot_xyz", {})
	if not table is Dictionary:
		return
	for id: String in table:
		var list: Array = []
		for entry: Variant in table[id]:
			if entry is Dictionary and entry.get("pos") is Array and (entry.pos as Array).size() == 3:
				list.append([StringName(str(entry.get("effect", ""))), Vector3(entry.pos[0], entry.pos[1], entry.pos[2])])
		_explicit[id] = list


func _make_layer(effect: StringName) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	layer.name = String(effect)
	var mesh: ArrayMesh = ModelLoader.merge(load(DIR + String(effect) + ".glb"))
	var params: Dictionary = EFFECTS[effect]
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface) as BaseMaterial3D
		var color: Color = source.albedo_color if source != null else Color.WHITE
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter(&"albedo", color)
		material.set_shader_parameter(&"anim", params.anim)
		for key: String in ["speed", "sway", "bob", "pulse", "duration"]:
			if params.has(key):
				material.set_shader_parameter(StringName(key), params[key])
		var glow: float = params.get("glow", 0.0)
		if params.anim == Anim.PLUME and color.r > color.b + 0.35:
			glow = WARM_GLOW
		material.set_shader_parameter(&"glow", glow)
		mesh.surface_set_material(surface, material)
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.use_custom_data = true
	layer.multimesh.mesh = mesh
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Шейдер раскачивает и раздвигает клубы — запас, чтобы край не отсекался.
	layer.extra_cull_margin = 1.5
	layer.visibility_range_end = VISIBLE_RANGE
	add_child(layer)
	return layer


## items: [позиция, масштаб, INSTANCE_CUSTOM]; ветер у всех один — без поворота.
static func _write(layer: MultiMeshInstance3D, items: Array) -> void:
	var multimesh: MultiMesh = layer.multimesh
	multimesh.instance_count = items.size()
	for i: int in items.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * items[i][1]), items[i][0]))
		multimesh.set_instance_custom_data(i, items[i][2])


## Точка выброса над самой высокой частью меша: середина вершин в 6 см от верха (подсказка Argon).
static func chimney_top(mesh: Mesh) -> Vector3:
	var box: AABB = mesh.get_aabb()
	var top_y: float = box.end.y
	var sum := Vector2.ZERO
	var count: int = 0
	for surface: int in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			if v.y >= top_y - 0.06:
				sum += Vector2(v.x, v.z)
				count += 1
	var xz: Vector2 = sum / count if count > 0 else Vector2(box.get_center().x, box.get_center().z)
	return Vector3(xz.x, top_y, xz.y)


## Размер верхушки меша по X и Z (узкая — труба, широкая — конёк или плоская крыша).
static func top_spread(mesh: Mesh) -> Vector2:
	var box: AABB = mesh.get_aabb()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for surface: int in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			if v.y >= box.end.y - 0.06:
				low = Vector2(minf(low.x, v.x), minf(low.y, v.z))
				high = Vector2(maxf(high.x, v.x), maxf(high.y, v.z))
	return high - low if high.x >= low.x else Vector2.ZERO


## Расстояние от точки до ближайшей вершины меша.
static func nearest_vertex(mesh: Mesh, point: Vector3) -> float:
	var best: float = INF
	for surface: int in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			best = minf(best, v.distance_to(point))
	return best


## Верх меша над точкой xz (в радиусе radius) — куда ставить фонтан на клумбу площади.
static func surface_top(mesh: Mesh, xz: Vector2, radius: float) -> float:
	var top: float = 0.0
	for surface: int in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			if Vector2(v.x, v.z).distance_to(xz) <= radius:
				top = maxf(top, v.y)
	return top
