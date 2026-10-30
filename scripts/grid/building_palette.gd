class_name BuildingPalette
extends RefCounted
## Разные цвета одинаковых домов (без новых файлов). Модели Kenney красятся одной палитрой
## colormap.png: сетка образцов 8×4 (образец 64×128 px), у всех наборов одинаковая раскладка.
## Шейдер по UV узнаёт образец: акценты (крыши, навесы — зелёный, жёлтый, оранжевый, красный,
## фиолетовый, розовый) получают цвет крыши здания, белые и кремовые стены — лёгкий оттенок.
## Окна (синие образцы), тёмные детали и двери не трогаются.
## Цвет здания — в INSTANCE_CUSTOM мультимеша: r — тон крыши, g — насыщенность, b — номер оттенка
## стен (/8), a — 1 «перекрашивать» (у служб и парков 0: их узнают по виду).

const SHADER: String = """
shader_type spatial;
uniform sampler2D palette : source_color, filter_linear_mipmap;
const vec3 WALLS[6] = vec3[6](
	vec3(1.0, 1.0, 1.0), vec3(1.0, 0.95, 0.84), vec3(0.98, 0.88, 0.72),
	vec3(1.0, 0.86, 0.78), vec3(0.86, 0.9, 0.97), vec3(0.88, 0.96, 0.86));
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
	vec3 c = texture(palette, UV).rgb;
	if (custom.a > 0.5) {
		int col = int(floor(fract(UV.x) * 8.0));
		int row = int(floor(fract(UV.y) * 4.0));
		bool accent = (row == 1 && col != 4 && col != 5) || (row == 3 && col == 1);
		if (accent) {
			vec3 h = rgb2hsv(c);
			h.x = custom.r;
			h.y *= custom.g;
			c = hsv2rgb(h);
		} else if (row == 2 && (col == 3 || col == 7)) {
			c *= WALLS[clamp(int(custom.b * 8.0 + 0.5), 0, 5)];
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
}
"""

## Цвета крыш: [тон, множитель насыщенности].
const ROOFS: Array[Vector2] = [
	Vector2(0.01, 1.0),   # 0 красная черепица
	Vector2(0.05, 0.9),   # 1 терракота
	Vector2(0.075, 0.6),  # 2 коричневая
	Vector2(0.33, 0.55),  # 3 зелёная
	Vector2(0.46, 0.9),   # 4 бирюзовая (как у Kenney)
	Vector2(0.6, 0.5),    # 5 сизая
	Vector2(0.6, 0.08),   # 6 графит
	Vector2(0.86, 0.4),   # 7 сливовая
]
## Наборы районов: какие крыши и стены встречаются (район — квадрат DISTRICT клеток).
const DISTRICTS: Array[Dictionary] = [
	{"roofs": [0, 1, 2], "walls": [0, 1, 2]},  # тёплый, европейский
	{"roofs": [5, 6, 4], "walls": [0, 4, 0]},  # северный
	{"roofs": [3, 4, 2], "walls": [0, 5, 1]},  # зелёный
	{"roofs": [1, 7, 0, 5], "walls": [1, 3, 2]},  # южный, пёстрый
]
const DISTRICT: int = 10

static var _materials: Dictionary[Texture2D, ShaderMaterial] = {}
static var _shader: Shader


## Цвет здания для INSTANCE_CUSTOM: по району и номеру здания, всегда один и тот же.
static func custom_for(building: BuildingInstance, data: BuildingData) -> Color:
	if data.zone == CityGrid.Zone.NONE:
		return Color(0, 0, 0, 0)
	var district: Dictionary = DISTRICTS[_hash(building.cell.x / DISTRICT, building.cell.y / DISTRICT, 7) % DISTRICTS.size()]
	var pick: int = _hash(building.id, building.cell.x, building.cell.y)
	var roofs: Array = district.roofs
	var walls: Array = district.walls
	var roof: Vector2 = ROOFS[roofs[pick % roofs.size()]]
	var wall: int = walls[(pick / 7) % walls.size()]
	return Color(roof.x, roof.y, wall / 8.0, 1.0)


## Меш с материалами-палитрами Kenney, заменёнными на перекрашивающий шейдер (общий на текстуру).
## Поверхности без текстуры (вывески, основания) не трогаются.
static func convert(mesh: Mesh) -> Mesh:
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return mesh
	for surface: int in array_mesh.get_surface_count():
		var material := array_mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		array_mesh.surface_set_material(surface, _material_for(material.albedo_texture))
	return array_mesh


static func _material_for(texture: Texture2D) -> ShaderMaterial:
	if not _materials.has(texture):
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter(&"palette", texture)
		_materials[texture] = material
	return _materials[texture]


static func _hash(a: int, b: int, c: int) -> int:
	var h: int = a * 73856093 ^ b * 19349663 ^ c * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
