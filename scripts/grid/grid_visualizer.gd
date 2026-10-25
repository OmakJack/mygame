extends MeshInstance3D
## Рисует линии сетки на земле по размеру GameState.grid.
## Видна только пока выбран инструмент: в обычном режиме картинка чистая.

## Высота линий над землёй, чтобы не мерцали.
const LINE_HEIGHT: float = 0.01

@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.18)


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = line_color
	material_override = material
	visible = false
	Events.grid_reset.connect(_rebuild)
	Events.tool_mode_changed.connect(func(mode: int, _type_id: StringName) -> void:
		visible = mode != BuildTool.Mode.NONE)
	_rebuild()


func _rebuild() -> void:
	var grid: CityGrid = GameState.grid
	var length: float = grid.world_size()
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i: int in grid.size + 1:
		var offset: float = i * CityGrid.CELL_SIZE
		# Линия вдоль X и линия вдоль Z.
		lines.surface_add_vertex(Vector3(0.0, LINE_HEIGHT, offset))
		lines.surface_add_vertex(Vector3(length, LINE_HEIGHT, offset))
		lines.surface_add_vertex(Vector3(offset, LINE_HEIGHT, 0.0))
		lines.surface_add_vertex(Vector3(offset, LINE_HEIGHT, length))
	lines.surface_end()
	mesh = lines
