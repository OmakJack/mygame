class_name CellCursor
extends MeshInstance3D
## Подсвечивает клетку под мышкой. build_tool берёт отсюда hovered_cell.

## Высота подсветки над землёй (выше дорог и превью инструмента).
const HIGHLIGHT_HEIGHT: float = 0.06

@export var highlight_color: Color = Color(1.0, 0.85, 0.2, 0.45)

## Клетка под мышкой. Имеет смысл только при has_cell == true.
var hovered_cell: Vector2i = Vector2i.ZERO
var has_cell: bool = false
## Клетка под мышкой без проверки границ (может быть за картой).
## Имеет смысл только при has_ground_hit == true — луч попал в плоскость земли.
var ground_cell: Vector2i = Vector2i.ZERO
var has_ground_hit: bool = false

var _ground_plane := Plane(Vector3.UP, 0.0)
var _material := StandardMaterial3D.new()


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * CityGrid.CELL_SIZE * 0.95
	mesh = quad
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = highlight_color
	material_override = _material
	visible = false


## Цвет подсветки (инструмент показывает так текущий режим).
func set_color(color: Color) -> void:
	_material.albedo_color = color


func _process(_delta: float) -> void:
	# Проверяем каждый кадр: клетка меняется и когда двигается камера, а не только мышь.
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var hit: Variant = _ground_plane.intersects_ray(from, dir)
	var grid: CityGrid = GameState.grid
	has_ground_hit = hit != null
	if has_ground_hit:
		ground_cell = grid.world_to_grid(hit)
	if not has_ground_hit or not grid.is_in_bounds(ground_cell):
		has_cell = false
		visible = false
		return
	hovered_cell = ground_cell
	has_cell = true
	visible = true
	position = grid.grid_to_world(hovered_cell) + Vector3.UP * HIGHLIGHT_HEIGHT
