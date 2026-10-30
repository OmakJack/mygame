class_name ProceduralBuildings
extends RefCounted
## Многоэтажки и офисы, которые строит код (слой 2 разнообразия): у Kenney нет жилых многоэтажек,
## а башен мало. Каждый тип — свой вид: этажность, размеры, цвет, рисунок окон, уступы, крыша.
## Вид задаётся зерном из id, поэтому в сохранениях тип всегда выглядит одинаково.
## Окна рисует шейдер фасада (FACADE_SHADER) по UV в метрах — без текстур.
## Типы не лежат в data/buildings: BuildingCatalog добавляет их при загрузке (types()).

## Сколько вариантов на уровень.
const APARTMENT_VARIANTS: int = 6
const OFFICE_VARIANTS: int = 5
## Высота этажа и шаг окон, метры (как у моделей Kenney при нашем масштабе).
const APARTMENT_FLOOR: float = 0.52
const OFFICE_FLOOR: float = 0.48
const WINDOW_STEP: float = 0.36
## Этажей по уровням [мин, макс].
const APARTMENT_FLOORS: Array[Vector2i] = [Vector2i(4, 6), Vector2i(7, 9), Vector2i(10, 13)]
const OFFICE_FLOORS: Array[Vector2i] = [Vector2i(6, 8), Vector2i(9, 12), Vector2i(13, 17)]
## Основание не шире клетки с отступом (как у моделей, BuildingMeshes.FOOTPRINT).
const MAX_SIDE: float = 1.75

## Рисунки фасада (UV2.x): окна-проёмы, лоджии, ленточные окна, стекло целиком, вертикальные полосы.
enum Style { PUNCHED, BALCONY, RIBBON, CURTAIN, STRIPS }

const APARTMENT_WALLS: Array[Color] = [
	Color(0.93, 0.89, 0.8), Color(0.78, 0.46, 0.36), Color(0.86, 0.86, 0.84), Color(0.95, 0.86, 0.62),
	Color(0.7, 0.78, 0.8), Color(0.98, 0.97, 0.94), Color(0.84, 0.7, 0.58),
]
const OFFICE_GLASS: Array[Color] = [
	Color(0.32, 0.5, 0.68), Color(0.3, 0.6, 0.62), Color(0.55, 0.5, 0.42), Color(0.26, 0.32, 0.42),
	Color(0.5, 0.62, 0.72),
]
const ROOF_COLOR := Color(0.42, 0.43, 0.46)
const DETAIL_COLOR := Color(0.6, 0.61, 0.63)
const GROUND_COLOR := Color(0.32, 0.33, 0.36)

const FACADE_SHADER: String = """
shader_type spatial;
const vec3 WALLS[6] = vec3[6](
	vec3(1.0, 1.0, 1.0), vec3(1.0, 0.95, 0.84), vec3(0.98, 0.88, 0.72),
	vec3(1.0, 0.86, 0.78), vec3(0.86, 0.9, 0.97), vec3(0.88, 0.96, 0.86));
varying vec4 custom;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	int style = int(UV2.x + 0.5);
	float floor_h = UV2.y;
	vec2 g = vec2(UV.x / %f, UV.y / floor_h);
	vec2 f = fract(g);
	vec3 wall = COLOR.rgb;
	if (custom.a > 0.5 && style < 3) {
		wall *= WALLS[clamp(int(custom.b * 8.0 + 0.5), 0, 5)];
	}
	float lit = hash(floor(g) + vec2(UV2.x * 7.0, 0.0));
	vec3 glass = mix(vec3(0.16, 0.22, 0.3), vec3(0.42, 0.55, 0.66), lit * 0.6);
	vec3 frame = vec3(0.3, 0.31, 0.34);
	bool win = false;
	bool slab = false;
	if (g.y < 1.0) {
		// Первый этаж: витрины во всю ширину.
		win = f.y > 0.12 && f.y < 0.8 && f.x > 0.08;
		wall = wall * 0.7;
	} else if (style == 0) {
		win = f.x > 0.22 && f.x < 0.78 && f.y > 0.3 && f.y < 0.82;
	} else if (style == 1) {
		win = f.x > 0.15 && f.x < 0.85 && f.y > 0.25 && f.y < 0.85;
		slab = f.y < 0.14;
	} else if (style == 2) {
		win = f.y > 0.32 && f.y < 0.8 && f.x > 0.05;
	} else if (style == 3) {
		glass = mix(COLOR.rgb * 0.55, COLOR.rgb, lit * 0.5);
		win = f.x > 0.06 && f.y > 0.08;
		wall = frame;
	} else {
		glass = mix(COLOR.rgb * 0.5, COLOR.rgb * 0.9, lit * 0.5);
		win = f.x > 0.18 && f.x < 0.62 && f.y > 0.06;
		wall = vec3(0.86, 0.86, 0.84);
	}
	vec3 c = win ? glass : (slab ? wall * 1.12 : wall);
	ALBEDO = c;
	ROUGHNESS = win ? 0.15 : 0.8;
	SPECULAR = win ? 0.7 : 0.3;
}
""" % WINDOW_STEP

