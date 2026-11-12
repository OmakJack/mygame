extends SceneTree
## Пешеходы и велосипедисты: выбор способа по времени и пробкам, разгрузка дорог,
## шоссе без пеших, выборки путей, фигурки на тротуарах.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.get_node("SimClock").set_speed(0)
	var gs: Node = root.get_node("GameState")
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Доли по времени.
	var free_long: Vector3 = TR.mode_shares(15.0, 15.0, false)
	check.call("free long trip — mostly cars (%.2f)" % free_long.x, free_long.x > 0.9)
	var short: Vector3 = TR.mode_shares(4.0, 4.0, false)
	check.call("short trip — some walk (%.2f) and bike (%.2f)" % [short.z, short.y], short.z > 0.1 and short.y > 0.03)
	var jam: Vector3 = TR.mode_shares(40.0, 10.0, false)
	check.call("jam — most leave the car (car %.2f)" % jam.x, jam.x < 0.3 and jam.y + jam.z > 0.7)
	check.call("too far to walk", TR.mode_shares(80.0, 20.0, false).z == 0.0)
	check.call("highway — cars only", TR.mode_shares(40.0, 5.0, true) == Vector3(1.0, 0.0, 0.0))
	var sum: Vector3 = TR.mode_shares(9.0, 7.0, false)
	check.call("shares sum to 1", is_equal_approx(sum.x + sum.y + sum.z, 1.0))
	# Долгая поездка в пробке: exp(−104) во float32 — ноль; раньше доли были 0/0 = NaN и вешали машинки.
	var stuck: Vector3 = TR.mode_shares(416.6, 57.0, false)
	var stuck_near: Vector3 = TR.mode_shares(416.6, 10.0, false)
	check.call("long jam — no NaN (%s, %s)" % [stuck, stuck_near], stuck == Vector3(1.0, 0.0, 0.0)
			and not is_nan(stuck_near.x) and stuck_near.y + stuck_near.z > 0.99)

	# Город с пробкой: те же дома и работа — нагрузка на дорогу меньше потока работников.
	var g := CityGrid.new(32)
	for x in range(2, 26): g.set_road(Vector2i(x, 10))
	for x in [2, 3, 4]:
		g.place_building(&"res_block_n", Vector2i(x, 9), 0)
	for x in range(14, 26):
		for z in [9, 11]:
			var id: int = g.place_building(&"off_tower_d", Vector2i(x, z), 0)
			g.buildings[id].powered = true; g.buildings[id].has_water = true
	var t = TR.compute(g)
	var peak: float = 0.0
	for x in range(2, 26):
		peak = maxf(peak, t.road_load[g.index_of(Vector2i(x, 10))])
	print("   workers=%.0f walkers=%.0f cyclists=%.0f peak_load=%.0f jams=%d" % [t.total_workers, t.walkers, t.cyclists, peak, t.jammed_cells])
	check.call("some walk or bike", t.walkers + t.cyclists > 0.0)
	check.call("only cars load the road", peak < t.total_workers - 1.0)
	check.call("people paths sampled", t.bike_paths.size() + t.walk_paths.size() > 0)

	# Шоссе посередине пути — никто не идёт и не едет на велосипеде.
	var gh := CityGrid.new(32)
	for x in range(2, 26): gh.set_road(Vector2i(x, 10), 3 if x >= 8 and x <= 12 else 1)
	gh.place_building(&"res_block_n", Vector2i(3, 9), 0)
	var oid: int = gh.place_building(&"off_tower_d", Vector2i(20, 9), 0)
	gh.buildings[oid].powered = true; gh.buildings[oid].has_water = true
	var th = TR.compute(gh)
	check.call("no walking over highway", th.walkers == 0.0 and th.cyclists == 0.0)

	# Фигурки: пути есть — фигурки появились, у каждой свой цвет.
	gs.grid = g
	gs.traffic = t
	var walkers: Node = main.get_node("Walkers")
	var cyclists: Node = main.get_node("Cyclists")
	root.get_node("SimClock").set_speed(1)
	for i in 3:
		walkers._process(0.05)
		cyclists._process(0.05)
	check.call("cyclists shown (%d)" % cyclists.visible_people_count(), cyclists.visible_people_count() == mini(120, roundi(t.cyclists / cyclists.WORKERS_PER_PERSON)))
	check.call("walkers shown (%d)" % walkers.visible_people_count(), walkers.visible_people_count() == mini(200, roundi(t.walkers / walkers.WORKERS_PER_PERSON)))
	# Пак Argon: 8 видов пешеходов и 4 велосипедиста, все загружены, рост фигурки — как у прежних.
	var sizes_ok: bool = walkers._layers.size() == 8 and cyclists._layers.size() == 4
	for layer: MultiMeshInstance3D in walkers._layers + cyclists._layers:
		var box: AABB = layer.multimesh.mesh.get_aabb()
		if box.size.y < 0.3 or box.size.y > 0.45: sizes_ok = false
	check.call("all 8 walker and 4 cyclist models loaded, 0.3–0.45 m tall", sizes_ok)
	var kinds: Dictionary = {}
	for car in walkers._cars + cyclists._cars:
		kinds[str(car.model) + ("c" if cyclists._cars.has(car) else "w")] = true
	check.call("several kinds on the streets (%d)" % kinds.size(), kinds.size() >= 6)
	if cyclists._cars.size() > 1:
		check.call("own colors", cyclists._cars[0].custom != cyclists._cars[1].custom)
		var p: Vector3 = cyclists.car_origin(0)
		var cell: Vector2i = g.world_to_grid(p)
		check.call("cyclist on a road cell", g.is_road(cell))
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
