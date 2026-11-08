class_name ProceduralHouses
extends RefCounted
## Жилые дома малой плотности, которые строит код (одно здание на участок, а не россыпь домиков).
## Семейство (BuildingData.family) — один дом в трёх стадиях: стиль (цвет стен, крыша, окна, крыльцо,
## сторона пристройки) задаёт зерно семейства, уровень — размер: ур. 1 — домик в 1–2 этажа, ур. 2 — больше
## и выше, с пристройкой или крылом, ур. 3 — дом в 3–4 этажа с балконами. Повышение (Levels) берёт следующую
## стадию того же семейства — дом растёт, а не подменяется чужим.
## Широкие участки — одно здание на несколько квартир (рядный дом под одной крышей, дверь на каждую секцию),
## глубокие — дом с крылом во двор, на ур. 3 — П-образный дом вокруг дворика.
## Типы не лежат в data/buildings: BuildingCatalog добавляет их при загрузке (types()).

## Размеры домов (как были у составных участков: ширина вдоль улицы × глубина).
const SIZES: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(5, 1),
]
## Семейств на размер.
const VARIANTS: int = 4
## Высота этажа и шаг окон, метры (дом Kenney в клетке — около 1 м с крышей).
const FLOOR: float = 0.44
## Шаг окон — как в FACADE_SHADER для стилей домов (0.46).
const WINDOW_STEP: float = 0.46
const MARGIN: float = 0.15
## Ширина одной секции (квартиры с дверью) рядного дома, метры.
const UNIT: float = 1.9

const WALLS: Array[Color] = [
	Color(0.95, 0.9, 0.78), Color(0.96, 0.85, 0.6), Color(0.87, 0.75, 0.6), Color(0.74, 0.81, 0.86),
	Color(0.76, 0.84, 0.72), Color(0.96, 0.95, 0.92), Color(0.76, 0.45, 0.36), Color(0.84, 0.83, 0.8),
]
const ROOFS: Array[Color] = [
	Color(0.64, 0.27, 0.2), Color(0.47, 0.32, 0.24), Color(0.34, 0.35, 0.38), Color(0.76, 0.44, 0.27),
	Color(0.32, 0.38, 0.46),
]
const TRIMS: Array[Color] = [Color(0.97, 0.96, 0.93), Color(0.9, 0.86, 0.78), Color(0.36, 0.3, 0.26)]
const DOOR_COLOR := Color(0.36, 0.22, 0.14)
const CHIMNEY_COLOR := Color(0.55, 0.32, 0.26)
const FLAT_ROOF := Color(0.46, 0.47, 0.49)
const GRASS := Color(0.42, 0.62, 0.33)
const PAVING := Color(0.74, 0.71, 0.66)
const GARAGE_COLOR := Color(0.62, 0.63, 0.65)
## Стиль фасада в FACADE_SHADER (UV2.x): окна дома и глухая стена (фронтоны).
const STYLE_WINDOWS: int = 5
const STYLE_PLAIN: int = 6

## Крыша: тон и насыщенность — от цвета здания (INSTANCE_CUSTOM, как у домов Kenney), полосы черепицы — по UV.
const ROOF_SHADER: String = """
shader_type spatial;
render_mode cull_disabled;
varying vec4 custom;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (custom.a > 0.5) {
		vec3 h = rgb2hsv(c);
		h.x = custom.r;
		h.y = clamp(h.y * custom.g, 0.0, 1.0);
		c = hsv2rgb(h);
	}
	c *= fract(UV.y / 0.11) < 0.18 ? 0.8 : 1.0;
	// Цвета вершин заданы в sRGB, ALBEDO — линейный: без перевода черепица выходит бледной.
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
}
"""

static var _roof: ShaderMaterial


## Типы для каталога: семейства (по 3 уровня) и старые id составных участков — для сохранений.
static func types() -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	var by_id: Dictionary[String, BuildingData] = {}
	for size: Vector2i in SIZES:
		for variant: int in VARIANTS:
			var family: String = family_id(size, variant)
			for level: int in [1, 2, 3]:
				var data := BuildingData.new()
				data.id = StringName("%s_l%d" % [family, level])
				data.family = StringName(family)
				data.display_name = "%s · ур. %d" % [_title(size, variant), level]
				data.grows = true
				LevelStats.apply(data, CityGrid.Zone.RESIDENTIAL, level, size)
				data.mesh = build(family, level, size)
				result.append(data)
				by_id[String(data.id)] = data
	# Составные участки из нескольких домиков (до 2026-11-08): в сохранениях их id остаются — тот же размер
	# и уровень, вид — дом семейства; сами не растут, повышаются по семейству.
	for level: int in [1, 2, 3]:
		for legacy: Array in LEGACY:
			var source: BuildingData = by_id["%s_l%d" % [family_id(legacy[1], legacy[2]), level]]
			var data := BuildingData.new()
			data.id = StringName(String(legacy[0]) % level)
			data.family = source.family
			data.display_name = source.display_name
			data.grows = false
			LevelStats.apply(data, CityGrid.Zone.RESIDENTIAL, level, legacy[1])
			data.mesh = source.mesh
			result.append(data)
	return result