static var _facade: ShaderMaterial
static var _plain: StandardMaterial3D


## Типы для каталога: 1×1 (res_gen_*, off_gen_*) и многоклеточные комплексы 2..7 клеток.
static func types() -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for level: int in [1, 2, 3]:
		for n: int in APARTMENT_VARIANTS:
			result.append(_type("res_gen_%d_%d" % [level, n], CityGrid.Zone.RESIDENTIAL_HIGH, level, "Многоэтажка"))
		for n: int in OFFICE_VARIANTS:
			result.append(_type("off_gen_%d_%d" % [level, n], CityGrid.Zone.OFFICE, level, "Офис"))
		# Многоклеточные жилые комплексы, торговые пассажи и бизнес-центры (2..7 клеток).
		for n: int in 2:
			result.append(_lot_type("res_wide_2x1_%d_%d" % [level, n], CityGrid.Zone.RESIDENTIAL_HIGH,
					level, Vector2i(2, 1), "Широкий дом %d" % (n + 1)))
			result.append(_lot_type("res_court_2x2_%d_%d" % [level, n], CityGrid.Zone.RESIDENTIAL_HIGH,
					level, Vector2i(2, 2), "Жилой двор %d" % (n + 1)))
			result.append(_lot_type("com_wide_2x1_%d_%d" % [level, n], CityGrid.Zone.COMMERCIAL_HIGH,
					level, Vector2i(2, 1), "Универмаг %d" % (n + 1)))
			result.append(_lot_type("com_wide_3x1_%d_%d" % [level, n], CityGrid.Zone.COMMERCIAL_HIGH,
					level, Vector2i(3, 1), "Пассаж %d" % (n + 1)))
			result.append(_lot_type("off_wide_2x1_%d_%d" % [level, n], CityGrid.Zone.OFFICE,
					level, Vector2i(2, 1), "Деловой дом %d" % (n + 1)))
			result.append(_lot_type("off_wide_3x1_%d_%d" % [level, n], CityGrid.Zone.OFFICE,
					level, Vector2i(3, 1), "Башни-близнецы %d" % (n + 1)))
			result.append(_lot_type("off_plaza_2x2_%d_%d" % [level, n], CityGrid.Zone.OFFICE,
					level, Vector2i(2, 2), "Бизнес-плаза %d" % (n + 1)))
		result.append(_lot_type("off_blvd_5x1_%d" % level, CityGrid.Zone.OFFICE,
				level, Vector2i(5, 1), "Деловой квартал"))
		result.append(_lot_type("off_campus_3x2_%d" % level, CityGrid.Zone.OFFICE,
				level, Vector2i(3, 2), "Бизнес-кампус"))
		result.append(_lot_type("off_hq_7x1_%d" % level, CityGrid.Zone.OFFICE,
				level, Vector2i(7, 1), "Штаб-квартира"))
	return result


static func _type(id: String, zone_type: CityGrid.Zone, level: int, name: String) -> BuildingData:
	var data := BuildingData.new()
	data.id = StringName(id)
	data.display_name = "%s %s · ур. %d" % [name, id.get_slice("_", 3), level]
	data.grows = true
	LevelStats.apply(data, zone_type, level)
	data.mesh = build(id, zone_type == CityGrid.Zone.OFFICE, level)
	return data


static func _lot_type(id: String, zone_type: CityGrid.Zone, level: int, plot_size: Vector2i,
		title: String) -> BuildingData:
	var data := BuildingData.new()
	data.id = StringName(id)
	data.display_name = "%s · ур. %d" % [title, level]
	data.grows = true
	LevelStats.apply(data, zone_type, level, plot_size)
	data.mesh = build_lot(id, zone_type, level, plot_size)
	return data


