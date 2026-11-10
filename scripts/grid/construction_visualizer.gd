extends Node3D
## Стройка как в Cities: Skylines: пока здание строится (BuildingInstance.construction_ticks),
## BuildingVisualizer его не рисует, а здесь — площадка (земля участка, забор у улицы, фундамент),
## дом растёт снизу вверх (BuildingPalette.construction_material режет его по высоте, внутри — бетон),
## вокруг — леса до текущей высоты; у средних зданий — башенный кран, у больших — два.
## Чем больше здание, тем дольше стройка (Levels.construction_ticks_for), выше леса и кран, длиннее стрела.
## Детали лесов и крана — из Blender (tools/blender/make_construction.py). Между тиками стройка
## идёт плавно (SimClock.tick_progress); на паузе всё замирает.

## Доли стройки: до FOUNDATION_END заливают фундамент, до WALLS_END растёт дом, потом разбирают леса.
const FOUNDATION_END: float = 0.12
const WALLS_END: float = 0.9
const FOUNDATION_HEIGHT: float = 0.06
const FOUNDATION_COLOR := Color(0.7, 0.69, 0.66)
## Ярус лесов (модуль scaffold.glb — 1 × 0.5 м, глубина 0.2 м) и зазор до стены, метры.
const SCAFFOLD_LEVEL: float = 0.5
const SCAFFOLD_GAP: float = 0.03
## Кран — у зданий от CRANE_HEIGHT метров (частные дома строят без крана, в одних лесах);
## два крана — у широких (от TWO_CRANES_CELLS клеток) и больших (клетки × высота от TWO_CRANES_VOLUME).
const CRANE_HEIGHT: float = 2.4
const TWO_CRANES_CELLS: int = 4
const TWO_CRANES_VOLUME: float = 20.0
## Мачта выше крыши, метры; стрела — доля большей стороны дома в пределах JIB_MIN..JIB_MAX.
const MAST_ABOVE_ROOF: float = 1.4
const JIB_SHARE: float = 0.75
const JIB_MIN: float = 2.0
const JIB_MAX: float = 7.0
## Мачта стоит внутри дома у задних углов, отступ от края, метры.
const CRANE_INSET: float = 0.4
## Низ стрелы над верхом мачты (crane_jib.glb) и груз над текущим ярусом, метры.
const JIB_BOTTOM: float = 0.12
const LOAD_ABOVE_WORK: float = 0.8
const PARTS := "res://assets/models/blender/construction/"


## Одна стройплощадка.
class Site:
	var building: BuildingInstance
	var data: BuildingData
	## Габариты меша дома (фасад на −Z), высота стен.
	var box: AABB
	var height: float
	## Узел в месте и с поворотом здания: площадка, фундамент и растущий дом — его дети.
	var root: Node3D
	var walls: MeshInstance3D
	var foundation: MeshInstance3D
	## Модули лесов одного яруса (в координатах здания) и сколько ярусов сейчас стоит.
	var ring: Array[Transform3D] = []
	var levels: int = 0
	var max_levels: int = 1
	## Краны: [x, z, фаза]; высота мачты и длина стрелы.
	var cranes: Array[Vector3] = []
	var mast: float = 0.0
	var jib: float = 0.0
	## Текущая высота среза (м от земли).
	var cut: float = -1.0


var _sites: Dictionary[int, Site] = {}
var _scaffold := MultiMeshInstance3D.new()
var _mast := MultiMeshInstance3D.new()
var _top := MultiMeshInstance3D.new()
var _jib := MultiMeshInstance3D.new()
var _cable := MultiMeshInstance3D.new()
var _hook := MultiMeshInstance3D.new()
var _foundation_mesh := BoxMesh.new()
## Время кранов: идёт только при идущей игре.
var _time: float = 0.0


func _ready() -> void:
	for pair: Array in [[_scaffold, "scaffold"], [_mast, "crane_mast"], [_top, "crane_top"], [_jib, "crane_jib"],
			[_cable, "crane_cable"], [_hook, "crane_hook"]]:
		var layer: MultiMeshInstance3D = pair[0]
		layer.multimesh = MultiMesh.new()
		layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		layer.multimesh.mesh = ModelLoader.merge(load(PARTS + pair[1] + ".glb"))
		# Краны поворачиваются и растут — запас, чтобы их не отсекало по краю экрана.
		layer.extra_cull_margin = JIB_MAX
		add_child(layer)
	_foundation_mesh.size = Vector3.ONE
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = FOUNDATION_COLOR
	concrete.roughness = 0.95
	_foundation_mesh.material = concrete
	Events.cells_changed.connect(func(_cells: Array[Vector2i]) -> void: _sync())
	Events.grid_reset.connect(_sync)
	_sync()


## Сколько стройплощадок сейчас (для проверок).
func site_count() -> int:
	return _sites.size()


