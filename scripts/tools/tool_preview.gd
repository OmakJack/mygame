class_name ToolPreview
extends MultiMeshInstance3D
## Подсвечивает клетки, которые изменит текущая операция инструмента.

## Высота над землёй: выше дорог, ниже курсора.
const PREVIEW_HEIGHT: float = 0.05

var _material := StandardMaterial3D.new()


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * CityGrid.CELL_SIZE * 0.9
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func show_cells(cells: Array[Vector2i], color: Color) -> void:
	_material.albedo_color = color
	var grid: CityGrid = GameState.grid
	multimesh.instance_count = cells.size()
	for i: int in cells.size():
		var pos: Vector3 = grid.grid_to_world(cells[i]) + Vector3.UP * PREVIEW_HEIGHT
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))


func clear() -> void:
	multimesh.instance_count = 0
