extends MeshInstance3D
## Вода (фаза 9): одна плоскость на всю карту, шейдер рисует воду по маске клеток воды.
## Маска увеличена с бикубическим сглаживанием — берег идёт плавной линией, а не ступеньками;
## у кромки — полоска песка, к середине реки вода темнее. Вода меняется только с новой картой.

## Чуть выше земли (0) и ниже зон (0.006) и асфальта (0.02).
const HEIGHT: float = 0.004
## Во сколько раз маска подробнее карты (для плавного берега).
const MASK_SCALE: int = 8

const SHADER: String = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec3 deep : source_color = vec3(0.13, 0.36, 0.55);
uniform vec3 shallow : source_color = vec3(0.32, 0.62, 0.72);
uniform vec3 sand : source_color = vec3(0.86, 0.79, 0.6);
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float m = texture(mask, UV).r;
	if (m < 0.38) {
		discard;
	}
	float wave = sin(world.x * 1.9 + TIME * 1.1) * 0.5 + sin(world.z * 2.6 - TIME * 0.8) * 0.5;
	float ripple = sin((world.x + world.z) * 4.1 + TIME * 1.7);
	float water = smoothstep(0.47, 0.53, m);
	vec3 color = mix(shallow, deep, smoothstep(0.55, 0.95, m)) + vec3(0.03) * wave;
	ALBEDO = mix(sand, color, water);
	ROUGHNESS = mix(0.95, 0.1, water);
	SPECULAR = mix(0.2, 0.7, water);
	vec3 tilt = vec3(wave * 0.12 + ripple * 0.04, 0.0, ripple * 0.06) * water;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
}
"""

var _cells: int = 0


func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	var grid: CityGrid = GameState.grid
	_cells = grid.water.count(1)
	visible = _cells > 0
	if not visible:
		return
	var image := Image.create_from_data(grid.size, grid.size, false, Image.FORMAT_L8, _mask_bytes(grid))
	image.resize(grid.size * MASK_SCALE, grid.size * MASK_SCALE, Image.INTERPOLATE_CUBIC)
	(material_override as ShaderMaterial).set_shader_parameter(&"mask", ImageTexture.create_from_image(image))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * grid.world_size()
	mesh = plane
	position = Vector3(grid.world_size() * 0.5, HEIGHT, grid.world_size() * 0.5)


## Маска 0/255 по слою воды.
static func _mask_bytes(grid: CityGrid) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(grid.water.size())
	for i: int in grid.water.size():
		bytes[i] = 255 if grid.water[i] == 1 else 0
	return bytes


func water_cell_count() -> int:
	return _cells
