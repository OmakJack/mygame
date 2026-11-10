class_name CellCursor
extends MeshInstance3D
## Подсвечивает клетку под мышкой. build_tool берёт отсюда hovered_cell.
## Над полосой свободной дороги (диагональ, дуга) подсвечивает её ячейку под углом дороги (hovered_slot):
## там игрок работает с ячейками, а не с клетками карты.

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
## Точка земли под мышкой (мир) — для дорог, которые ставятся не по клеткам (RoadTool).
var ground_point := Vector3.ZERO
## Мышь над панелью интерфейса.
var over_ui: bool = false
## Не показывать подсветку клетки (у инструмента дорог свой маркер), но считать клетку.
var suppressed: bool = false
## Ячейка свободной полосы под мышью или null.
var hovered_slot: FreeStrips.Slot = null

var _cell_mesh := PlaneMesh.new()
var _slot_mesh := ArrayMesh.new()
var _slot_shape := PackedVector2Array()

var _ground_plane := Plane(Vector3.UP, 0.0)
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_cell_mesh.size = Vector2.ONE * CityGrid.CELL_SIZE * 0.95
	mesh = _cell_mesh
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		ground_point = hit
		ground_cell = grid.world_to_grid(hit)
	# Над панелями UI курсор прячем, но ground_cell считаем дальше —
	# начатое протягивание не обрывается, если мышь заехала на панель.
	over_ui = get_viewport().gui_get_hovered_control() != null
	if over_ui or not has_ground_hit or not grid.is_in_bounds(ground_cell):
		has_cell = false
		hovered_slot = null
		visible = false
		return
	hovered_cell = ground_cell
	has_cell = true
	visible = not suppressed
	grid.ensure_strips()
	hovered_slot = grid.free_strips.slot_at_point(Vector2(ground_point.x, ground_point.z))
	if hovered_slot != null:
		_show_slot(hovered_slot)
	else:
		mesh = _cell_mesh
		position = grid.grid_to_world(hovered_cell) + Vector3.UP * HIGHLIGHT_HEIGHT


## Подсветка по форме ячейки (углы в мире).
func _show_slot(slot: FreeStrips.Slot) -> void:
	position = Vector3.UP * HIGHLIGHT_HEIGHT
	if mesh == _slot_mesh and _slot_shape == slot.corners:
		return
	_slot_shape = slot.corners
	var points := PackedVector3Array()
	for i: int in [0, 1, 2, 0, 2, 3]:
		var p: Vector2 = slot.corners[i].lerp(slot.center, 0.05)
		points.append(Vector3(p.x, 0.0, p.y))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	_slot_mesh.clear_surfaces()
	_slot_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = _slot_mesh
