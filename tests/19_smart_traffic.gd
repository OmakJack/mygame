extends SceneTree
## Умный трафик: светофоры, дистанция, полосы, повороты дугой (маршрут по графу, этап C2), выбор пути
## с учётом перекрёстков;
## деревья по всему полю.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Светофоры: перекрёсток — 3+ соседа; оси по очереди, не обе сразу зелёные.
	var g := CityGrid.new(32)
	for x in range(2, 30): g.set_road(Vector2i(x, 10))
	for z in range(2, 20): g.set_road(Vector2i(15, z))
	check.call("junction found", TrafficLights.is_junction(g, Vector2i(15, 10)) and not TrafficLights.is_junction(g, Vector2i(14, 10)))
	var both := false
	var each := [false, false]
	for i in 100:
		var t: float = i * 0.1
		var a: bool = TrafficLights.is_green(Vector2i(15, 10), 0, t)
		var b: bool = TrafficLights.is_green(Vector2i(15, 10), 1, t)
		if a and b: both = true
		if a: each[0] = true
		if b: each[1] = true
	check.call("axes take turns", not both and each[0] and each[1])
	g.set_road(Vector2i(16, 10), 3)
	var gh := CityGrid.new(32)
	for x in range(2, 30): gh.set_road(Vector2i(x, 10), 3)
	for z in range(2, 20): gh.set_road(Vector2i(15, z), 3)
	check.call("no lights on highway", not TrafficLights.is_junction(gh, Vector2i(15, 10)))

	# Выбор пути: улица с перекрёстками против чистого проспекта той же длины.
	var gr := CityGrid.new(32)
	for x in range(2, 30):
		gr.set_road(Vector2i(x, 8))
		gr.set_road(Vector2i(x, 14), 2)
	for z in range(8, 15):
		gr.set_road(Vector2i(2, z)); gr.set_road(Vector2i(29, z))
	# Поперечные тупички к улице — делают на ней перекрёстки.
	for x in range(5, 27, 3): gr.set_road(Vector2i(x, 7))
	gr.place_building(&"res_small_01", Vector2i(1, 11), 0)
	var oid: int = gr.place_building(&"off_tower_a", Vector2i(30, 11), 0)
	gr.buildings[oid].powered = true; gr.buildings[oid].has_water = true
	var t = TR.compute(gr)
	check.call("route prefers avenue without stops", t.road_load[gr.index_of(Vector2i(15, 14))] > t.road_load[gr.index_of(Vector2i(15, 8))])

	# Машинки: свой город — одна прямая улица с перекрёстком.
	var city: CityGrid = gs.grid
	for x in range(10, 40): city.set_road(Vector2i(x, 20))
	for z in range(15, 26): city.set_road(Vector2i(25, z))
	var tv: Node = main.get_node("TrafficVisualizer")
	city.roads.sync(city)
	tv._check_roads()
	var graph: RoadGraph = city.roads
	var path := PackedInt32Array()
	for x in range(10, 40): path.append(city.index_of(Vector2i(x, 20)))
	var CarClass = tv.Car
	var make := func(cells: PackedInt32Array, d: float) -> Variant:
		var car = CarClass.new(); car.path = cells; car.forward = true; car.speed = 1.0
		car.route = tv._route_for(car, city); car.distance = d
		return car
	var front = make.call(path, 10.6)
	var back = make.call(path, 9.8)
	tv._cars.clear(); tv._cars.append(front); tv._cars.append(back)
	tv._fill_occupancy()
	var free_back: float = tv._free_ahead(back, city)
	check.call("keeps distance (%.2f)" % free_back, absf(free_back - (0.8 - tv.MIN_GAP)) < 0.01)
	# Едут справа от оси: на восток — южнее середины улицы.
	check.call("drives on the right (%.2f)" % (back.route.point_at(3.0).y - 41.0),
			is_equal_approx(back.route.point_at(3.0).y - 41.0, RoadGeometry.lane_offsets(1)[0]))
	# Красный: перед перекрёстком (25, 20) — стоп-линия до «зебры», по фазе своего подхода (ось E–W).
	var junction: int = graph.node_near(Vector2(51, 41), 0.1)
	var leg: RoadRoute.Leg = null
	for l: RoadRoute.Leg in back.route.legs:
		if l.stop >= 0.0: leg = l; break
	check.call("stop line at the junction", leg != null and leg.light_node == junction)
	var stop_gap: float = back.route.point_at(leg.stop).distance_to(graph.nodes[junction].pos) if leg != null else 0.0
	check.call("stop line before the zebra (%.2f m)" % stop_gap,
			stop_gap >= RoadRoute.trim(graph, city, junction, leg.light_segment) + RoadGeometry.ZEBRA_LENGTH)
	check.call("approach along the street is the E–W phase", TrafficLights.approach_group(graph, junction, leg.light_segment) == 1)
	var stopper = make.call(path, leg.stop - 0.5)
	tv._cars.clear(); tv._cars.append(stopper)
	tv._fill_occupancy()
	var red_time := -1.0
	for i in 200:
		if not TrafficLights.approach_green(graph, junction, leg.light_segment, i * 0.05): red_time = i * 0.05; break
	TrafficLights.time = red_time
	var free_red: float = tv._free_ahead(stopper, city)
	check.call("stops at red (%.2f)" % free_red, is_equal_approx(free_red, 0.5))
	var green_time := -1.0
	for i in 200:
		if TrafficLights.approach_green(graph, junction, leg.light_segment, i * 0.05): green_time = i * 0.05; break
	TrafficLights.time = green_time
	check.call("goes on green", tv._free_ahead(stopper, city) == INF)
	# Поворот на перекрёстке: дуга без изломов, справа от узла, по дороге.
	var turn := PackedInt32Array()
	for x in range(18, 26): turn.append(city.index_of(Vector2i(x, 20)))
	for z in range(21, 26): turn.append(city.index_of(Vector2i(25, z)))
	var turner = make.call(turn, 0.0)
	var smooth := true
	var on_road := true
	var closest := INF
	var d := 0.2
	while d < turner.route.length() - 0.2:
		if turner.route.dir_at(d).angle_to(turner.route.dir_at(d + 0.25)) > deg_to_rad(25.0): smooth = false
		if not city.is_road(RoadGraph.cell_of(turner.route.point_at(d))): on_road = false
		closest = minf(closest, turner.route.point_at(d).distance_to(graph.nodes[junction].pos))
		d += 0.1
	check.call("right turn is a smooth arc on the road", smooth and on_road and closest > 0.3)
	# Полосы: на проспекте две, на улице одна (по разметке).
	check.call("two lanes on avenue", tv._offset(2, 1) == RoadGeometry.lane_offsets(2)[1]
			and tv._offset(2, 0) == RoadGeometry.lane_offsets(2)[0] and tv._offset(1, 1) == RoadGeometry.lane_offsets(1)[0])
	# Пешеходы правилам не подчиняются.
	check.call("people ignore car rules", not main.get_node("Walkers")._obeys_rules() and tv._obeys_rules())

	# Деревья — по всему полю (раньше предел обрывал нижнюю половину).
	var trees: Node = main.get_node("TreeVisualizer")
	trees._rebuild()
	var q := [0, 0, 0, 0]
	for layer in trees._layers:
		for i in layer.multimesh.instance_count:
			var p: Vector3 = layer.multimesh.get_instance_transform(i).origin
			q[(1 if p.x > 64.0 else 0) + (2 if p.z > 64.0 else 0)] += 1
	var lo: int = mini(mini(q[0], q[1]), mini(q[2], q[3]))
	var hi: int = maxi(maxi(q[0], q[1]), maxi(q[2], q[3]))
	check.call("trees in all quarters %s" % str(q), lo > hi * 0.6)
	check.call("trees within limit (%d)" % trees.tree_count(), trees.tree_count() <= trees.MAX_TREES)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
