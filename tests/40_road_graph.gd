extends SceneTree
## Граф дорог (как в Cities: Skylines, этап C1): прямая и дуга по точкам, пересечение — перекрёсток,
## примыкание к дороге (Т-перекрёсток), растр в клетки (диагональ — связная и без «домов на дороге»),
## проверки (вплотную к дороге, острый угол, за краем, мало денег), дома зон на пути сносятся,
## снос и смена типа, подхват клеток, поставленных мимо графа, сохранение графа.

const STREET: int = 1
const AVENUE: int = 2


func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var g := CityGrid.new(64)
	var graph: RoadGraph = g.roads
	var at := func(x: int, y: int) -> RoadGraph.RoadPoint: return RoadGraph.RoadPoint.new(RoadGraph.cell_center(Vector2i(x, y)))
	var row_cells := func(y: int, x0: int, x1: int) -> bool:
		for x in range(x0, x1 + 1):
			if not g.is_road(Vector2i(x, y)): return false
		return true

	# Прямая по центрам клеток — ровно ряд клеток, цена — как раньше за клетку.
	var plan: RoadGraph.Plan = graph.plan(g, at.call(5, 10), at.call(25, 10), null, STREET, 100000)
	check.call("straight plan ok (%s)" % plan.reason, plan.ok)
	check.call("straight takes 21 cells, cost 210 (%d, %d)" % [plan.cells.size(), plan.cost],
			plan.cells.size() == 21 and plan.cost == 210)
	graph.build(g, plan)
	check.call("straight road on the grid", row_cells.call(10, 5, 25) and g.road_cells.size() == 21)
	check.call("one segment, two nodes", graph.segments.size() == 1 and graph.nodes.size() == 2)

	# Поперечная дорога — пересечение становится узлом с четырьмя дорогами.
	plan = graph.plan(g, at.call(15, 2), at.call(15, 20), null, STREET, 100000)
	check.call("crossing plan ok (%s), one crossing" % plan.reason, plan.ok and plan.crossings.size() == 1)
	graph.build(g, plan)
	check.call("crossing splits both roads (%d segments, %d nodes)" % [graph.segments.size(), graph.nodes.size()],
			graph.segments.size() == 4 and graph.nodes.size() == 5)
	check.call("crossing cell is a junction", graph.is_junction(g, Vector2i(15, 10)))
	check.call("cells of both roads (%d)" % g.road_cells.size(), g.road_cells.size() == 21 + 19 - 1)

	# Примыкание к середине дороги — Т-перекрёсток.
	var on_road := RoadGraph.RoadPoint.new(RoadGraph.cell_center(Vector2i(8, 10)))
	on_road.segment = graph.segment_near(on_road.pos, 0.5)
	plan = graph.plan(g, on_road, at.call(8, 22), null, STREET, 100000)
	check.call("T plan ok (%s)" % plan.reason, plan.ok)
	graph.build(g, plan)
	var t_node: int = graph.node_near(RoadGraph.cell_center(Vector2i(8, 10)), 0.1)
	check.call("T node with three roads", t_node != -1 and graph.nodes[t_node].segments.size() == 3)

	# Вплотную к дороге, острый угол, за краем, мало денег — нельзя.
	plan = graph.plan(g, at.call(5, 11), at.call(13, 11), null, STREET, 100000)
	check.call("parallel road next to another is refused (%s)" % plan.reason, not plan.ok)
	var end_a := RoadGraph.RoadPoint.new(RoadGraph.cell_center(Vector2i(25, 10)))
	end_a.node = graph.node_near(end_a.pos, 0.1)
	plan = graph.plan(g, end_a, at.call(17, 13), null, STREET, 100000)
	check.call("sharp angle is refused (%s)" % plan.reason, not plan.ok and plan.reason.contains("угол"))
	plan = graph.plan(g, at.call(40, 2), RoadGraph.RoadPoint.new(Vector2(140.0, 4.0)), null, STREET, 100000)
	check.call("off the map is refused (%s)" % plan.reason, not plan.ok)
	plan = graph.plan(g, at.call(40, 2), at.call(60, 2), null, STREET, 50)
	check.call("not enough money (%s)" % plan.reason, not plan.ok and plan.cost > 50)

	# Диагональ: клетки связаны по сторонам, дом на соседней клетке не залезет на полотно.
	plan = graph.plan(g, at.call(30, 30), at.call(42, 40), null, STREET, 100000)
	check.call("diagonal plan ok (%s)" % plan.reason, plan.ok)
	graph.build(g, plan)
	var seen: Dictionary = {Vector2i(30, 30): true}
	var queue: Array[Vector2i] = [Vector2i(30, 30)]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset: Vector2i in CityGrid.NEIGHBORS:
			if g.is_road(cell + offset) and not seen.has(cell + offset):
				seen[cell + offset] = true
				queue.append(cell + offset)
	check.call("diagonal cells are 4-connected end to end", seen.has(Vector2i(42, 40)))
	var clear_ok: bool = true
	var diag: RoadGraph.Segment = graph.segments[graph.segment_near(RoadGraph.cell_center(Vector2i(36, 35)), 2.0)]
	for y in range(28, 43):
		for x in range(28, 45):
			var cell := Vector2i(x, y)
			if g.is_road(cell): continue
			# Ближняя к дороге точка «дома» 1.6 × 1.6 м в центре клетки — не ближе полуширины дороги.
			var center: Vector2 = RoadGraph.cell_center(cell)
			var nearest: Vector2 = graph.nearest_on(diag, center)
			var points: PackedVector2Array = graph.curve(diag)
			var foot: Vector2 = RoadGraph.bezier(points[0], points[1], points[2], nearest.x)
			var corner: Vector2 = center + (foot - center).sign() * 0.8
			if graph.nearest_on(diag, corner).y < RoadTypes.HALF_WIDTH[STREET] - RoadGraph.CLEARANCE - 0.05:
				clear_ok = false
	check.call("no house next to the diagonal would stand on the road", clear_ok)

	# Дуга (кривая с управляющей точкой): одна дорога, клетки по дуге.
	plan = graph.plan(g, at.call(45, 5), at.call(55, 15), RoadGraph.cell_center(Vector2i(55, 5)), STREET, 100000)
	check.call("curve plan ok (%s)" % plan.reason, plan.ok)
	graph.build(g, plan)
	var curve_id: int = graph.segment_near(RoadGraph.bezier(RoadGraph.cell_center(Vector2i(45, 5)),
			RoadGraph.cell_center(Vector2i(55, 5)), RoadGraph.cell_center(Vector2i(55, 15)), 0.5), 0.3)
	check.call("curve is one segment through its middle", curve_id != -1
			and g.is_road(RoadGraph.cell_of(RoadGraph.bezier(RoadGraph.cell_center(Vector2i(45, 5)),
			RoadGraph.cell_center(Vector2i(55, 5)), RoadGraph.cell_center(Vector2i(55, 15)), 0.5))))
	var mid_cell: Vector2i = RoadGraph.cell_of(RoadGraph.bezier(RoadGraph.cell_center(Vector2i(45, 5)),
			RoadGraph.cell_center(Vector2i(55, 5)), RoadGraph.cell_center(Vector2i(55, 15)), 0.4))
	var anchor: Vector2 = graph.anchor(mid_cell)
	check.call("cars ride the curve: cell anchor lies on the road", graph.nearest_on(graph.segments[curve_id], anchor).y < 0.05)

	# Дома зон на пути сносятся, служебные здания — мешают.
	g.set_zone(Vector2i(20, 25), CityGrid.Zone.RESIDENTIAL)
	var house: int = g.place_building(BuildingCatalog.growable_types(CityGrid.Zone.RESIDENTIAL)[0].id, Vector2i(20, 25), 2)
	plan = graph.plan(g, at.call(16, 25), at.call(24, 25), null, STREET, 100000)
	check.call("zoned house on the way will be demolished (%s)" % plan.reason, plan.ok and plan.demolish.has(house))
	graph.build(g, plan)
	check.call("house demolished, road laid", not g.buildings.has(house) and g.is_road(Vector2i(20, 25)))

	# Смена типа и снос.
	var cross_id: int = graph.segment_near(RoadGraph.cell_center(Vector2i(15, 5)), 0.3)
	graph.retype(g, cross_id, AVENUE)
	check.call("retype makes avenue cells", g.get_road_type(Vector2i(15, 5)) == AVENUE
			and g.get_road_type(Vector2i(15, 3)) == AVENUE)
	check.call("junction cell takes the bigger type", g.get_road_type(Vector2i(15, 10)) == AVENUE)
	graph.remove_segments(g, [cross_id])
	check.call("removed segment frees its cells", not g.is_road(Vector2i(15, 5)) and not g.is_road(Vector2i(15, 2)))
	check.call("shared junction cell stays, back to street", g.is_road(Vector2i(15, 10)) and g.get_road_type(Vector2i(15, 10)) == STREET)

	# Клетки мимо графа (как в тестах, старых сохранениях и у въезда трассы) — граф подхватывает.
	var before: int = graph.segments.size()
	for x in range(50, 56): g.set_road(Vector2i(x, 50), STREET)
	for y in range(51, 54): g.set_road(Vector2i(55, y), STREET)
	graph.sync(g)
	var corner_node: int = graph.node_near(RoadGraph.cell_center(Vector2i(55, 50)), 0.1)
	check.call("set_road cells adopted as an L of two segments", graph.segments.size() == before + 2 and corner_node != -1)
	g.set_road(Vector2i(52, 51), STREET)
	graph.sync(g)
	var tee: int = graph.node_near(RoadGraph.cell_center(Vector2i(52, 50)), 0.1)
	check.call("cell next to a road joins it (T node)", tee != -1 and graph.nodes[tee].segments.size() == 3)
	g.remove_road(Vector2i(20, 10))
	graph.sync(g)
	var owned_all: bool = true
	for cell: Vector2i in g.road_cells:
		if graph.owners_of(cell).is_empty() and not graph._lone.has(cell): owned_all = false
	for cell: Vector2i in graph._owners:
		if not g.is_road(cell): owned_all = false
	check.call("removing a cell past the graph: graph matches the grid again", owned_all)
	check.call("old crossing still a junction after re-adoption", graph.is_junction(g, Vector2i(8, 10)))

	# Сохранение: граф → словарь → JSON → новый граф на тех же клетках — те же отрезки и точки.
	var data: Variant = JSON.parse_string(JSON.stringify(graph.to_dict()))
	var g2 := CityGrid.new(64)
	for cell: Vector2i in g.road_cells:
		g2.set_road(cell, g.get_road_type(cell))
	var warnings: Array[String] = g2.roads.load_dict(g2, data)
	check.call("loaded graph: same segments and nodes (%d/%d, %d/%d) %s" % [g2.roads.segments.size(), graph.segments.size(),
			g2.roads.nodes.size(), graph.nodes.size(), warnings],
			g2.roads.segments.size() == graph.segments.size() and g2.roads.nodes.size() == graph.nodes.size())
	var curve_back: RoadGraph.Segment = g2.roads.segments.get(curve_id)
	check.call("loaded curve keeps its shape", curve_back != null and curve_back.ctrl.is_equal_approx(graph.segments[curve_id].ctrl))
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
