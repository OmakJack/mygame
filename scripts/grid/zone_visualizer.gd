extends MultiMeshInstance3D
## Раскрашивает зоны. Один экземпляр на клетку (номер = CityGrid.index_of),
## цвет экземпляра — цвет зоны; без зоны — прозрачный.

## Высота над землёй: выше линий сетки (0.01), ниже тротуаров (0.02).
const ZONE_HEIGHT: float = 0.015

const ZONE_COLORS: Dictionary[CityGrid.Zone, Color] = {
	CityGrid.Zone.NONE: Color(0, 0, 0, 0),
	CityGrid.Zone.RESIDENTIAL: Color(0.25, 0.8, 0.3, 0.45),
	CityGrid.Zone.COMMERCIAL: Color(0.25, 0.5, 0.95, 0.45),
	CityGrid.Zone.INDUSTRIAL: Color(0.95, 0.8, 0.2, 0.45),
}
## Зона без доступа к дороге: тот же цвет, но тусклее и прозрачнее.
const NO_ACCESS_DIM: float = 0.45
const NO_ACCESS_ALPHA: float = 0.25


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * CityGrid.CELL_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Events.cells_changed.connect(_on_cells_changed)
	Events.grid_reset.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	var grid: CityGrid = GameState.grid
	multimesh.instance_count = grid.size * grid.size
	for y: int in grid.size:
		for x: int in grid.size:
			var cell := Vector2i(x, y)
			var pos: Vector3 = grid.grid_to_world(cell) + Vector3.UP * ZONE_HEIGHT
			multimesh.set_instance_transform(grid.index_of(cell), Transform3D(Basis.IDENTITY, pos))
			_update_cell(cell)


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	# Доступ к дороге мог измениться у соседей в радиусе ROAD_ACCESS_RANGE.
	# Перекрашиваем либо общий прямоугольник, либо квадрат вокруг каждой клетки — что меньше
	# (рост в разных углах карты дал бы прямоугольник на всю карту).
	var r: int = CityGrid.ROAD_ACCESS_RANGE
	var area := Rect2i(cells[0], Vector2i.ZERO)
	for cell: Vector2i in cells:
		area = area.expand(cell)
	# Rect2i.end не входит в прямоугольник после expand — считаем его включительно.
	var area_cells: int = (area.size.x + 1 + 2 * r) * (area.size.y + 1 + 2 * r)
	var squares_cells: int = cells.size() * (2 * r + 1) * (2 * r + 1)
	if squares_cells < area_cells:
		for cell: Vector2i in cells:
			_update_rect(cell - Vector2i(r, r), cell + Vector2i(r, r))
	else:
		_update_rect(area.position - Vector2i(r, r), area.end + Vector2i(r, r))


## Перекрашивает клетки от top_left до bottom_right включительно (обрезая по карте).
func _update_rect(top_left: Vector2i, bottom_right: Vector2i) -> void:
	var grid: CityGrid = GameState.grid
	var from: Vector2i = grid.clamp_to_bounds(top_left)
	var to: Vector2i = grid.clamp_to_bounds(bottom_right)
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			_update_cell(Vector2i(x, y))


func _update_cell(cell: Vector2i) -> void:
	var grid: CityGrid = GameState.grid
	var zone_type: CityGrid.Zone = grid.get_zone(cell)
	var color: Color = ZONE_COLORS[zone_type]
	if zone_type != CityGrid.Zone.NONE and not grid.has_road_access(cell):
		color = color.darkened(NO_ACCESS_DIM)
		color.a = NO_ACCESS_ALPHA
	multimesh.set_instance_color(grid.index_of(cell), color)
