class_name ZoneVisualizer
extends MultiMeshInstance3D
## Раскраска клеток: один экземпляр на клетку (номер = CityGrid.index_of), цвет — по слою карты.
## Слои (клавиша V по кругу): зоны / свет / вода / службы.

enum Overlay { ZONES, POWER, WATER, SERVICES, TRAFFIC, LAND_VALUE, POLLUTION, NOISE }

const OVERLAY_NAMES: Dictionary[Overlay, String] = {
	Overlay.ZONES: "Зоны",
	Overlay.POWER: "Свет",
	Overlay.WATER: "Вода",
	Overlay.SERVICES: "Службы",
	Overlay.TRAFFIC: "Трафик",
	Overlay.LAND_VALUE: "Цена земли",
	Overlay.POLLUTION: "Загрязнение",
	Overlay.NOISE: "Шум",
}

## Высота зон: чуть над землёй, ниже линий сетки (0.01) и асфальта (0..0.02) — не срезает крыльца домов.
const ZONE_HEIGHT: float = 0.006
## Высота остальных слоёв: поверх дорог (разметка — 0.035), ниже превью (0.05).
const OVERLAY_HEIGHT: float = 0.04

const ZONE_COLORS: Dictionary[CityGrid.Zone, Color] = {
	CityGrid.Zone.NONE: Color(0, 0, 0, 0),
	CityGrid.Zone.RESIDENTIAL: Color(0.3, 0.85, 0.35, 0.3),
	CityGrid.Zone.COMMERCIAL: Color(0.3, 0.55, 0.95, 0.3),
	CityGrid.Zone.INDUSTRIAL: Color(0.95, 0.8, 0.25, 0.3),
	CityGrid.Zone.RESIDENTIAL_HIGH: Color(0.1, 0.6, 0.25, 0.4),
	CityGrid.Zone.COMMERCIAL_HIGH: Color(0.15, 0.3, 0.85, 0.4),
	CityGrid.Zone.OFFICE: Color(0.6, 0.35, 0.9, 0.35),
}
## Под построенным домом зона почти прозрачная: видны трава и тени, а пустые участки читаются ярче.
const BUILT_ALPHA: float = 0.08
## Зона без доступа к дороге: тот же цвет, но тусклее и прозрачнее.
const NO_ACCESS_DIM: float = 0.45
const NO_ACCESS_ALPHA: float = 0.25

const CLEAR := Color(0, 0, 0, 0)
const SERVED := Color(0.2, 0.85, 0.3, 0.75)
const UNSERVED := Color(1.0, 0.15, 0.15, 0.85)
## Станция / дорога с ресурсом для слоёв света и воды.
const POWER_SOURCE := Color(1.0, 0.85, 0.1, 0.9)
const POWER_ROAD := Color(1.0, 0.85, 0.1, 0.35)
const WATER_SOURCE := Color(0.2, 0.75, 1.0, 0.9)
const WATER_ROAD := Color(0.2, 0.75, 1.0, 0.35)
const NO_SUPPLY_ROAD := Color(0.4, 0.4, 0.4, 0.35)
## Слой служб: прозрачность растёт с числом служб, покрывающих клетку.
const COVERAGE_COLOR := Color(0.3, 0.9, 0.4)
const SERVICE_BUILDING := Color(1.0, 1.0, 1.0, 0.9)
## Слой трафика: дороги от зелёного через жёлтый к красному; дома с долгой дорогой — оранжевые.
const TRAFFIC_FREE := Color(0.2, 0.85, 0.3, 0.8)
const TRAFFIC_BUSY := Color(1.0, 0.85, 0.1, 0.85)
const TRAFFIC_JAM := Color(1.0, 0.15, 0.1, 0.9)
## С этой загрузки цвет идёт от жёлтого к красному.
const TRAFFIC_BUSY_RATIO: float = 0.7
const LONG_COMMUTE := Color(1.0, 0.45, 0.1)
## Цена земли: от красного (дёшево) через жёлтый к зелёному (дорого).
const VALUE_LOW := Color(0.9, 0.25, 0.2, 0.55)
const VALUE_MID := Color(0.98, 0.85, 0.25, 0.5)
const VALUE_HIGH := Color(0.2, 0.8, 0.35, 0.6)
## Загрязнение и шум: цвет, прозрачность растёт со значением.
const POLLUTION_COLOR := Color(0.45, 0.3, 0.15)
const NOISE_COLOR := Color(0.95, 0.45, 0.85)

