extends MeshInstance3D
## Земля под картой: трава с мягкими пятнами (шум FastNoiseLite, без загрузок), за краем карты — темнее.
## Размер и положение берутся из GameState.grid.

## Поле вокруг карты, метры: чтобы у края не обрывалось в пустоту.
const MARGIN: float = 60.0

const SHADER_CODE: String = """
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 grass_dark : source_color = vec3(0.37, 0.58, 0.29);
uniform vec3 grass_light : source_color = vec3(0.44, 0.64, 0.33);
uniform vec3 dry_grass : source_color = vec3(0.58, 0.64, 0.36);
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform float map_size = 128.0;
uniform float outside_dim = 0.72;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Крупные пятна — светлее/темнее трава, редкие — сухая; мелкий шум — живость.
	float large = texture(noise, world_pos.xz * 0.012).r;
	float patches = texture(noise, world_pos.xz * 0.035 + vec2(0.37, 0.71)).r;
	float fine = texture(noise, world_pos.xz * 0.25 + vec2(0.13, 0.29)).r;
	vec3 color = mix(grass_dark, grass_light, smoothstep(0.3, 0.7, large));
	color = mix(color, dry_grass, smoothstep(0.62, 0.8, patches) * 0.3);
	color *= 0.93 + 0.12 * fine;
	// За краем карты — темнее, с мягким переходом шириной 3 м.
	vec2 inside_xz = smoothstep(vec2(-1.5), vec2(1.5), world_pos.xz)
			* (vec2(1.0) - smoothstep(vec2(map_size - 1.5), vec2(map_size + 1.5), world_pos.xz));
	color *= mix(outside_dim, 1.0, inside_xz.x * inside_xz.y);
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
"""

var _material := ShaderMaterial.new()


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	_material.set_shader_parameter(&"noise", texture)
	material_override = _material
	Events.grid_reset.connect(_resize)
	_resize()


func _resize() -> void:
	var size: float = GameState.grid.world_size()
	var plane := mesh as PlaneMesh
	plane.size = Vector2.ONE * (size + MARGIN * 2.0)
	position = Vector3(size * 0.5, 0.0, size * 0.5)
	_material.set_shader_parameter(&"map_size", size)
