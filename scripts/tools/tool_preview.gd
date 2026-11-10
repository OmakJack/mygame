class_name ToolPreview
extends MultiMeshInstance3D
## Подсвечивает клетки, которые изменит текущая операция инструмента, и четырёхугольники под углом
## дороги (ячейки свободных полос, участки и здания у кривых дорог).

## Высота над землёй: выше дорог, ниже курсора.
const PREVIEW_HEIGHT: float = 0.05

var _material := StandardMaterial3D.new()
var _quads := MeshInstance3D.new()
var _quad_material := StandardMaterial3D.new()


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * CityGrid.CELL_SIZE * 0.9
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	quad.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quads.material_override = _quad_material
	_quads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quads)


func show_cells(cells: Array[Vector2i], color: Color) -> void:
	show_selection(cells, [], color)


## Клетки и четырёхугольники (углы в мире x, z) одним цветом.
func show_selection(cells: Array[Vector2i], quads: Array[PackedVector2Array], color: Color) -> void:
	var colors: Array[Color] = []
	colors.resize(cells.size())
	colors.fill(color)
	show_colored(cells, colors)
	if quads.is_empty():
		_quads.mesh = null
		return
	var points := PackedVector3Array()
	for quad: PackedVector2Array in quads:
		var center: Vector2 = (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
		for i: int in [0, 1, 2, 0, 2, 3]:
			var p: Vector2 = quad[i].lerp(center, 0.05)
			points.append(Vector3(p.x, PREVIEW_HEIGHT, p.y))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_quad_material.albedo_color = color
	_quads.mesh = mesh


## Сколько четырёхугольников показано (для проверок).
func quad_count() -> int:
	return _quads.mesh.surface_get_array_len(0) / 6 if _quads.mesh != null else 0


## Клетки каждая своим цветом (участки разметки — чередующимися оттенками).
func show_colored(cells: Array[Vector2i], colors: Array[Color]) -> void:
	var grid: CityGrid = GameState.grid
	multimesh.instance_count = cells.size()
	for i: int in cells.size():
		var pos: Vector3 = grid.grid_to_world(cells[i]) + Vector3.UP * PREVIEW_HEIGHT
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		multimesh.set_instance_color(i, colors[i])


func clear() -> void:
	multimesh.instance_count = 0
	_quads.mesh = null