## Доля готовности стройки 0..1 — с долей текущего тика, чтобы анимация шла плавно.
static func progress_of(building: BuildingInstance, tick_part: float) -> float:
	var total: int = maxi(1, maxi(building.construction_total, building.construction_ticks))
	return clampf((total - building.construction_ticks + tick_part) / total, 0.0, 1.0)


func _process(delta: float) -> void:
	if _sites.is_empty():
		return
	if SimClock.speed > 0:
		_time += delta
	var tick_part: float = SimClock.tick_progress()
	var scaffold_changed: bool = false
	for site: Site in _sites.values():
		if _update_site(site, progress_of(site.building, tick_part)):
			scaffold_changed = true
	if scaffold_changed:
		_write_scaffold()
	_write_cranes()


## Площадки — по зданиям со стройкой: новые появляются, достроенные и снесённые уходят.
func _sync() -> void:
	var grid: CityGrid = GameState.grid
	var building_now: Dictionary[int, bool] = {}
	for building: BuildingInstance in grid.buildings.values():
		if building.construction_ticks > 0:
			building_now[building.id] = true
	for id: int in _sites.keys():
		var site: Site = _sites[id]
		if not building_now.has(id) or grid.buildings.get(id) != site.building \
				or site.building.type_id != site.data.id:
			# Сразу, а не в конце кадра: готовый дом уже рисует BuildingVisualizer.
			site.root.free()
			_sites.erase(id)
	for id: int in building_now:
		if not _sites.has(id):
			var data: BuildingData = BuildingCatalog.get_type(grid.buildings[id].type_id)
			if data != null:
				_sites[id] = _make_site(grid, grid.buildings[id], data)
	_write_scaffold()
	_write_cranes()


func _make_site(grid: CityGrid, building: BuildingInstance, data: BuildingData) -> Site:
	var site := Site.new()
	site.building = building
	site.data = data
	var mesh: Mesh = BuildingPalette.convert(BuildingMeshes.mesh_for(data))
	site.box = mesh.get_aabb()
	site.height = site.box.end.y
	site.root = Node3D.new()
	site.root.transform = grid.building_transform(building)
	add_child(site.root)
	var ground := MeshInstance3D.new()
	ground.mesh = BuildingMeshes.site_mesh(data)
	site.root.add_child(ground)
	site.foundation = MeshInstance3D.new()
	site.foundation.mesh = _foundation_mesh
	site.foundation.visible = false
	site.root.add_child(site.foundation)
	site.walls = MeshInstance3D.new()
	site.walls.mesh = mesh
	for surface: int in mesh.get_surface_count():
		site.walls.set_surface_override_material(surface,
				BuildingPalette.construction_material(mesh.surface_get_material(surface)))
	site.walls.set_instance_shader_parameter(&"building_custom", BuildingPalette.custom_for(building, data))
	site.walls.set_instance_shader_parameter(&"cut_height", -1.0)
	site.root.add_child(site.walls)
	site.ring = _scaffold_ring(site.box)
	site.max_levels = maxi(1, ceili(site.height / SCAFFOLD_LEVEL))
	_plan_cranes(site, data)
	_update_site(site, progress_of(building, SimClock.tick_progress()))
	return site


## Модули лесов одного яруса по четырём сторонам дома; ширина модуля подгоняется под сторону.
func _scaffold_ring(box: AABB) -> Array[Transform3D]:
	var ring: Array[Transform3D] = []
	var x0: float = box.position.x - SCAFFOLD_GAP
	var x1: float = box.end.x + SCAFFOLD_GAP
	var z0: float = box.position.z - SCAFFOLD_GAP
	var z1: float = box.end.z + SCAFFOLD_GAP
	# [начало, конец, угол поворота (модуль смотрит наружу на +Z), вдоль X?, координата стороны].
	for side: Array in [[x0, x1, PI, true, z0], [x0, x1, 0.0, true, z1], [z0, z1, PI * 0.5, false, x1],
			[z0, z1, -PI * 0.5, false, x0]]:
		var length: float = side[1] - side[0]
		var count: int = maxi(1, roundi(length))
		var width: float = length / count
		var basis := Basis(Vector3.UP, side[2]) * Basis.from_scale(Vector3(width, 1.0, 1.0))
		for k: int in count:
			var along: float = side[0] + width * (k + 0.5)
			var origin := Vector3(along, 0.0, side[4]) if side[3] else Vector3(side[4], 0.0, along)
			ring.append(Transform3D(basis, origin))
	return ring


## Краны по размеру здания: мачта внутри дома у задних углов, выше крыши; стрела — по большей стороне.
func _plan_cranes(site: Site, data: BuildingData) -> void:
	if site.height < CRANE_HEIGHT:
		return
	var cells: int = data.size.x * data.size.y
	var volume: float = cells * site.height
	var box: AABB = site.box
	var back_z: float = box.end.z - CRANE_INSET
	var phase: float = fposmod(site.building.id * 0.618034, 1.0) * TAU
	if cells >= TWO_CRANES_CELLS and volume >= TWO_CRANES_VOLUME and box.size.x > CRANE_INSET * 4.0:
		site.cranes.append(Vector3(box.position.x + CRANE_INSET, back_z, phase))
		site.cranes.append(Vector3(box.end.x - CRANE_INSET, back_z, phase + 2.4))
	else:
		var x: float = box.position.x + CRANE_INSET if box.size.x > CRANE_INSET * 3.0 else box.get_center().x
		site.cranes.append(Vector3(x, back_z, phase))
	site.mast = site.height + MAST_ABOVE_ROOF
	site.jib = clampf(maxf(box.size.x, box.size.z) * JIB_SHARE, JIB_MIN, JIB_MAX)