## Старые id составных участков → [формат id, размер, семейство].
const LEGACY: Array[Array] = [
	["res_lot_2x1_%d_a", Vector2i(2, 1), 0], ["res_lot_2x1_%d_b", Vector2i(2, 1), 1],
	["res_lot_3x1_%d_a", Vector2i(3, 1), 0], ["res_lot_3x1_%d_b", Vector2i(3, 1), 1],
	["res_lot_2x2_%d", Vector2i(2, 2), 0], ["res_lot_5x1_%d", Vector2i(5, 1), 0],
	["res_lot_3x2_%d", Vector2i(3, 2), 0],
]


static func family_id(size: Vector2i, variant: int) -> String:
	return "res_home_%dx%d_%d" % [size.x, size.y, variant]


static func _title(size: Vector2i, variant: int) -> String:
	var letter: String = "ABCD"[variant % 4]
	if size.y >= 2:
		return "Дом с крылом %s" % letter
	match size.x:
		1:
			return "Дом %s" % letter
		2:
			return "Дом на две семьи %s" % letter
	return "Рядный дом %s" % letter


## Меш дома семейства family на уровне level: центр основания в начале координат, улица — на −Z.
static func build(family: String, level: int, size: Vector2i) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(family)
	var style := {
		"wall": WALLS[rng.randi_range(0, WALLS.size() - 1)],
		"roof": ROOFS[rng.randi_range(0, ROOFS.size() - 1)],
		"trim": TRIMS[rng.randi_range(0, TRIMS.size() - 1)],
		"modern": rng.randf() < 0.3,
		"hip": rng.randf() < 0.35,
		"side": -1.0 if rng.randf() < 0.5 else 1.0,
		"chimney": rng.randf() < 0.7,
	}
	var st := {
		"walls": _begin(), "roof": _begin(), "details": _begin(),
	}
	var avail := Vector2(size.x * CityGrid.CELL_SIZE - MARGIN * 2.0, size.y * CityGrid.CELL_SIZE - MARGIN * 2.0)
	var front: float = -avail.y * 0.5
	# Газон под домом и дорожка к улице.
	_box(st.details, Vector3(0, 0, 0), Vector3(avail.x + 0.2, 0.02, avail.y + 0.2), GRASS)

	if size.y >= 2:
		_deep(st, style, level, size, avail, front)
	else:
		_row(st, style, level, size, avail, front)

	var mesh := ArrayMesh.new()
	st.walls.generate_tangents()
	st.walls.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, ProceduralBuildings._facade_material())
	st.roof.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _roof_material())
	st.details.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, ProceduralBuildings._plain_material())
	return mesh


## Дом в одну клетку глубиной: домик, дом на две семьи или рядный дом (одно здание, секция на квартиру).
static func _row(st: Dictionary, style: Dictionary, level: int, size: Vector2i, avail: Vector2, front: float) -> void:
	var floors: int = level
	var width: float
	var depth: float
	match level:
		1:
			width = avail.x * (0.66 if size.x == 1 else 0.9)
			depth = 1.12
		2:
			width = avail.x * (0.72 if size.x == 1 else 0.96)
			depth = 1.38
		_:
			width = avail.x
			depth = 1.56
	var x: float = 0.0
	if size.x == 1:
		x = style.side * (avail.x - width) * 0.5
	var setback: float = 0.22 if level == 1 else 0.12
	var center := Vector3(x, 0.0, front + setback + depth * 0.5)
	var units: int = maxi(1, roundi(width / UNIT))
	_body(st, style, center, Vector2(width, depth), floors, units, level)
	# Пристройка-гараж у домика на 2-м уровне — в свободную сторону клетки.
	if size.x == 1 and level == 2:
		var garage_w: float = avail.x - width - 0.04
		var gx: float = x - style.side * (width * 0.5 + garage_w * 0.5 + 0.02)
		var gz: float = center.z + 0.12
		_wall_box(st.walls, Vector3(gx, 0, gz), Vector3(garage_w, FLOOR * 0.95, depth - 0.24), STYLE_PLAIN, style.wall)
		_box(st.details, Vector3(gx, FLOOR * 0.95, gz), Vector3(garage_w + 0.06, 0.05, depth - 0.18), FLAT_ROOF)
		_box(st.details, Vector3(gx, 0, gz - (depth - 0.24) * 0.5 - 0.01), Vector3(garage_w * 0.7, FLOOR * 0.7, 0.03),
				GARAGE_COLOR)
		_box(st.details, Vector3(gx, 0.0, front - 0.02), Vector3(garage_w * 0.7, 0.025, (gz - front) * 2.0 - depth + 0.3),
				PAVING)


