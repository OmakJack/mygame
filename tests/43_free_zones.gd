extends SceneTree
## Зоны и дома вдоль кривых дорог (этап C3, как в Cities: Skylines): у диагонали и дуги — ячейки вдоль
## края полотна (клетки — в своих ячейках), дома встают под углом дороги фасадом к ней, не залезают на
## полотно и друг на друга; дорога по сетке — полосы из клеток как раньше; сохранение, повышение уровня,
## новая дорога рядом и снос не ломают дом под углом.

const STREET: int = 1
const AVENUE: int = 2


func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.get_node("SimClock").set_speed(0)
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var CO: GDScript = load("res://scripts/simulation/consolidation.gd")
	var LE: GDScript = load("res://scripts/simulation/levels.gd")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var c := func(x: float, y: float) -> Vector2: return Vector2((x + 0.5) * 2.0, (y + 0.5) * 2.0)
	var road := func(g: CityGrid, a: Vector2, b: Vector2, type: int, ctrl: Variant = null) -> bool:
		var graph: RoadGraph = g.roads
		graph.sync(g)
		var pa := RoadGraph.RoadPoint.new(a)
		pa.node = graph.node_near(a, 1.0)
		if pa.node == -1: pa.segment = graph.segment_near(a, 0.8)
		var pb := RoadGraph.RoadPoint.new(b)
		pb.node = graph.node_near(b, 1.0)
		if pb.node == -1: pb.segment = graph.segment_near(b, 0.8)
		if pa.node != -1: pa.pos = graph.nodes[pa.node].pos
		if pb.node != -1: pb.pos = graph.nodes[pb.node].pos
		var plan: RoadGraph.Plan = graph.plan(g, pa, pb, ctrl, type, 1000000)
		if not plan.ok:
			print("refused ", a, " → ", b, ": ", plan.reason)
			return false
		graph.build(g, plan)
		graph.sync(g)
		return true

	# Карта: диагональ, дуга-проспект и прямая улица по сетке далеко от них.
	var g := CityGrid.new(64)
	var graph: RoadGraph = g.roads
	var built: bool = road.call(g, c.call(6, 6), c.call(30, 30), STREET)
	built = road.call(g, c.call(34, 6), c.call(58, 30), AVENUE, c.call(58, 6)) and built
	built = road.call(g, c.call(2, 56), c.call(60, 56), STREET) and built
	check.call("roads built (%d segments)" % graph.segments.size(), built and graph.segments.size() == 3)
	var diagonal: int = graph.segment_near(c.call(18, 18), 0.3)
	var arc: int = graph.segment_near(RoadGraph.bezier(c.call(34, 6), c.call(58, 6), c.call(58, 30), 0.5), 0.3)
	var straight: int = graph.segment_near(c.call(30, 56), 0.3)
	check.call("free: diagonal and arc, not the straight street",
			FreeStrips.is_free(graph, graph.segments[diagonal]) and FreeStrips.is_free(graph, graph.segments[arc])
			and not FreeStrips.is_free(graph, graph.segments[straight]))
	g.ensure_strips()
	var strips: FreeStrips = g.free_strips

	# --- Ячейки вдоль свободных дорог ---
	var per_side := {}
	for slot: FreeStrips.Slot in strips.slots:
		var key := Vector2i(slot.segment, slot.side)
		per_side[key] = per_side.get(key, 0) + 1
	check.call("diagonal: cells both sides (%d, %d)" % [per_side.get(Vector2i(diagonal, 1), 0), per_side.get(Vector2i(diagonal, -1), 0)],
			per_side.get(Vector2i(diagonal, 1), 0) > 40 and per_side.get(Vector2i(diagonal, -1), 0) > 40)
	check.call("arc: cells both sides (%d, %d)" % [per_side.get(Vector2i(arc, 1), 0), per_side.get(Vector2i(arc, -1), 0)],
			per_side.get(Vector2i(arc, 1), 0) > 30 and per_side.get(Vector2i(arc, -1), 0) > 30)
	var inside: bool = true
	var on_land: bool = true
	var clear_of_road: bool = true
	var edge_ok: bool = true
	for slot: FreeStrips.Slot in strips.slots:
		var half: float = RoadTypes.HALF_WIDTH[graph.segments[slot.segment].type]
		for cell: Vector2i in slot.cells:
			var center: Vector2 = RoadGraph.cell_center(cell)
			var grown: PackedVector2Array = Geometry2D.offset_polygon(slot.corners, 0.01)[0]
			if not Geometry2D.is_point_in_polygon(center, grown): inside = false
			if g.is_road(cell) or g.is_water(cell): on_land = false
		for id: int in graph.segments:
			if graph.nearest_on(graph.segments[id], slot.center).y < RoadTypes.HALF_WIDTH[graph.segments[id].type]:
				clear_of_road = false
		if slot.row == 1:
			var inner: float = graph.nearest_on(graph.segments[slot.segment], slot.corners[0].lerp(slot.corners[1], 0.5)).y
			if absf(inner - half) > 0.05: edge_ok = false
	check.call("every cell sits in its slot", inside)
	check.call("slot cells are land, not road", on_land)
	check.call("slots stay off the ribbon", clear_of_road)
	check.call("first row starts at the ribbon edge", edge_ok)

	# --- Прямая улица: полосы из клеток те же, что без кривых дорог ---
	var plain := CityGrid.new(64)
	road.call(plain, c.call(2, 56), c.call(60, 56), STREET)
	plain.ensure_strips()
	var same: bool = true
	for y in range(48, 64):
		for x in 64:
			var i: int = g.index_of(Vector2i(x, y))
			if g.strip_dir[i] != plain.strip_dir[i] or g.strip_depth[i] != plain.strip_depth[i]: same = false
	check.call("grid street: strips as before", same and g.free_slot(Vector2i(30, 55)) == null and g.get_strip_depth(Vector2i(30, 55)) == 1)

	# --- Рост: всё в полосах — жильё ---
	for y in 64:
		for x in 64:
			var cell := Vector2i(x, y)
			if g.in_strip(cell) and not g.is_road(cell):
				g.set_zone(cell, CityGrid.Zone.RESIDENTIAL)
	var net := RoadNetwork.new()
	net.update(g)
	var ut := Utilities.new()
	for cell: Vector2i in net.component_of:
		ut.spare_power[net.component_of[cell]] = 1000000
		ut.spare_water[net.component_of[cell]] = 1000000
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var returns_ok: bool = true
	for i in 500:
		var at: Vector2i = GR.grow_one(g, CityGrid.Zone.RESIDENTIAL, rng, net, ut, null, 0.6)
		if at != CityGrid.NO_CELL and g.get_building_at(at) == null: returns_ok = false
	check.call("growth returns a cell of the new house", returns_ok)
	var on := {diagonal: 0, arc: 0, straight: 0}
	var gridded: int = 0
	var free: Array[BuildingInstance] = []
	for b: BuildingInstance in g.buildings.values():
		if b.is_free():
			free.append(b)
			var best: int = -1
			var best_d: float = INF
			for id: int in graph.segments:
				var d: float = graph.nearest_on(graph.segments[id], b.center).y
				if d < best_d: best_d = d; best = id
			on[best] = on.get(best, 0) + 1
		elif b.cell.y > 44:
			gridded += 1
	check.call("diagonal: houses at an angle (%d)" % on[diagonal], on[diagonal] >= 8)
	check.call("arc: houses at an angle (%d)" % on[arc], on[arc] >= 6)
	check.call("grid street: houses on the grid (%d) and none at an angle" % gridded, gridded >= 8 and on[straight] == 0)

	# Дом: фасадом к дороге, не на полотне, не на соседе; клетки под ним — его, участок — с формой.
	var rect := func(b: BuildingInstance, shrink: float) -> PackedVector2Array:
		var data: BuildingData = BuildingCatalog.get_type(b.type_id)
		var front := Vector2(-sin(b.yaw), -cos(b.yaw))
		var along := Vector2(front.y, -front.x)
		var w: float = data.size.x * CityGrid.CELL_SIZE * 0.5 - shrink
		var d: float = data.size.y * CityGrid.CELL_SIZE * 0.5 - shrink
		return PackedVector2Array([b.center + along * w + front * d, b.center - along * w + front * d,
				b.center - along * w - front * d, b.center + along * w - front * d])
	var faces: bool = true
	var off_ribbon: bool = true
	var own_cells: bool = true
	var shaped_lot: bool = true
	var worst := 1.0
	for b: BuildingInstance in free:
		var best: int = -1
		var best_d: float = INF
		for id: int in graph.segments:
			var d: float = graph.nearest_on(graph.segments[id], b.center).y
			if d < best_d: best_d = d; best = id
		var segment: RoadGraph.Segment = graph.segments[best]
		var curve: PackedVector2Array = graph.curve(segment)
		var foot: Vector2 = RoadGraph.bezier(curve[0], curve[1], curve[2], graph.nearest_on(segment, b.center).x)
		var dot: float = Vector2(-sin(b.yaw), -cos(b.yaw)).dot((foot - b.center).normalized())
		worst = minf(worst, dot)
		if dot < 0.97: faces = false
		var poly: PackedVector2Array = rect.call(b, 0.0)
		for k in 4:
			for f in [0.0, 0.5]:
				var p: Vector2 = poly[k].lerp(poly[(k + 1) % 4], f)
				for id: int in graph.segments:
					var into: float = RoadTypes.HALF_WIDTH[graph.segments[id].type] - graph.nearest_on(graph.segments[id], p).y
					if into > 0.05:
						if off_ribbon: print("   on the ribbon: house %d, road %d, %.2f m in" % [b.id, id, into])
						off_ribbon = false
		for cell: Vector2i in b.cells():
			if g.building_at[g.index_of(cell)] != b.id: own_cells = false
		var lot: CityGrid.Lot = g.lot_of(b)
		if lot == null or lot.poly.size() != 4 or not lot.shape.has(b.shape[0]): shaped_lot = false
	check.call("houses face their road (worst %.3f)" % worst, faces)
	check.call("houses stay off the ribbon", off_ribbon)
	check.call("cells under a house are its own", own_cells)
	check.call("lot along the road: four corners, house inside", shaped_lot)
	var overlap: int = 0
	for i in free.size():
		for j in range(i + 1, free.size()):
			if free[i].center.distance_to(free[j].center) > 12.0: continue
			var both: Array[PackedVector2Array] = Geometry2D.intersect_polygons(rect.call(free[i], 0.05), rect.call(free[j], 0.05))
			if not both.is_empty():
				if overlap < 4:
					var area := 0.0
					var q: PackedVector2Array = both[0]
					for k in q.size(): area += q[k].cross(q[(k + 1) % q.size()])
					print("   overlap: houses %d and %d, %.2f m²" % [free[i].id, free[j].id, absf(area) * 0.5])
				overlap += 1
	check.call("houses do not overlap (%d pairs)" % overlap, overlap == 0)
	var transform_ok: bool = true
	for b: BuildingInstance in free:
		var t: Transform3D = g.building_transform(b)
		if t.origin.distance_to(Vector3(b.center.x, 0.0, b.center.y)) > 0.001 or (t.basis * Vector3.FORWARD).distance_to(
				Vector3(-sin(b.yaw), 0.0, -cos(b.yaw))) > 0.001: transform_ok = false
	check.call("model placed at the house pose", transform_ok)

	# --- Сохранение и загрузка: дом под углом и его участок те же ---
	var saved: Variant = JSON.parse_string(JSON.stringify(CS.to_dict(g, "C3", 1000, 10, 0, 0)))
	var loaded = CS.from_dict(saved)
	var g2: CityGrid = loaded.grid if loaded.ok else null
	if not loaded.warnings.is_empty(): print("   warnings: ", loaded.warnings)
	var kept: bool = g2 != null and loaded.warnings.is_empty()
	if kept:
		for b: BuildingInstance in free:
			var b2: BuildingInstance = g2.buildings.get(b.id)
			if b2 == null or not b2.is_free() or b2.shape != b.shape or b2.center.distance_to(b.center) > 0.001 \
					or absf(b2.yaw - b.yaw) > 0.0001 or b2.cell != b.cell or b2.size != b.size:
				kept = false
				continue
			var lot2: CityGrid.Lot = g2.lot_of(b2)
			var lot: CityGrid.Lot = g.lot_of(b)
			if lot2 == null or lot2.shape != lot.shape or lot2.poly.size() != 4 or lot2.poly[2].distance_to(lot.poly[2]) > 0.001:
				kept = false
	check.call("save/load keeps houses at an angle and their lots", kept)
	if g2 != null:
		g2.ensure_strips()
		check.call("loaded: same slots taken (%d / %d)" % [g2.free_strips.occupied.size(), strips.occupied.size()],
				g2.free_strips.occupied.size() == strips.occupied.size() and strips.occupied.size() > 0)

	# --- Новая дорога в стороне: номера ячеек новые, участки заняты те же ---
	var taken: int = strips.occupied.size()
	road.call(g, c.call(2, 44), c.call(12, 44), STREET)
	g.ensure_strips()
	check.call("new road elsewhere: lots keep their slots (%d / %d)" % [g.free_strips.occupied.size(), taken],
			g.free_strips.occupied.size() == taken)

	# --- Повышение уровня: тот же дом на том же месте и под тем же углом ---
	var up: BuildingInstance = null
	var options: Array[BuildingData] = []
	for b: BuildingInstance in free:
		options = BuildingCatalog.next_level_types(BuildingCatalog.get_type(b.type_id))
		if not options.is_empty(): up = b; break
	if up != null:
		var pose: Transform3D = g.building_transform(up)
		var shape: Array[Vector2i] = up.shape.duplicate()
		var applied: bool = LE._apply(g, up, BuildingCatalog.get_type(up.type_id), options[0], net, ut)
		check.call("level up keeps the pose", applied and up.type_id == options[0].id and up.shape == shape
				and g.building_transform(up).is_equal_approx(pose))
	else:
		check.call("level up keeps the pose (no house to upgrade)", false)
	var demands: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 0.5}
	check.call("consolidation leaves houses at an angle alone",
			not CO.blockers(g, free[0], null, demands).is_empty())

	# --- Снос: клетки свободны, зона осталась, ячейки участка снова пусты ---
	var gone: BuildingInstance = free[1]
	var lot_id: int = g.lot_of(gone).id
	var lot_cells: Array[Vector2i] = g.lot_of(gone).shape.duplicate()
	check.call("remove works", g.remove_building(gone.id))
	var freed: bool = true
	for cell: Vector2i in lot_cells:
		if g.get_building_at(cell) != null or g.get_lot(cell) != null or g.get_zone(cell) != CityGrid.Zone.RESIDENTIAL:
			freed = false
	for slot_id: int in g.free_strips.occupied:
		if g.free_strips.occupied[slot_id] == lot_id: freed = false
	check.call("demolished: cells free, zone kept, slots free", freed)
	var regrown: bool = false
	for i in 200:
		GR.grow_one(g, CityGrid.Zone.RESIDENTIAL, rng, net, ut, null, 0.6)
		if g.get_building_at(lot_cells[0]) != null: regrown = true; break
	check.call("the spot grows again", regrown)

	# --- Новая дорога поперёк диагонали: дома, которые задевает её полотно, сносятся ---
	var free_before: int = 0
	for b: BuildingInstance in g.buildings.values():
		if b.is_free(): free_before += 1
	road.call(g, c.call(10, 26), c.call(26, 10), STREET)
	var hit: int = 0
	var free_after: int = 0
	for b: BuildingInstance in g.buildings.values():
		if not b.is_free(): continue
		free_after += 1
		var poly: PackedVector2Array = g.free_footprint(b)
		for id: int in graph.segments:
			var half: float = RoadTypes.HALF_WIDTH[graph.segments[id].type]
			for k in 4:
				for f in [0.0, 0.5]:
					if graph.nearest_on(graph.segments[id], poly[k].lerp(poly[(k + 1) % 4], f)).y < half - 0.05:
						hit += 1
	check.call("crossing road: houses in its way demolished (%d → %d), none left on a ribbon (%d)" % [free_before, free_after, hit],
			free_after < free_before and hit == 0)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