## Фундамент, срез дома и ярусы лесов по готовности p. Возвращает true, если число ярусов изменилось.
func _update_site(site: Site, p: float) -> bool:
	var pour: float = clampf(p / FOUNDATION_END, 0.0, 1.0) * FOUNDATION_HEIGHT
	site.foundation.visible = pour > 0.001 and p < WALLS_END
	if site.foundation.visible:
		site.foundation.transform = Transform3D(Basis.from_scale(Vector3(site.box.size.x + 0.04, pour, site.box.size.z + 0.04)),
				Vector3(site.box.get_center().x, pour * 0.5, site.box.get_center().z))
	var levels: int = 0
	if p < FOUNDATION_END:
		site.cut = -1.0
	elif p < WALLS_END:
		site.cut = site.height * (p - FOUNDATION_END) / (WALLS_END - FOUNDATION_END)
		levels = mini(site.max_levels, ceili(site.cut / SCAFFOLD_LEVEL + 0.01))
	else:
		# Дом готов, леса разбирают сверху вниз.
		site.cut = site.height + 1.0
		levels = roundi(site.max_levels * (1.0 - (p - WALLS_END) / (1.0 - WALLS_END)))
	site.walls.set_instance_shader_parameter(&"cut_height", site.cut)
	if levels == site.levels:
		return false
	site.levels = levels
	return true


func _write_scaffold() -> void:
	var count: int = 0
	for site: Site in _sites.values():
		count += site.ring.size() * site.levels
	var multimesh: MultiMesh = _scaffold.multimesh
	multimesh.instance_count = count
	var i: int = 0
	for site: Site in _sites.values():
		var xform: Transform3D = site.root.transform
		for level: int in site.levels:
			var lift := Vector3(0.0, level * SCAFFOLD_LEVEL, 0.0)
			for module: Transform3D in site.ring:
				multimesh.set_instance_transform(i, xform * module.translated(lift))
				i += 1


## Краны: мачта из секций по 1 м (подогнанных под высоту); стрела качается, тележка ездит по ней,
## груз опускается к текущему ярусу.
func _write_cranes() -> void:
	var cranes: Array[Array] = []
	var segments: int = 0
	for site: Site in _sites.values():
		for crane: Vector3 in site.cranes:
			cranes.append([site, crane])
			segments += ceili(site.mast)
	# Число экземпляров — только если изменилось: присвоение заново выделяет буфер.
	if _mast.multimesh.instance_count != segments:
		_mast.multimesh.instance_count = segments
	for layer: MultiMeshInstance3D in [_top, _jib, _cable, _hook]:
		if layer.multimesh.instance_count != cranes.size():
			layer.multimesh.instance_count = cranes.size()
	var s: int = 0
	for i: int in cranes.size():
		var site: Site = cranes[i][0]
		var crane: Vector3 = cranes[i][1]
		var base: Transform3D = site.root.transform * Transform3D(Basis.IDENTITY, Vector3(crane.x, 0.0, crane.y))
		var count: int = ceili(site.mast)
		var step: float = site.mast / count
		for k: int in count:
			_mast.multimesh.set_instance_transform(s, base * Transform3D(Basis.from_scale(Vector3(1.0, step, 1.0)),
					Vector3(0.0, k * step, 0.0)))
			s += 1
		var yaw: float = crane.z + 1.1 * sin(_time * 0.22 + crane.z * 2.0)
		var top: Transform3D = base * Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, site.mast, 0.0))
		_top.multimesh.set_instance_transform(i, top)
		_jib.multimesh.set_instance_transform(i, top * Transform3D(Basis.from_scale(Vector3(site.jib, 1.0, 1.0)), Vector3.ZERO))
		var reach: float = site.jib * (0.55 + 0.3 * sin(_time * 0.37 + crane.z))
		var hook_top: float = site.mast + JIB_BOTTOM
		var hook_y: float = clampf(maxf(site.cut, 0.0) + LOAD_ABOVE_WORK, 0.6, hook_top - 0.3)
		var cable: float = hook_top - hook_y
		_cable.multimesh.set_instance_transform(i, top * Transform3D(Basis.from_scale(Vector3(1.0, cable, 1.0)),
				Vector3(reach, JIB_BOTTOM, 0.0)))
		_hook.multimesh.set_instance_transform(i, top * Transform3D(Basis.IDENTITY, Vector3(reach, JIB_BOTTOM - cable, 0.0)))