## Дом в две клетки глубиной: ур. 1 — корпус в 2 этажа у улицы, ур. 2 — в 3 этажа с крылом во двор (Г),
## ур. 3 — П-образный дом в 4 этажа вокруг дворика.
static func _deep(st: Dictionary, style: Dictionary, level: int, size: Vector2i, avail: Vector2, front: float) -> void:
	var floors: int = [2, 3, 4][level - 1]
	var width: float = avail.x * [0.78, 0.94, 1.0][level - 1]
	var depth: float = [1.36, 1.5, 1.6][level - 1]
	var center := Vector3(style.side * (avail.x - width) * 0.5, 0.0, front + 0.14 + depth * 0.5)
	var units: int = maxi(1, roundi(width / UNIT))
	_body(st, style, center, Vector2(width, depth), floors, units, level)
	if level == 1:
		# Сад за домом: дорожка и дерево-клумба.
		_box(st.details, Vector3(center.x, 0.02, front + 0.14 + depth + 0.7), Vector3(0.22, 0.02, 1.2), PAVING)
		return
	# Крылья во двор: глубина до конца участка, ширина — треть дома.
	var wing_w: float = clampf(width * 0.36, 1.0, 1.6)
	var wing_z0: float = center.z + depth * 0.5
	var wing_d: float = avail.y * 0.5 - wing_z0 - 0.05
	var sides: Array[float] = [-1.0, 1.0]
	if level == 2:
		sides = [float(style.side)]
	for s: float in sides:
		var wx: float = center.x + s * (width - wing_w) * 0.5
		var wing_floors: int = floors if s == style.side else maxi(2, floors - 1)
		var wing_center := Vector3(wx, 0.0, wing_z0 + wing_d * 0.5)
		_wall_box(st.walls, wing_center, Vector3(wing_w, wing_floors * FLOOR, wing_d), STYLE_WINDOWS, style.wall)
		_roof_over(st, style, wing_center, Vector2(wing_w, wing_d), wing_floors, false, level)


## Корпус: стены с окнами, двери секций с козырьками, крыша, у ур. 3 — балконы.
static func _body(st: Dictionary, style: Dictionary, center: Vector3, footprint: Vector2, floors: int, units: int,
		level: int) -> void:
	var height: float = floors * FLOOR
	_wall_box(st.walls, center, Vector3(footprint.x, height, footprint.y), STYLE_WINDOWS, style.wall)
	var face_z: float = center.z - footprint.y * 0.5
	var unit_w: float = footprint.x / units
	for u: int in units:
		var ux: float = center.x - footprint.x * 0.5 + unit_w * (u + 0.5)
		# Дверь чуть сбоку от середины секции, над ней — козырёк, к ней — дорожка.
		var door_x: float = ux + unit_w * 0.18 * (1.0 if u % 2 == 0 else -1.0)
		_box(st.details, Vector3(door_x, 0.0, face_z - 0.015), Vector3(0.2, 0.33, 0.03), DOOR_COLOR)
		_box(st.details, Vector3(door_x, 0.36, face_z - 0.09), Vector3(0.34, 0.03, 0.18), style.trim)
		_box(st.details, Vector3(door_x, 0.0, face_z - 0.3), Vector3(0.24, 0.022, 0.42), PAVING)
		# Межсекционная лопатка: видно квартиры, но дом один.
		if u > 0:
			var px: float = center.x - footprint.x * 0.5 + unit_w * u
			_box(st.details, Vector3(px, 0.0, face_z - 0.02), Vector3(0.06, height, 0.04), style.trim)
		# Балконы: ур. 3, со второго этажа, по одному на секцию.
		if level >= 3:
			for f: int in range(1, floors):
				var by: float = f * FLOOR + 0.02
				var bx: float = ux - unit_w * 0.14 * (1.0 if u % 2 == 0 else -1.0)
				_box(st.details, Vector3(bx, by, face_z - 0.1), Vector3(minf(0.62, unit_w * 0.45), 0.035, 0.2), style.trim)
				_box(st.details, Vector3(bx, by + 0.035, face_z - 0.195), Vector3(minf(0.62, unit_w * 0.45), 0.13, 0.015),
						style.trim.darkened(0.25))
	# Цоколь по всему периметру.
	_box(st.details, Vector3(center.x, 0.0, center.z), Vector3(footprint.x + 0.04, 0.06, footprint.y + 0.04),
			style.wall.darkened(0.35))
	_roof_over(st, style, center, footprint, floors, true, level)
	# Трубы: по одной на секцию у традиционных домов.
	if style.chimney and not (style.modern and level == 3):
		for u: int in units:
			var cx: float = center.x - footprint.x * 0.5 + unit_w * (u + 0.72)
			_box(st.details, Vector3(cx, height + 0.08, center.z + footprint.y * 0.14), Vector3(0.12, 0.42, 0.12),
					CHIMNEY_COLOR)


