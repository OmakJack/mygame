extends SceneTree
## Умный трафик: светофоры, дистанция, полосы, парковка у цели, выбор пути с учётом перекрёстков;
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
	tv._check_roads()
	var path := PackedInt32Array()
	for x in range(10, 40): path.append(city.index_of(Vector2i(x, 20)))
	var CarClass = tv.Car
	var front = CarClass.new(); front.path = path; front.progress = 5.3; front.forward = true; front.speed = 1.0
	var back = CarClass.new(); back.path = path; back.progress = 4.9; back.forward = true; back.speed = 1.0
	tv._cars.clear(); tv._cars.append(front); tv._cars.append(back)
	tv._fill_occupancy(city)
	var free_back: float = tv._free_ahead(back, city, 4)
	check.call("keeps distance (%.2f)" % free_back, free_back < 0.4 - tv.MIN_GAP + 0.01)
	# Красный: машина перед перекрёстком (клетка 25 — перекрёсток, k = 14) стоит у стоп-линии.
	var stopper = CarClass.new(); stopper.path = path; stopper.forward = true; stopper.progress = 14.2; stopper.speed = 1.0
	tv._cars.clear(); tv._cars.append(stopper)
	tv._fill_occupancy(city)
	var red_time := -1.0
	for i in 200:
		if not TrafficLights.is_green(Vector2i(25, 20), 1, i * 0.05): red_time = i * 0.05; break
	TrafficLights.time = red_time
	var free_red: float = tv._free_ahead(stopper, city, 14)
	check.call("stops at red (%.2f)" % free_red, is_equal_approx(free_red, tv.STOP_LINE - 0.2))
	var green_time := -1.0
	for i in 200:
		if TrafficLights.is_green(Vector2i(25, 20), 1, i * 0.05): green_time = i * 0.05; break
	TrafficLights.time = green_time
	check.call("goes on green", tv._free_ahead(stopper, city, 14) == INF)
	# Полосы: на проспекте две, на улице одна.
	city.set_road(Vector2i(30, 20), 2)
	var lane_car = CarClass.new(); lane_car.lane = 1
	check.call("two lanes on avenue", tv._lane_for(lane_car, city, city.index_of(Vector2i(30, 20))) == tv.MULTI_LANES[1] and tv._lane_for(lane_car, city, city.index_of(Vector2i(12, 20))) == tv.LANE_OFFSET)
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