var overlay: Overlay = Overlay.ZONES

## Слой служб: клетка → битовая маска покрывающих служб (пересчитывается при перерисовке).
var _service_mask := PackedByteArray()


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
	# Свет, вода и службы меняются на каждом пересчёте — перерисовываем слой целиком.
	Events.stats_changed.connect(func() -> void:
		if overlay != Overlay.ZONES:
			_repaint_all())
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"overlay_next"):
		set_overlay(((overlay + 1) % Overlay.size()) as Overlay)


func set_overlay(new_overlay: Overlay) -> void:
	overlay = new_overlay
	_rebuild()
	Events.overlay_changed.emit(overlay)


func _rebuild() -> void:
	var grid: CityGrid = GameState.grid
	multimesh.instance_count = grid.size * grid.size
	var height: float = ZONE_HEIGHT if overlay == Overlay.ZONES else OVERLAY_HEIGHT
	for y: int in grid.size:
		for x: int in grid.size:
			var cell := Vector2i(x, y)
			var pos: Vector3 = grid.grid_to_world(cell) + Vector3.UP * height
			multimesh.set_instance_transform(grid.index_of(cell), Transform3D(Basis.IDENTITY, pos))
	_repaint_all()


func _repaint_all() -> void:
	var grid: CityGrid = GameState.grid
	# По grid_reset stats_changed приходит раньше, чем мы пересобраны под новую карту.
	if multimesh.instance_count != grid.size * grid.size:
		return
	if overlay == Overlay.SERVICES:
		_build_service_mask(grid)
	for y: int in grid.size:
		for x: int in grid.size:
			_update_cell(Vector2i(x, y))


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	if cells.is_empty() or overlay != Overlay.ZONES:
		# Остальные слои перерисуются целиком по stats_changed.
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
	var color: Color
	match overlay:
		Overlay.ZONES:
			color = _zone_color(cell)
		Overlay.POWER:
			color = _utility_color(cell, true)
		Overlay.WATER:
			color = _utility_color(cell, false)
		Overlay.SERVICES:
			color = _service_color(cell)
		Overlay.TRAFFIC:
			color = _traffic_color(cell)
		Overlay.LAND_VALUE:
			color = _value_color(cell)
		Overlay.POLLUTION:
			color = _amount_color(GameState.land.pollution, cell, POLLUTION_COLOR)
		Overlay.NOISE:
			color = _amount_color(GameState.land.noise, cell, NOISE_COLOR)
	multimesh.set_instance_color(GameState.grid.index_of(cell), color)


func _zone_color(cell: Vector2i) -> Color:
	var grid: CityGrid = GameState.grid
	var zone_type: CityGrid.Zone = grid.get_zone(cell)
	var color: Color = ZONE_COLORS[zone_type]
	if zone_type != CityGrid.Zone.NONE and not grid.has_road_access(cell):
		color = color.darkened(NO_ACCESS_DIM)
		color.a = NO_ACCESS_ALPHA
	elif zone_type != CityGrid.Zone.NONE and grid.get_building_at(cell) != null:
		color.a = BUILT_ALPHA
	return color


## Свет (power = true) или вода: станции, здания со ресурсом и без, дороги с запасом.
func _utility_color(cell: Vector2i, power: bool) -> Color:
	var grid: CityGrid = GameState.grid
	if grid.is_road(cell):
		var component: int = GameState.network.component_of.get(cell, -1)
		var supplied: Dictionary[int, bool] = GameState.utilities.powered_components if power \
				else GameState.utilities.watered_components
		if supplied.has(component):
			return POWER_ROAD if power else WATER_ROAD
		return NO_SUPPLY_ROAD
	var building: BuildingInstance = grid.get_building_at(cell)
	if building == null:
		return CLEAR
	var data: BuildingData = BuildingCatalog.get_type(building.type_id)
	if data == null:
		return CLEAR
	if (data.power_supply if power else data.water_supply) > 0:
		# Станция работает, если есть дорога; водокачке ещё нужен свет.
		var working: bool = grid.has_building_road_access(building) and (power or building.powered)
		if not working:
			return UNSERVED
		return POWER_SOURCE if power else WATER_SOURCE
	if (data.power_use if power else data.water_use) == 0:
		return CLEAR
	return SERVED if (building.powered if power else building.has_water) else UNSERVED


