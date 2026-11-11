extends SceneTree
## Снос дорог у кривых: бульдозер сносит свободную дорогу (диагональ, дуга) целым отрезком, от узла
## до узла, — под мышью её полотно подсвечено; соседние дороги и перекрёсток остаются; щелчок по
## полотну не задевает здание рядом; прямоугольник берёт отрезок, если задел его клетки; дорога по
## сетке сносится клетками, как раньше.

const STREET: int = 1


func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var sm: Node = root.get_node("SaveManager")
	sm.save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	sm.with_river = false
	sm.with_highway = false
	sm.new_city()
	await process_frame
	var g: CityGrid = gs.grid
	var graph: RoadGraph = g.roads
	var tool: Node = main.get_node("BuildTool")
	var cursor: Node3D = tool.cursor
	gs.money = 100000
	gs.rank = 3
	var c := func(x: float, y: float) -> Vector2: return Vector2((x + 0.5) * 2.0, (y + 0.5) * 2.0)
	var road := func(a: Vector2, b: Vector2, ctrl: Variant = null) -> bool:
		graph.sync(g)
		var pa := RoadGraph.RoadPoint.new(a)
		pa.node = graph.node_near(a, 1.0)
		if pa.node == -1: pa.segment = graph.segment_near(a, 0.8)
		var pb := RoadGraph.RoadPoint.new(b)
		pb.node = graph.node_near(b, 1.0)
		if pb.node == -1: pb.segment = graph.segment_near(b, 0.8)
		if pa.node != -1: pa.pos = graph.nodes[pa.node].pos
		if pb.node != -1: pb.pos = graph.nodes[pb.node].pos
		var plan: RoadGraph.Plan = graph.plan(g, pa, pb, ctrl, STREET, 1000000)
		if not plan.ok:
			print("refused ", a, " → ", b, ": ", plan.reason)
			return false
		ev.cells_changed.emit(graph.build(g, plan))
		graph.sync(g)
		return true
	# Улица по сетке; от неё диагональ с продолжением под другим углом и дуга.
	var built: bool = road.call(c.call(4, 50), c.call(60, 50))
	built = road.call(c.call(10, 50), c.call(34, 26)) and built
	built = road.call(c.call(34, 26), c.call(48, 22)) and built
	built = road.call(c.call(40, 50), c.call(60, 30), c.call(40, 30)) and built
	check.call("roads built", built)
	var diagonal: int = graph.segment_near(c.call(22, 38), 0.3)
	var piece: int = graph.segment_near(c.call(41, 24), 0.4)
	var arc_mid: Vector2 = RoadGraph.bezier(c.call(40, 50), c.call(40, 30), c.call(60, 30), 0.5)
	var arc: int = graph.segment_near(arc_mid, 0.3)
	var street_cells := func() -> int:
		var count: int = 0
		for x in range(4, 61):
			if g.is_road(Vector2i(x, 50)): count += 1
		return count
	var point := func(pos: Vector2) -> void:
		cursor.has_cell = true
		cursor.has_ground_hit = true
		cursor.over_ui = false
		cursor.hovered_slot = g.free_strips.slot_at_point(pos)
		cursor.ground_point = Vector3(pos.x, 0.0, pos.y)
		cursor.ground_cell = RoadGraph.cell_of(pos)
		cursor.hovered_cell = cursor.ground_cell
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	var click := func(pos: Vector2) -> void:
		point.call(pos)
		tool._unhandled_input(press)
		tool._input(release)

	# --- Под бульдозером: кривая дорога подсвечена целиком, дорога по сетке — клеткой ---
	g.ensure_strips()
	tool._set_mode(tool.Mode.BULLDOZE)
	point.call(c.call(22, 38))
	tool._process(0.0)
	check.call("pointer on a diagonal: the whole piece highlighted (%d quads), cell marker hidden" % tool.preview.quad_count(),
			tool._hover_segment == diagonal and tool.preview.quad_count() > 30 and cursor.suppressed)
	point.call(c.call(25, 50))
	tool._process(0.0)
	check.call("pointer on a grid street: the cell marker, nothing highlighted",
			tool._hover_segment == -1 and tool.preview.quad_count() == 0 and not cursor.suppressed)

	# --- Служба у продолжения диагонали — щелчок по полотну рядом её не задевает ---
	var strips: FreeStrips = g.free_strips
	var seat: FreeStrips.Slot = null
	for col in range(1, strips.frames[piece].count - 1):
		for side in [1, -1]:
			var probe: FreeStrips.Slot = strips.slot_in(piece, side, col, 1)
			if seat == null and probe != null and not probe.cells.is_empty(): seat = probe
	tool._set_mode(tool.Mode.PLACE, &"water_tower_01")
	cursor.has_cell = true
	cursor.hovered_slot = seat
	cursor.hovered_cell = seat.cells[0]
	tool._dragging = true
	tool._drag_start = seat.cells[0]
	tool._update_drag(seat.cells[0])
	tool._apply()
	tool._end_drag()
	var tower: BuildingInstance = null
	for b: BuildingInstance in g.buildings.values(): tower = b
	check.call("water tower placed by the road", tower != null and tower.is_free())

	# --- Щелчок по диагонали: отрезок снесён целиком, соседи и перекрёсток на месте ---
	var own: Array[Vector2i] = []
	for cell: Vector2i in graph.segments[diagonal].cells:
		if graph.owners_of(cell).size() == 1: own.append(cell)
	var before: int = street_cells.call()
	tool._set_mode(tool.Mode.BULLDOZE)
	point.call(c.call(22, 38))
	tool._unhandled_input(press)
	var picked: bool = tool._drag_segments == [diagonal] and tool._drag_cells.is_empty() and tool.preview.quad_count() > 30
	tool._input(release)
	var gone: bool = not graph.segments.has(diagonal) and graph.segment_near(c.call(22, 38), 1.0) == -1
	for cell: Vector2i in own:
		if g.is_road(cell): gone = false
	check.call("click on the diagonal: the whole piece is gone (%d cells)" % own.size(), picked and gone and own.size() > 20)
	check.call("the street it joined is intact (%d cells), the junction cell too" % street_cells.call(),
			street_cells.call() == before and g.is_road(Vector2i(10, 50)))
	check.call("the next piece of the same road stays", graph.segments.has(piece) and graph.segment_near(c.call(41, 24), 0.4) == piece)
	await process_frame
	var rv: Node = main.get_node("RoadVisualizer")
	check.call("its ribbon is no longer drawn", not rv._segments.has(diagonal))

	# --- Щелчок по краю полотна у здания: сносится дорога, здание стоит ---
	g.ensure_strips()
	var edge: Vector2 = tower.center + Vector2(-sin(tower.yaw), -cos(tower.yaw)) * 1.2
	check.call("the point is on the ribbon, right by the building", graph.segment_at(edge) == piece
			and edge.distance_to(tower.center) < 1.5)
	click.call(edge)
	check.call("click on the ribbon edge: road removed, the building by it stays",
			not graph.segments.has(piece) and g.buildings.has(tower.id))
	check.call("without the road the building has no access", not g.has_building_road_access(tower))

	# --- Прямоугольник задел клетки дуги — дуга сносится целиком; полосы и ячейки её зон уходят ---
	g.ensure_strips()
	var arc_slots: int = 0
	for slot: FreeStrips.Slot in g.free_strips.slots:
		if slot.segment == arc: arc_slots += 1
	var arc_cells: Array[Vector2i] = graph.segments[arc].cells.duplicate()
	var hit_cell: Vector2i = RoadGraph.cell_of(arc_mid)
	cursor.has_cell = false
	tool._set_mode(tool.Mode.BULLDOZE)
	tool._dragging = true
	tool._drag_start = hit_cell - Vector2i(2, 2)
	tool._update_drag(hit_cell + Vector2i(2, 2))
	var marked: bool = tool._drag_segments == [arc] and tool.preview.quad_count() > 20
	var skips_road_cells: bool = true
	for cell: Vector2i in tool._drag_cells:
		if arc_cells.has(cell): skips_road_cells = false
	tool._apply()
	tool._end_drag()
	var far_end: Vector2i = RoadGraph.cell_of(c.call(58, 30))
	g.ensure_strips()
	var left_slots: int = 0
	for slot: FreeStrips.Slot in g.free_strips.slots:
		if slot.segment == arc: left_slots += 1
	check.call("rectangle over a part of the arc: the whole arc is marked, its cells go with it", marked and skips_road_cells)
	check.call("the arc is gone to its far end, its zone strips too (%d → %d slots)" % [arc_slots, left_slots],
			not graph.segments.has(arc) and not g.is_road(far_end) and arc_slots > 100 and left_slots == 0
			and street_cells.call() == before)

	# --- Дорога по сетке: клетками, как раньше, — из неё вырезается кусок ---
	click.call(c.call(25, 50))
	check.call("click on a grid street: one cell removed, the rest stays",
			not g.is_road(Vector2i(25, 50)) and g.is_road(Vector2i(24, 50)) and g.is_road(Vector2i(26, 50))
			and street_cells.call() == before - 1)
	tool._dragging = true
	tool._drag_start = Vector2i(30, 49)
	tool._update_drag(Vector2i(34, 51))
	var by_cells: bool = tool._drag_segments.is_empty() and tool._drag_cells.size() == 15
	tool._apply()
	tool._end_drag()
	check.call("rectangle over a grid street: its cells only", by_cells and street_cells.call() == before - 6
			and g.is_road(Vector2i(35, 50)))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