## Крыша над корпусом: двускатная (конёк вдоль длинной стороны) или вальмовая; у «современных» на ур. 3 —
## плоская с парапетом и надстройкой выхода на крышу.
static func _roof_over(st: Dictionary, style: Dictionary, center: Vector3, footprint: Vector2, floors: int,
		main: bool, level: int) -> void:
	var top: float = floors * FLOOR
	if style.modern and level >= 3:
		_box(st.details, Vector3(center.x, top, center.z), Vector3(footprint.x + 0.04, 0.05, footprint.y + 0.04), FLAT_ROOF)
		for edge: Array in [[0.0, -1.0], [0.0, 1.0], [-1.0, 0.0], [1.0, 0.0]]:
			var along_x: bool = edge[0] == 0.0
			var size := Vector3(footprint.x + 0.04 if along_x else 0.05, 0.1, 0.05 if along_x else footprint.y + 0.04)
			_box(st.details, Vector3(center.x + edge[0] * (footprint.x * 0.5), top + 0.05,
					center.z + edge[1] * (footprint.y * 0.5)), size, style.trim)
		if main:
			_wall_box(st.walls, Vector3(center.x + footprint.x * 0.22, top + 0.05, center.z + footprint.y * 0.1),
					Vector3(minf(0.7, footprint.x * 0.3), 0.32, 0.6), STYLE_PLAIN, style.wall)
		return
	var along_x: bool = footprint.x >= footprint.y
	var span: float = footprint.y if along_x else footprint.x
	var rise: float = clampf(span * 0.36, 0.3, 0.62)
	_pitched(st, Vector3(center.x, top, center.z), footprint, rise, along_x, style.hip and main, style)


## Двускатная или вальмовая крыша на высоте base.y; фронтоны — в стенах (цвет и оттенок стен).
static func _pitched(st: Dictionary, base: Vector3, footprint: Vector2, rise: float, along_x: bool, hip: bool,
		style: Dictionary) -> void:
	var oh: float = 0.09
	# Локальные оси: a — вдоль конька, b — поперёк.
	var half_a: float = (footprint.x if along_x else footprint.y) * 0.5
	var half_b: float = (footprint.y if along_x else footprint.x) * 0.5
	var to_world := func(a: float, b: float, y: float) -> Vector3:
		return base + (Vector3(a, y, b) if along_x else Vector3(b, y, a))
	var ridge_a: float = half_a + oh
	if hip:
		ridge_a = maxf(0.0, half_a - half_b * 0.9)
	var eave_y: float = -0.04
	var color: Color = style.roof
	# Два ската: от карниза (± (half_b + oh)) к коньку (b = 0, высота rise).
	for s: float in [-1.0, 1.0]:
		var e0: Vector3 = to_world.call(-(half_a + oh), s * (half_b + oh), eave_y)
		var e1: Vector3 = to_world.call(half_a + oh, s * (half_b + oh), eave_y)
		var r1: Vector3 = to_world.call(ridge_a, 0.0, rise)
		var r0: Vector3 = to_world.call(-ridge_a, 0.0, rise)
		var slope: float = Vector2(half_b + oh, rise - eave_y).length()
		_quad(st.roof, [e0, e1, r1, r0], [Vector2(0, 0), Vector2(1, 0), Vector2(1, slope), Vector2(0, slope)], color)
	for s: float in [-1.0, 1.0]:
		if hip:
			# Торцевой скат-треугольник.
			var t0: Vector3 = to_world.call(s * (half_a + oh), -(half_b + oh), eave_y)
			var t1: Vector3 = to_world.call(s * (half_a + oh), half_b + oh, eave_y)
			var tr: Vector3 = to_world.call(s * ridge_a, 0.0, rise)
			var slope_end: float = Vector2(half_a + oh - ridge_a, rise - eave_y).length()
			_tri(st.roof, [t0, t1, tr], [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, slope_end)], color,
					_face_normal(t0, t1, tr, to_world.call(s, 0.0, 0.0) - base))
		else:
			# Фронтон: треугольник стены под коньком.
			var g0: Vector3 = to_world.call(s * half_a, -half_b, 0.0)
			var g1: Vector3 = to_world.call(s * half_a, half_b, 0.0)
			var gr: Vector3 = to_world.call(s * half_a, 0.0, rise + 0.02)
			var normal: Vector3 = to_world.call(s, 0.0, 0.0) - base
			_wall_tri(st.walls, [g0, g1, gr], normal.normalized(), style.wall)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Стены корпуса с окнами (STYLE_WINDOWS) или глухие (STYLE_PLAIN); крышки нет. center — центр низа.
