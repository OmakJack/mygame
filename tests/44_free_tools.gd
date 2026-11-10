extends SceneTree
## Инструменты у кривых дорог: зона красится ячейками полосы, а не клетками карты (прямоугольником —
## и ячейки внутри, от ячейки — вдоль дороги), сетки карты у зон нет; служба встаёт под углом дороги;
## слои «Свет» и «Трафик» красят само полотно, а дом под углом — его прямоугольником; снос и «Инфо»
## находят дом под углом по участку; сохранение держит службу и её участок.

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
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var EC: GDScript = load("res://scripts/simulation/economy.gd")
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
	var zv: Node = main.get_node("ZoneVisualizer")
	var rv: Node = main.get_node("RoadVisualizer")
	var lines: Node3D = main.get_node("GridVisualizer")
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
	# Улица по сетке, от неё диагональ; дуга отдельно, соединена с улицей.
	var built: bool = road.call(c.call(4, 50), c.call(60, 50))
	built = road.call(c.call(10, 50), c.call(34, 26)) and built
	built = road.call(c.call(40, 50), c.call(60, 30), c.call(40, 30)) and built
	check.call("roads built", built)
	var diagonal: int = graph.segment_near(c.call(22, 38), 0.3)
	var arc: int = graph.segment_near(RoadGraph.bezier(c.call(40, 50), c.call(40, 30), c.call(60, 30), 0.5), 0.3)
	g.ensure_strips()
	var strips: FreeStrips = g.free_strips
	var count: int = strips.frames[diagonal].count

	# --- Сетка карты: у зон её нет, у сноса и служб — есть ---
	tool._set_mode(tool.Mode.ZONE_R)
	var hidden: bool = not lines.visible
	tool._set_mode(tool.Mode.BULLDOZE)
	check.call("map grid: hidden for zones, shown for bulldozer", hidden and lines.visible)

	# --- Прямоугольник клеток берёт и ячейки внутри, даже без клеток ---
	var in_rect := func(a: Vector2i, b: Vector2i) -> Array:
		return strips.slots_in(Rect2(Vector2(a) * 2.0, Vector2(b - a + Vector2i.ONE) * 2.0))
	var from := Vector2i(12, 30)
	var to := Vector2i(26, 44)
	var expect: Array = in_rect.call(from, to)
	var bare: int = 0
	for slot: FreeStrips.Slot in expect:
		if slot.cells.is_empty(): bare += 1
	var money: int = gs.money
	tool._set_mode(tool.Mode.ZONE_R); tool._dragging = true; tool._drag_start = from
	tool._update_drag(to)
	var grid_cells: int = tool._drag_cells.size()
	check.call("rectangle preview: slots as quads (%d), grid cells apart (%d)" % [tool.preview.quad_count(), grid_cells],
			tool.preview.quad_count() == expect.size() and tool._drag_slots.size() == expect.size())
	tool._apply(); tool._end_drag()
	var painted: bool = not expect.is_empty() and bare > 0
	for slot: FreeStrips.Slot in expect:
		if slot.zone != CityGrid.Zone.RESIDENTIAL: painted = false
	check.call("rectangle zones every slot inside (%d, %d of them without cells)" % [expect.size(), bare], painted)
	check.call("a slot costs like a cell (%d $)" % (money - gs.money),
			money - gs.money == (expect.size() + grid_cells) * EC.ZONE_COST)

	# --- От ячейки — вдоль дороги: колонки × ряды своей стороны ---
	var along := func(mode: int, segment: int, side: int, col0: int, row0: int, col1: int, row1: int) -> void:
		tool._set_mode(mode); tool._dragging = true
		tool._drag_start = RoadGraph.cell_of(strips.slot_in(segment, side, col0, row0).center)
		tool._drag_anchor.assign([segment, side, col0, row0])
		tool._drag_strip = Vector2i(segment, side)
		tool._drag_coords = Vector2i(col1, row1)
		tool._update_drag(tool._drag_start)
	var first: int = count / 2
	along.call(tool.Mode.ZONE_C, diagonal, 1, first, 1, first + 5, 2)
	check.call("along the road: 6 columns × 2 rows in the preview (%d)" % tool.preview.quad_count(),
			tool.preview.quad_count() == 12 and tool._drag_cells.is_empty())
	tool._apply(); tool._end_drag()
	var commercial: int = 0
	var only_there: bool = true
	for slot: FreeStrips.Slot in strips.slots:
		if slot.zone != CityGrid.Zone.COMMERCIAL: continue
		commercial += 1
		if slot.segment != diagonal or slot.side != 1 or slot.col < first or slot.col > first + 5 or slot.row > 2:
			only_there = false
	check.call("along the road: exactly those slots zoned (%d)" % commercial, commercial == 12 and only_there)
	# Мышь ушла с полосы — колонка и ряд прижимаются к её краям.
	var far: FreeStrips.Slot = strips.slot_in(diagonal, 1, first, 4)
	var beyond: Vector2 = far.center - far.front * 30.0
	check.call("pointer off the strip: clamped to its last row", strips.coords_at(diagonal, 1, beyond) == Vector2i(first, 4)
			and strips.coords_at(diagonal, 1, c.call(4, 60)).x == 0)
	# Снять зону — тоже ячейками.
	along.call(tool.Mode.DEZONE, diagonal, 1, first, 1, first + 5, 2)
	tool._apply(); tool._end_drag()
	var cleared: bool = true
	for col in range(first, first + 6):
		if strips.slot_in(diagonal, 1, col, 1).zone != CityGrid.Zone.NONE: cleared = false
	check.call("dezone along the road", cleared)

	# --- То же мышью: нажали на ячейке, повели вдоль дороги, отпустили ---
	var cursor: Node3D = tool.cursor
	var point := func(slot: FreeStrips.Slot) -> void:
		cursor.has_cell = true
		cursor.has_ground_hit = true
		cursor.over_ui = false
		cursor.hovered_slot = slot
		cursor.ground_point = Vector3(slot.center.x, 0.0, slot.center.y)
		cursor.ground_cell = RoadGraph.cell_of(slot.center)
		cursor.hovered_cell = cursor.ground_cell
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	tool._set_mode(tool.Mode.ZONE_I)
	point.call(strips.slot_in(diagonal, -1, first, 1))
	tool._unhandled_input(press)
	var started: bool = tool._dragging and tool._drag_anchor == [diagonal, -1, first, 1] and tool.preview.quad_count() == 1
	point.call(strips.slot_in(diagonal, -1, first + 3, 3))
	tool._process(0.0)
	var stretched: bool = tool.preview.quad_count() == 12
	tool._input(release)
	var industrial: int = 0
	for slot: FreeStrips.Slot in strips.slots:
		if slot.zone == CityGrid.Zone.INDUSTRIAL and slot.segment == diagonal and slot.side == -1: industrial += 1
	check.call("mouse: press on a slot, drag along the road, release — 4 columns × 3 rows zoned (%d)" % industrial,
			started and stretched and industrial == 12 and not tool._dragging and tool.preview.quad_count() == 0)
	# Дорога в несколько щелчков — цепочка отрезков: зона тянется через узел по той же стороне.
	var joined: bool = road.call(c.call(34, 26), c.call(48, 22))
	g.ensure_strips()
	var next_piece: int = graph.segment_near(c.call(41, 24), 0.4)
	check.call("road continued: a chain of two pieces", joined and next_piece != -1 and next_piece != diagonal
			and strips.chain(diagonal, next_piece).size() == 2 and strips.chain(diagonal, arc).size() > 2)
	var start_col: int = strips.frames[diagonal].count - 3
	while start_col > 0 and strips.slot_in(diagonal, 1, start_col, 1) == null: start_col -= 1
	tool._set_mode(tool.Mode.ZONE_O)
	point.call(strips.slot_in(diagonal, 1, start_col, 1))
	tool._unhandled_input(press)
	var over_next: FreeStrips.Slot = null
	for side in [1, -1]:
		var probe: FreeStrips.Slot = strips.slot_in(next_piece, side, 3, 2)
		if probe != null and not tool._chain_to(next_piece, side).is_empty(): over_next = probe
	var other_side: FreeStrips.Slot = strips.slot_in(next_piece, -over_next.side, 3, 2) if over_next != null else null
	if over_next != null:
		point.call(over_next)
		tool._process(0.0)
	var on_first: int = 0
	var on_next: int = 0
	var elsewhere: int = 0
	for slot: FreeStrips.Slot in tool._drag_slots:
		if slot.segment == diagonal and slot.side == 1 and slot.col >= start_col and slot.row <= 2: on_first += 1
		elif slot.segment == next_piece and slot.side == over_next.side and slot.col <= 3 and slot.row <= 2: on_next += 1
		else: elsewhere += 1
	check.call("drag through a node: slots of both pieces, same side of the road (%d + %d, %d elsewhere)" % [on_first, on_next, elsewhere],
			over_next != null and on_first >= 3 and on_next >= 4 and elsewhere == 0)
	# Мышь перешла через дорогу — выделение остаётся на своей стороне.
	if other_side != null:
		point.call(other_side)
		tool._process(0.0)
	var stays: bool = true
	for slot: FreeStrips.Slot in tool._drag_slots:
		if slot.segment == next_piece and slot.side != over_next.side: stays = false
	check.call("pointer across the road: selection stays on its side", other_side != null and stays and not tool._drag_slots.is_empty())
	tool._input(release)
	var shown: FreeStrips.Slot = strips.slot_in(diagonal, -1, first, 1)
	cursor._show_slot(shown)
	check.call("pointer highlight takes the shape of the slot", cursor.mesh == cursor._slot_mesh
			and cursor.mesh.get_aabb().grow(0.1).has_point(Vector3(shown.center.x, 0.0, shown.center.y))
			and cursor.mesh.get_aabb().size.x > 2.2)

	# --- Служба у кривой — под её углом: снаружи дуги и внутри ---
	var arc_count: int = strips.frames[arc].count
	var hover := func(slot: FreeStrips.Slot) -> Vector2i:
		var cell: Vector2i = slot.cells[0] if not slot.cells.is_empty() else RoadGraph.cell_of(slot.center)
		tool.cursor.hovered_slot = slot
		tool.cursor.has_cell = true
		tool.cursor.hovered_cell = cell
		return cell
	var place := func(type: StringName, side: int, col: int) -> BuildingInstance:
		tool._set_mode(tool.Mode.PLACE, type)
		var cell: Vector2i = hover.call(strips.slot_in(arc, side, col, 1))
		tool._dragging = true; tool._drag_start = cell
		tool._update_drag(cell)
		var ids: Array = g.buildings.keys()
		tool._apply()
		tool._end_drag()
		for id: int in g.buildings:
			if not ids.has(id): return g.buildings[id]
		return null
	money = gs.money
	var plant: BuildingInstance = place.call(&"power_plant_01", 1, arc_count / 2)
	var tower: BuildingInstance = place.call(&"water_tower_01", -1, arc_count / 2)
	var station: BuildingInstance = place.call(&"fire_02", -1, arc_count / 2 + 4)
	var stands := func(b: BuildingInstance) -> bool:
		if b == null or not b.is_free() or not g.has_building_road_access(b) or g.lot_of(b) == null: return false
		var segment: RoadGraph.Segment = graph.segments[arc]
		var curve: PackedVector2Array = graph.curve(segment)
		var foot: Vector2 = RoadGraph.bezier(curve[0], curve[1], curve[2], graph.nearest_on(segment, b.center).x)
		if Vector2(-sin(b.yaw), -cos(b.yaw)).dot((foot - b.center).normalized()) < 0.97: return false
		for p: Vector2 in g.free_footprint(b):
			if graph.nearest_on(segment, p).y < RoadTypes.HALF_WIDTH[STREET] - 0.05: return false
		for cell: Vector2i in b.cells():
			if g.get_zone(cell) != CityGrid.Zone.NONE: return false
		return true
	check.call("power plant inside the arc: at the road angle, off the ribbon", stands.call(plant))
	check.call("water tower outside the arc", stands.call(tower))
	check.call("fire station 2×1 at the road angle", stands.call(station))
	var costs: int = 0
	for type: StringName in [&"power_plant_01", &"water_tower_01", &"fire_02"]: costs += BuildingCatalog.get_type(type).cost
	check.call("services paid once (%d $)" % (money - gs.money), money - gs.money == costs)
	tool._set_mode(tool.Mode.PLACE, &"water_tower_01")
	var taken: FreeStrips.Slot = strips.slot_at_point(tower.center) if tower != null else null
	check.call("its slots are taken: no second building, no zone there", taken != null and strips.occupied.has(taken.id)
			and not tool._can_place(hover.call(taken)) and not g.can_zone_slot(taken, CityGrid.Zone.RESIDENTIAL))
	# У улицы по сетке — по клеткам, как раньше; у кривой клетка ячейки ведёт к постановке под углом.
	tool.cursor.hovered_slot = null
	tool.cursor.hovered_cell = Vector2i(-9, -9)
	var axis: Vector2 = RoadGraph.bezier(c.call(40, 50), c.call(40, 30), c.call(60, 30), 0.3)
	check.call("ribbon test: on the road and its edge, not 3 m away", graph.on_ribbon(axis) and graph.on_ribbon(axis + Vector2(0.9, 0.0))
			and not graph.on_ribbon(c.call(30, 46)) and graph.on_ribbon(c.call(30, 51), 1.1) and not graph.on_ribbon(c.call(30, 51), 0.6))
	var spare_cell: Vector2i = Vector2i(-1, -1)
	for col in range(2, arc_count - 2):
		var probe: FreeStrips.Slot = strips.slot_in(arc, -1, col, 2)
		if probe != null and not probe.cells.is_empty() and not strips.occupied.has(probe.id) and spare_cell.x < 0:
			spare_cell = probe.cells[0]
	check.call("a cell of a strip along a curve: placed at the road angle, not by cells",
			spare_cell.x >= 0 and not tool._free_place(spare_cell).is_empty())
	check.call("by cells next to a grid street: as before", tool._can_place(Vector2i(50, 51)) and tool._free_place(Vector2i(50, 51)).is_empty())

	# --- Слои: красится само полотно, дом под углом — прямоугольником ---
	ev.cells_changed.emit([Vector2i(50, 51)] as Array[Vector2i])
	await process_frame
	var arc_cell: Vector2i = graph.segments[arc].cells[graph.segments[arc].cells.size() / 2]
	zv.set_overlay(zv.Overlay.POWER)
	await process_frame
	check.call("power layer: the ribbon of the arc is tinted, its cells are not",
			rv.tint_at(arc_cell).is_equal_approx(zv.POWER_ROAD) and zv.multimesh.get_instance_color(g.index_of(arc_cell)).a == 0.0)
	var shapes: Mesh = zv._slots.mesh
	check.call("power layer: buildings at an angle drawn as their own rectangles (%d)" % (shapes.surface_get_array_len(0) / 6 if shapes != null else 0),
			shapes != null and shapes.surface_get_array_len(0) == 3 * 6
			and zv.multimesh.get_instance_color(g.index_of(plant.cells()[0])).a == 0.0)
	zv.set_overlay(zv.Overlay.TRAFFIC)
	await process_frame
	check.call("traffic layer: ribbon tinted", rv.tint_at(arc_cell).a > 0.0)
	zv.set_overlay(zv.Overlay.ZONES)
	await process_frame
	check.call("zones layer: no tint on roads", rv.tint_at(arc_cell).a == 0.0)

	# --- Сохранение: служба под углом, её участок и зоны ячеек ---
	var loaded = CS.from_dict(JSON.parse_string(JSON.stringify(CS.to_dict(g, "C3", 1000, 10, 0, 0))))
	if not loaded.warnings.is_empty(): print("   warnings: ", loaded.warnings)
	var g2: CityGrid = loaded.grid if loaded.ok else null
	var kept: bool = g2 != null and loaded.warnings.is_empty()
	if kept:
		g2.ensure_strips()
		var plant2: BuildingInstance = g2.buildings.get(plant.id)
		kept = plant2 != null and plant2.is_free() and g2.lot_of(plant2) != null \
				and g2.free_strips.occupied.size() == strips.occupied.size()
		for i in mini(strips.slots.size(), g2.free_strips.slots.size()):
			if strips.slots[i].zone != g2.free_strips.slots[i].zone: kept = false
	check.call("save/load: service at an angle keeps its lot, slot zones kept", kept)

	# --- «Инфо» и снос находят дом под углом по участку ---
	var lot: CityGrid.Lot = g.lot_of(station)
	var part: FreeStrips.Slot = strips.slot_at_point(station.center)
	hover.call(part)
	tool.cursor.hovered_cell = Vector2i(0, 0)
	check.call("info: a click on the lot opens its building", g.get_building_or_yard(tool._inspect_cell()) == station)
	tool._set_mode(tool.Mode.BULLDOZE)
	tool._dragging = true
	tool._drag_start = Vector2i(0, 0)
	tool.cursor.hovered_cell = Vector2i(0, 0)
	tool._update_drag(Vector2i(0, 0))
	check.call("bulldozer preview: the lot under the pointer", tool.preview.quad_count() == 1 and tool._drag_cells.has(lot.shape[0]))
	tool._apply(); tool._end_drag()
	check.call("bulldozer removes the building at an angle, slots free again",
			not g.buildings.has(station.id) and not strips.occupied.has(part.id))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
