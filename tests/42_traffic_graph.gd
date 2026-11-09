extends SceneTree
## Трафик по графу дорог (этап C2): машинки едут по кривым на своей полосе справа (диагональ, дуга),
## поворачивают дугой; светофоры — по фазам подходов (косой крест, «вилка»); очередь на красный
## держит дистанцию и трогается на зелёный; застрявшая уезжает; пешеходы — по тротуару; дорогу перестроили под машинкой —
## она остаётся на месте.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	var g: CityGrid = gs.grid
	var graph: RoadGraph = g.roads
	var tv: Node = main.get_node("TrafficVisualizer")
	var walkers: Node = main.get_node("Walkers")
	var c := func(x: float, y: float) -> Vector2: return Vector2((x + 0.5) * 2.0, (y + 0.5) * 2.0)
	var road := func(a: Vector2, b: Vector2, type: int, ctrl: Variant = null) -> bool:
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
	# Путь клеток вдоль отрезка — как его дал бы Traffic (по возрастанию t).
	var cells_of := func(id: int) -> PackedInt32Array:
		var segment: RoadGraph.Segment = graph.segments[id]
		var order: Array = range(segment.cells.size())
		order.sort_custom(func(i: int, j: int) -> bool: return segment.cell_t[i] < segment.cell_t[j])
		var result := PackedInt32Array()
		for i: int in order: result.append(g.index_of(segment.cells[i]))
		return result
	var CarClass = tv.Car
	var make := func(visual: Node, cells: PackedInt32Array, d: float, lane: int = 0) -> Variant:
		var car = CarClass.new(); car.path = cells; car.forward = true; car.speed = 1.0; car.lane = lane
		car.route = visual._route_for(car, g); car.distance = d
		return car
	# Насколько точки маршрута (без концов) отстоят от оси отрезка: [меньше, больше].
	var spread := func(car, id: int) -> Vector2:
		var lo := INF
		var hi := 0.0
		var d := 1.0
		while d < car.route.length() - 1.0:
			var off: float = graph.nearest_on(graph.segments[id], car.route.point_at(d)).y
			lo = minf(lo, off); hi = maxf(hi, off)
			d += 0.25
		return Vector2(lo, hi)

	# Диагональ и дуга: машинка — на своей полосе по всей длине (а не лесенкой по клеткам).
	road.call(c.call(5, 5), c.call(25, 25), 1)
	var diagonal: int = graph.segment_near(c.call(15, 15), 0.2)
	var diag_car = make.call(tv, cells_of.call(diagonal), 0.0)
	var lane: float = RoadGeometry.lane_offsets(1)[0]
	var s: Vector2 = spread.call(diag_car, diagonal)
	check.call("diagonal: on the lane all the way (%.2f..%.2f)" % [s.x, s.y], absf(s.x - lane) < 0.03 and absf(s.y - lane) < 0.03)
	road.call(c.call(35, 5), c.call(55, 25), 2, c.call(55, 5))
	var arc: int = graph.segment_near(RoadGraph.bezier(c.call(35, 5), c.call(55, 5), c.call(55, 25), 0.5), 0.2)
	var arc_car = make.call(tv, cells_of.call(arc), 0.0, 1)
	s = spread.call(arc_car, arc)
	var outer: float = RoadGeometry.lane_offsets(2)[1]
	check.call("arc avenue: outer lane all the way (%.2f..%.2f)" % [s.x, s.y], absf(s.x - outer) < 0.05 and absf(s.y - outer) < 0.05)
	var walker = make.call(walkers, cells_of.call(diagonal), 0.0)
	s = spread.call(walker, diagonal)
	var sidewalk: float = (RoadTypes.ASPHALT_HALF[1] + RoadTypes.HALF_WIDTH[1]) * 0.5
	check.call("walkers on the sidewalk (%.2f..%.2f)" % [s.x, s.y], absf(s.x - sidewalk) < 0.03 and absf(s.y - sidewalk) < 0.03)

	# Косой крест: две диагонали — разные фазы; «вилка» из трёх косых дорог — не все зелёные сразу.
	road.call(c.call(5, 25), c.call(25, 5), 1)
	var cross: int = graph.node_near(c.call(15, 15), 0.2)
	var groups: Array[int] = []
	for id: int in graph.nodes[cross].segments: groups.append(TrafficLights.approach_group(graph, cross, id))
	var same_road := func(i: int, j: int) -> bool:
		var di: Vector2 = graph.direction_from(graph.segments[graph.nodes[cross].segments[i]], cross)
		var dj: Vector2 = graph.direction_from(graph.segments[graph.nodes[cross].segments[j]], cross)
		return di.dot(dj) < -0.9
	var cross_ok: bool = groups.size() == 4
	for i in groups.size():
		for j in range(i + 1, groups.size()):
			if (groups[i] == groups[j]) != same_road.call(i, j): cross_ok = false
	check.call("diagonal crossing: each road its own phase %s" % str(groups), cross_ok)
	road.call(c.call(20, 40), c.call(30, 40), 1)
	road.call(c.call(30, 40), c.call(38, 36), 1)
	road.call(c.call(30, 40), c.call(38, 44), 1)
	var fork: int = graph.node_near(c.call(30, 40), 0.2)
	var fork_groups := {}
	for id: int in graph.nodes[fork].segments: fork_groups[TrafficLights.approach_group(graph, fork, id)] = true
	check.call("fork: both phases used", graph.nodes[fork].segments.size() == 3 and fork_groups.size() == 2)

	# Очередь на красный: две машинки на подходе — первая у стоп-линии, вторая за ней с дистанцией;
	# на зелёный обе проезжают.
	for x in range(5, 40): g.set_road(Vector2i(x, 50))
	for z in range(45, 56): g.set_road(Vector2i(20, z))
	graph.sync(g)
	tv._check_roads()
	var street := PackedInt32Array()
	for x in range(5, 40): street.append(g.index_of(Vector2i(x, 50)))
	var probe = make.call(tv, street, 0.0)
	var leg: RoadRoute.Leg = null
	for l: RoadRoute.Leg in probe.route.legs:
		if l.stop >= 0.0: leg = l; break
	check.call("approach has a stop line", leg != null)
	var red := -1.0
	var green := -1.0
	for i in 400:
		var on: bool = TrafficLights.approach_green(graph, leg.light_node, leg.light_segment, i * 0.05)
		if not on and red < 0.0: red = i * 0.05
		if on and red >= 0.0 and green < 0.0: green = i * 0.05
	var first = make.call(tv, street, leg.stop - 3.0)
	var second = make.call(tv, street, leg.stop - 4.5)
	tv._cars.clear(); tv._cars.append(first); tv._cars.append(second)
	TrafficLights.time = red
	for i in 120:
		tv._fill_occupancy()
		for car in tv._cars: tv._advance(car, g, tv.SPEED * 0.05, 0.05)
	check.call("first waits at the stop line (%.2f m before)" % (leg.stop - first.distance), absf(leg.stop - first.distance) < 0.02)
	var gap: float = first.distance - second.distance
	check.call("second keeps distance behind (%.2f m)" % gap, gap >= tv.MIN_GAP - 0.01 and gap < tv.MIN_GAP + 0.2)
	TrafficLights.time = green
	for i in 40:
		tv._fill_occupancy()
		for car in tv._cars: tv._advance(car, g, tv.SPEED * 0.05, 0.05)
	check.call("both drive on at green", first.distance > leg.stop + 1.0 and second.distance > leg.stop)

	# Застряла (стоит дольше STUCK_TIME) — уезжает и берёт новую поездку (путей нет — с начала маршрута).
	var jammed = make.call(tv, street, leg.stop)
	tv._cars.clear(); tv._cars.append(jammed)
	TrafficLights.time = red
	jammed.stuck = tv.STUCK_TIME - 0.01
	tv._fill_occupancy()
	tv._advance(jammed, g, tv.SPEED * 0.05, 0.05)
	check.call("stuck car leaves", jammed.distance == 0.0 and jammed.stuck == 0.0)

	# Дорогу перестроили под машинкой (Т к середине — отрезок разрезан): машинка там же.
	var rider = make.call(tv, street, 10.0)
	tv._cars.clear(); tv._cars.append(rider)
	var before: Vector2 = rider.route.point_at(rider.distance)
	road.call(c.call(10, 50), c.call(10, 58), 1)
	tv._check_roads()
	var after: Vector2 = rider.route.point_at(rider.distance)
	check.call("rebuilt road: car stays put (%.2f m)" % before.distance_to(after), tv._cars.size() == 1 and before.distance_to(after) < 0.3)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