## Меш здания по id: фасад окнами, первый этаж, крыша и детали. Вход — на −Z.
static func build(id: String, office: bool, level: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var details := SurfaceTool.new()
	details.begin(Mesh.PRIMITIVE_TRIANGLES)

	var floors_range: Vector2i = (OFFICE_FLOORS if office else APARTMENT_FLOORS)[level - 1]
	var floors: int = rng.randi_range(floors_range.x, floors_range.y)
	var floor_h: float = OFFICE_FLOOR if office else APARTMENT_FLOOR
	var style: int
	var color: Color
	if office:
		style = Style.CURTAIN if rng.randf() < 0.6 else Style.STRIPS
		color = OFFICE_GLASS[rng.randi_range(0, OFFICE_GLASS.size() - 1)]
	else:
		style = [Style.PUNCHED, Style.BALCONY, Style.RIBBON][rng.randi_range(0, 2)]
		color = APARTMENT_WALLS[rng.randi_range(0, APARTMENT_WALLS.size() - 1)]
	var width: float = snappedf(rng.randf_range(1.25, MAX_SIDE), WINDOW_STEP * 0.5)
	var depth: float = snappedf(rng.randf_range(1.2, MAX_SIDE), WINDOW_STEP * 0.5)

	# Корпус; у высоких — уступ: верхние этажи уже (как у башен).
	var lower: int = floors
	if floors >= 9 and rng.randf() < 0.65:
		lower = floors - rng.randi_range(2, maxi(3, floors / 3))
	_facade_box(walls, Vector3(0, 0, 0), Vector3(width, lower * floor_h, depth), 0.0, color, style, floor_h)
	var top: float = lower * floor_h
	var top_size := Vector2(width, depth)
	if lower < floors:
		top_size = Vector2(width * rng.randf_range(0.6, 0.8), depth * rng.randf_range(0.6, 0.8))
		_facade_box(walls, Vector3(0, top, 0), Vector3(top_size.x, (floors - lower) * floor_h, top_size.y), top,
				color, style, floor_h)
		_box(details, Vector3(0, top, 0), Vector3(width + 0.04, 0.05, depth + 0.04), ROOF_COLOR)
		top = floors * floor_h
	# Крыша: плита с бортиком, будка лестницы, вентиляция; у офисов — иногда антенна.
	_box(details, Vector3(0, top, 0), Vector3(top_size.x + 0.05, 0.06, top_size.y + 0.05), ROOF_COLOR)
	_box(details, Vector3(rng.randf_range(-0.2, 0.2) * top_size.x, top + 0.06, rng.randf_range(-0.2, 0.2) * top_size.y),
			Vector3(0.36, 0.28, 0.3), DETAIL_COLOR)
	for i: int in rng.randi_range(1, 3):
		var at := Vector3(rng.randf_range(-0.35, 0.35) * top_size.x, top + 0.06, rng.randf_range(-0.35, 0.35) * top_size.y)
		_box(details, at, Vector3(0.18, 0.12, 0.18), DETAIL_COLOR.darkened(0.15))
	if office and rng.randf() < 0.5:
		_box(details, Vector3(0, top + 0.06, 0), Vector3(0.05, rng.randf_range(0.6, 1.1), 0.05), DETAIL_COLOR)
	# Козырёк над входом.
	_box(details, Vector3(0, floor_h * 0.78, -depth * 0.5 - 0.09), Vector3(0.5, 0.04, 0.18), GROUND_COLOR)

	var mesh := ArrayMesh.new()
	walls.generate_tangents()
	walls.commit(mesh)
	mesh.surface_set_material(0, _facade_material())
	details.commit(mesh)
	mesh.surface_set_material(1, _plain_material())
	return mesh


## Многоклеточный процедурный комплекс (2..7 клеток): стилобат у улицы (−Z), крылья и башни.
static func build_lot(id: String, zone_type: CityGrid.Zone, level: int, plot_size: Vector2i) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var details := SurfaceTool.new()
	details.begin(Mesh.PRIMITIVE_TRIANGLES)

	var office: bool = zone_type == CityGrid.Zone.OFFICE
	var comm: bool = zone_type == CityGrid.Zone.COMMERCIAL_HIGH
	var floors_range: Vector2i = (OFFICE_FLOORS if office else APARTMENT_FLOORS)[level - 1]
	if comm:
		floors_range = [Vector2i(3, 5), Vector2i(5, 7), Vector2i(7, 10)][level - 1]
	var main_floors: int = rng.randi_range(floors_range.x, floors_range.y) + (1 if plot_size.x * plot_size.y >= 5 else 0)
	var floor_h: float = OFFICE_FLOOR if (office or comm) else APARTMENT_FLOOR
	var style: int
	var color: Color
	if office:
		style = Style.CURTAIN if rng.randf() < 0.65 else Style.STRIPS
		color = OFFICE_GLASS[rng.randi_range(0, OFFICE_GLASS.size() - 1)]
	elif comm:
		style = Style.RIBBON if rng.randf() < 0.55 else Style.CURTAIN
		color = OFFICE_GLASS[rng.randi_range(0, OFFICE_GLASS.size() - 1)].lightened(0.15)
	else:
		style = [Style.PUNCHED, Style.BALCONY, Style.RIBBON][rng.randi_range(0, 2)]
		color = APARTMENT_WALLS[rng.randi_range(0, APARTMENT_WALLS.size() - 1)]

	var lot_w: float = plot_size.x * CityGrid.CELL_SIZE - 0.32
	var lot_d: float = plot_size.y * CityGrid.CELL_SIZE - 0.32
	# Плита двора/площади.
	var slab_col: Color = Color(0.68, 0.67, 0.64) if (office or comm) else Color(0.45, 0.58, 0.38)
	_box(details, Vector3(0, 0, 0), Vector3(lot_w + 0.14, 0.03, lot_d + 0.14), slab_col)

	var pod_floors: int = 2 if main_floors >= 6 else 1
	var pod_d: float = minf(lot_d, 1.58)
	var pod_z: float = -lot_d * 0.5 + pod_d * 0.5
	# Стилобат вдоль лицевой улицы (−Z).
	_add_tower(walls, details, Vector3(0, 0.03, pod_z), Vector2(lot_w, pod_d), pod_floors, floor_h,
			color, style, false, rng)

	if plot_size == Vector2i(2, 1):
		_add_tower(walls, details, Vector3(0, 0.03, 0), Vector2(lot_w * 0.88, lot_d * 0.88),
				main_floors, floor_h, color, style, office, rng)
	elif plot_size == Vector2i(3, 1):
		var tw: float = lot_w * 0.36
		var offset_x: float = lot_w * 0.28
		_add_tower(walls, details, Vector3(-offset_x, 0.03, 0.04), Vector2(tw, lot_d * 0.86),
				main_floors, floor_h, color, style, office, rng)
		_add_tower(walls, details, Vector3(offset_x, 0.03, 0.04), Vector2(tw, lot_d * 0.86),
				maxi(3, main_floors - rng.randi_range(0, 2)), floor_h, color, style, false, rng)
	elif plot_size == Vector2i(2, 2):
		# Угловая Г-образная композиция со сквером/плазой.
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		_add_tower(walls, details, Vector3(side * lot_w * 0.22, 0.03, -lot_d * 0.2),
				Vector2(lot_w * 0.5, lot_d * 0.52), main_floors, floor_h, color, style, office, rng)
		_add_tower(walls, details, Vector3(-side * lot_w * 0.24, 0.03, -lot_d * 0.24),
				Vector2(lot_w * 0.44, lot_d * 0.42), maxi(3, main_floors - 2), floor_h, color, style, false, rng)
		_add_tower(walls, details, Vector3(side * lot_w * 0.26, 0.03, lot_d * 0.24),
				Vector2(lot_w * 0.42, lot_d * 0.44), maxi(3, main_floors - 3), floor_h, color, style, false, rng)
	elif plot_size == Vector2i(5, 1):
		# Центральная доминанта + два боковых крыла.
		_add_tower(walls, details, Vector3(0, 0.03, 0.03), Vector2(2.3, lot_d * 0.9),
				main_floors + 2, floor_h, color, style, office, rng)
		for s: float in [-1.0, 1.0]:
			_add_tower(walls, details, Vector3(s * 3.15, 0.03, 0.03), Vector2(2.4, lot_d * 0.84),
					maxi(4, main_floors - 2), floor_h, color, style, false, rng)
	elif plot_size == Vector2i(3, 2):
		# Кампус: две башни по диагонали/бокам и задний корпус вокруг двора.
		_add_tower(walls, details, Vector3(-lot_w * 0.28, 0.03, -lot_d * 0.16),
				Vector2(1.95, 1.85), main_floors + 1, floor_h, color, style, office, rng)
		_add_tower(walls, details, Vector3(lot_w * 0.28, 0.03, 0.18),
				Vector2(1.95, 1.85), maxi(4, main_floors - 1), floor_h, color, style, office, rng)
		_add_tower(walls, details, Vector3(-lot_w * 0.05, 0.03, lot_d * 0.32),
				Vector2(lot_w * 0.56, 1.05), maxi(3, pod_floors + 2), floor_h, color, style, false, rng)
	else:
		# 7×1 и шире: флагманский проспектный ансамбль с центральной башней и 2 средними корпусами.
		_add_tower(walls, details, Vector3(0, 0.03, 0.04), Vector2(2.5, lot_d * 0.92),
				main_floors + 3, floor_h, color, style, true, rng)
		for s: float in [-1.0, 1.0]:
			_add_tower(walls, details, Vector3(s * 3.2, 0.03, 0.02), Vector2(2.2, lot_d * 0.86),
					maxi(5, main_floors - 1), floor_h, color, style, false, rng)
			_add_tower(walls, details, Vector3(s * 5.6, 0.03, 0.0), Vector2(1.8, lot_d * 0.8),
					maxi(3, main_floors - 4), floor_h, color, style, false, rng)

	# Козырьки входов вдоль лицевого фасада (−Z).
	var entries: int = maxi(1, plot_size.x / 2 + 1)
	for i: int in entries:
		var ex: float = ((i + 0.5) / entries - 0.5) * (lot_w * 0.82)
		_box(details, Vector3(ex, floor_h * 0.82, -lot_d * 0.5 - 0.08), Vector3(0.62, 0.045, 0.2), GROUND_COLOR)

	var mesh := ArrayMesh.new()
	walls.generate_tangents()
	walls.commit(mesh)
	mesh.surface_set_material(0, _facade_material())
	details.commit(mesh)
	mesh.surface_set_material(1, _plain_material())
	return mesh


static func _add_tower(walls: SurfaceTool, details: SurfaceTool, base: Vector3, footprint: Vector2,
		floors: int, floor_h: float, color: Color, style: int, spire: bool, rng: RandomNumberGenerator) -> void:
	var lower: int = floors
	if floors >= 10:
		lower = floors - 3
	var h0: float = lower * floor_h
	_facade_box(walls, base, Vector3(footprint.x, h0, footprint.y), 0.0, color, style, floor_h)
	var top: float = base.y + h0
	var top_fp: Vector2 = footprint
	if lower < floors:
		top_fp = footprint * 0.74
		var h1: float = (floors - lower) * floor_h
		_facade_box(walls, Vector3(base.x, top, base.z), Vector3(top_fp.x, h1, top_fp.y), h0, color, style, floor_h)
		_box(details, Vector3(base.x, top, base.z), Vector3(footprint.x + 0.05, 0.05, footprint.y + 0.05), ROOF_COLOR)
		top += h1
	_box(details, Vector3(base.x, top, base.z), Vector3(top_fp.x + 0.05, 0.06, top_fp.y + 0.05), ROOF_COLOR)
	_box(details, Vector3(base.x + rng.randf_range(-0.15, 0.15) * top_fp.x, top + 0.06, base.z),
			Vector3(minf(0.42, top_fp.x * 0.35), 0.26, minf(0.34, top_fp.y * 0.35)), DETAIL_COLOR)
	if spire:
		_box(details, Vector3(base.x, top + 0.06, base.z), Vector3(0.06, rng.randf_range(0.7, 1.3), 0.06), DETAIL_COLOR)


## Корпус: четыре стены с UV в метрах (u — вдоль стены, v — высота от земли) и рисунком окон в UV2.
static func _facade_box(st: SurfaceTool, base: Vector3, size: Vector3, v_from: float, color: Color, style: int,
		floor_h: float) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var y0: float = base.y
	var y1: float = base.y + size.y
	# Стены: [начало, конец, нормаль] по низу, обход против часовой снаружи.
	var sides: Array = [
		[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3.FORWARD],
		[Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3.RIGHT],
		[Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3.BACK],
		[Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz), Vector3.LEFT],
	]
	for side: Array in sides:
		var a: Vector3 = side[0]
		var b: Vector3 = side[1]
		var length: float = a.distance_to(b)
		var corners: Array[Vector3] = [a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0)]
		var uvs: Array[Vector2] = [Vector2(0, v_from), Vector2(length, v_from), Vector2(length, v_from + size.y), Vector2(0, v_from + size.y)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(side[2])
			st.set_color(color)
			st.set_uv(uvs[index])
			st.set_uv2(Vector2(style, floor_h))
			st.add_vertex(corners[index] + Vector3(base.x, 0, base.z))


## Простой ящик с цветом в вершинах (крыши, будки, козырьки); base — центр низа.
static func _box(st: SurfaceTool, base: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i: int in indices:
		st.set_normal(normals[i])
		st.set_color(color)
		st.add_vertex(vertices[i] + base + Vector3(0, size.y * 0.5, 0))


static func _facade_material() -> ShaderMaterial:
	if _facade == null:
		_facade = ShaderMaterial.new()
		_facade.shader = Shader.new()
		_facade.shader.code = FACADE_SHADER
	return _facade


static func _plain_material() -> StandardMaterial3D:
	if _plain == null:
		_plain = StandardMaterial3D.new()
		_plain.vertex_color_use_as_albedo = true
		_plain.roughness = 0.85
	return _plain