func _traffic_color(cell: Vector2i) -> Color:
	var grid: CityGrid = GameState.grid
	var traffic: Traffic = GameState.traffic
	if grid.is_road(cell):
		var ratio: float = traffic.load_ratio(grid, grid.index_of(cell))
		if ratio <= 0.0:
			return NO_SUPPLY_ROAD
		if ratio < TRAFFIC_BUSY_RATIO:
			return TRAFFIC_FREE.lerp(TRAFFIC_BUSY, ratio / TRAFFIC_BUSY_RATIO)
		return TRAFFIC_BUSY.lerp(TRAFFIC_JAM, clampf((ratio - TRAFFIC_BUSY_RATIO) / (1.0 - TRAFFIC_BUSY_RATIO), 0.0, 1.0))
	var building: BuildingInstance = grid.get_building_at(cell)
	if building == null:
		return CLEAR
	var badness: float = traffic.home_badness.get(building.id, 0.0)
	if badness <= 0.0:
		return CLEAR
	var color: Color = LONG_COMMUTE
	color.a = 0.35 + 0.55 * badness
	return color


func _service_color(cell: Vector2i) -> Color:
	var grid: CityGrid = GameState.grid
	var building: BuildingInstance = grid.get_building_at(cell)
	if building != null:
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data != null and data.service != BuildingData.Service.NONE:
			return SERVICE_BUILDING
	var mask: int = _service_mask[grid.index_of(cell)]
	if mask == 0:
		return CLEAR
	var count: int = 0
	while mask > 0:
		count += mask & 1
		mask >>= 1
	var color: Color = COVERAGE_COLOR
	color.a = 0.15 + 0.15 * count
	return color


## Для каждой клетки — какие работающие службы её покрывают (бит = номер службы).
func _build_service_mask(grid: CityGrid) -> void:
	_service_mask.resize(grid.size * grid.size)
	_service_mask.fill(0)
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or not Services.is_active(grid, building, data):
			continue
		var r: int = data.service_radius
		for sc: Vector2i in building.cells():
			for dy: int in range(-r, r + 1):
				var reach: int = r - absi(dy)
				for dx: int in range(-reach, reach + 1):
					var cell: Vector2i = sc + Vector2i(dx, dy)
					if grid.is_in_bounds(cell):
						_service_mask[grid.index_of(cell)] |= 1 << data.service


## Цена земли на суше; на воде и дорогах — пусто.
func _value_color(cell: Vector2i) -> Color:
	var grid: CityGrid = GameState.grid
	if grid.is_water(cell) or grid.is_road(cell):
		return CLEAR
	# Жёлтый — обычная земля (LandValue.BASE_VALUE = 25), ниже — краснее, выше — зеленее до 75.
	var value: float = GameState.land.value_at(GameState.land.land_value, grid, cell)
	if value < LandValue.BASE_VALUE:
		return VALUE_LOW.lerp(VALUE_MID, value / LandValue.BASE_VALUE)
	return VALUE_MID.lerp(VALUE_HIGH, clampf((value - LandValue.BASE_VALUE) / 50.0, 0.0, 1.0))


## Загрязнение или шум: чем больше, тем гуще цвет; слабое (< 5) — не рисуем.
func _amount_color(layer: PackedByteArray, cell: Vector2i, base: Color) -> Color:
	var amount: int = GameState.land.value_at(layer, GameState.grid, cell)
	if amount < 5:
		return CLEAR
	var color: Color = base
	color.a = 0.15 + 0.7 * amount / 100.0
	return color