## Окна по стене — по середине стены (u сдвинут на половину остатка).
static func _wall_box(st: SurfaceTool, center: Vector3, size: Vector3, style: int, color: Color) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
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
		# Целое число шагов окон по стене; остаток (±0.115 м) — поровну по краям: окна не режутся углом.
		var shift: float = (length - roundf(length / WINDOW_STEP) * WINDOW_STEP) * 0.5
		var corners: Array[Vector3] = [a, b, b + Vector3(0, size.y, 0), a + Vector3(0, size.y, 0)]
		var uvs: Array[Vector2] = [Vector2(-shift, 0), Vector2(length - shift, 0), Vector2(length - shift, size.y),
				Vector2(-shift, size.y)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(side[2])
			st.set_color(color)
			st.set_uv(uvs[index])
			st.set_uv2(Vector2(style, FLOOR))
			st.add_vertex(corners[index] + center)


## Треугольник стены (фронтон) — глухой, цвет и оттенок стен как у корпуса.
static func _wall_tri(st: SurfaceTool, points: Array, normal: Vector3, color: Color) -> void:
	var ordered: Array = _wind(points, normal)
	for p: Vector3 in ordered:
		st.set_normal(normal)
		st.set_color(color)
		st.set_uv(Vector2(p.x + p.z, p.y))
		st.set_uv2(Vector2(STYLE_PLAIN, FLOOR))
		st.add_vertex(p)


## Четырёхугольник ската: нормаль — от фигуры, наружу и вверх.
static func _quad(st: SurfaceTool, points: Array, uvs: Array, color: Color) -> void:
	var normal: Vector3 = (points[1] - points[0]).cross(points[3] - points[0]).normalized()
	if normal.y < 0.0:
		normal = -normal
	_tri(st, [points[0], points[1], points[2]], [uvs[0], uvs[1], uvs[2]], color, normal)
	_tri(st, [points[0], points[2], points[3]], [uvs[0], uvs[2], uvs[3]], color, normal)


## Нормаль треугольника, смотрящая в сторону outward (и вверх для скатов).
static func _face_normal(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> Vector3:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	return normal


static func _tri(st: SurfaceTool, points: Array, uvs: Array, color: Color, normal: Vector3) -> void:
	var order: Array[int] = [0, 1, 2]
	# Лицевая сторона в Godot — обход по часовой, если смотреть снаружи (как у ProceduralBuildings._facade_box).
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0.0:
		order = [0, 2, 1]
	for i: int in order:
		st.set_normal(normal)
		st.set_color(color)
		st.set_uv(uvs[i])
		st.add_vertex(points[i])


static func _wind(points: Array, normal: Vector3) -> Array:
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0.0:
		return [points[0], points[2], points[1]]
	return points


## Ящик с цветом вершин: base — центр низа.
static func _box(st: SurfaceTool, base: Vector3, size: Vector3, color: Color) -> void:
	ProceduralBuildings._box(st, base, size, color)


static func _roof_material() -> ShaderMaterial:
	if _roof == null:
		_roof = ShaderMaterial.new()
		_roof.shader = Shader.new()
		_roof.shader.code = ROOF_SHADER
	return _roof
