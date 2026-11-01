extends SceneTree
## Трафик: Дейкстра, поток к работе, пробки, объезд.
const SHOT := "res://tests/out/phase8.png"

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hud: CanvasLayer = main.get_node("HUD")
	var zv: MultiMeshInstance3D = main.get_node("ZoneVisualizer")
	var cars: MultiMeshInstance3D = main.get_node("TrafficVisualizer")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)

	# --- Дейкстра против обхода в ширину на одинаковых стоимостях ---
	var maze := CityGrid.new(24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 24:
		for x in 24:
			if rng.randf() < 0.6: maze.set_road(Vector2i(x, y))
	var n: int = 24 * 24
	var cost := PackedFloat32Array(); cost.resize(n); cost.fill(1.0)
	var srcs := PackedInt32Array()
	var jobs := PackedFloat32Array(); jobs.resize(n)
	for road in maze.road_cells:
		if srcs.size() < 3: srcs.append(maze.index_of(road)); jobs[maze.index_of(road)] = 10.0
	var arr := PackedFloat32Array(); arr.resize(n)
	var pen := PackedFloat32Array(); pen.resize(n)
	var dist := PackedFloat32Array(); dist.resize(n)
	var nxt := PackedInt32Array(); nxt.resize(n)
	var order: PackedInt32Array = TR._dijkstra(maze, srcs, jobs, arr, 0.0, cost, pen, dist, nxt)
	var bfs := {}
	var queue: Array = []
	for s0 in srcs: bfs[s0] = 1.0; queue.append(s0)
	while not queue.is_empty():
		var c: int = queue.pop_front()
		for d in [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]:
			var cell: Vector2i = Vector2i(c % 24, c / 24) + d
			if maze.is_road(cell) and not bfs.has(maze.index_of(cell)):
				bfs[maze.index_of(cell)] = bfs[c] + 1.0
				queue.append(maze.index_of(cell))
	var same := order.size() == bfs.size()
	for k in bfs:
		if not is_equal_approx(dist[k], bfs[k]): same = false
	var unique := {}
	for c in order: unique[c] = true
	check.call("dijkstra == bfs", same and unique.size() == order.size())

	# --- Сценарий Argon: спальный район, магазин на выезде, промзона вдали ---
	var g: CityGrid = gs.grid
	for x in range(2, 51): g.set_road(Vector2i(x, 20))
	var homes := 0
	for x in range(2, 9):
		for y in [17, 18, 19, 21, 22, 23]:
			if g.place_building(&"res_small_01", Vector2i(x, y), 0) >= 0: homes += 1
	g.place_building(&"com_small_01", Vector2i(10, 19), 2)
	for x in range(40, 49):
		for y in [18, 19, 21, 22]:
			g.place_building(&"ind_small_01", Vector2i(x, y), 0)
	for b: BuildingInstance in g.buildings.values():
		b.powered = true
		b.has_water = true
	var t = TR.compute(g)
	var mid: int = g.index_of(Vector2i(30, 20))
	print("workers=%.0f walk=%.1f bike=%.1f load@x30=%.1f jammed=%d avg_commute=%.1f share=%.2f" % [t.total_workers, t.walkers, t.cyclists, t.road_load[mid], t.jammed_cells, t.average_commute, t.long_commute_share])
	# Первый проход развозит всех к ближайшей работе (магазину), дальше — по перегрузке: при втрое меньшем
	# населении (2026-11-01) магазин успевает взять треть, а не шестую часть — большинство всё равно в промзону.
	check.call("most flow goes to industry (not the shop)", t.road_load[mid] >= 0.6 * t.total_workers)
	check.call("jam on single road", t.jammed_cells > 0)
	check.call("pure", TR.compute(g).road_load == t.road_load)
	check.call("sample paths", not t.sample_paths.is_empty() and t.sample_paths.size() <= TR.MAX_SAMPLE_PATHS)

	# --- Объезд: параллельная дорога y=26 с перемычками на x=9 и x=39 (x=40 занят цехами) ---
	for x in range(9, 40): g.set_road(Vector2i(x, 26))
	for y in range(21, 26):
		g.set_road(Vector2i(9, y))
		g.set_road(Vector2i(39, y))
	# перемычки заняли клетки зданий? place_building мог стоять на (40,21..22) — set_road не ставит дорогу на здание
	var t2 = TR.compute(g)
	var main_load: float = t2.road_load[g.index_of(Vector2i(30, 20))]
	var detour_load: float = t2.road_load[g.index_of(Vector2i(30, 26))]
	print("with detour: main=%.1f detour=%.1f jammed=%d" % [main_load, detour_load, t2.jammed_cells])
	check.call("detour used", detour_load > 0.2 * t.total_workers)
	check.call("main relieved", main_load < t.road_load[mid] * 0.85)
	check.call("no swing (pure)", TR.compute(g).road_load == t2.road_load)

	# --- Нет работы в компоненте — тяжесть 1 ---
	var lonely := CityGrid.new(16)
	lonely.set_road(Vector2i(2, 2))
	lonely.place_building(&"res_small_01", Vector2i(2, 3), 0)
	var t3 = TR.compute(lonely)
	check.call("no jobs -> badness 1", is_equal_approx(t3.long_commute_share, 1.0) and is_equal_approx(t3.demand_offset(), -0.3))

	# --- Мёртвый цех не принимает ---
	var dead := CityGrid.new(16)
	for x in range(1, 12): dead.set_road(Vector2i(x, 5))
	dead.place_building(&"res_small_01", Vector2i(1, 6), 0)
	var factory_id: int = dead.place_building(&"ind_small_01", Vector2i(10, 6), 0)
	dead.buildings[factory_id].powered = false
	var t4 = TR.compute(dead)
	check.call("unpowered job ignored", is_equal_approx(t4.long_commute_share, 1.0))

	# --- Правила пересчёта в симуляции (со станциями: симуляция сама считает свет и воду) ---
	for c in [Vector2i(12, 19), Vector2i(13, 19)]: g.place_building(&"power_plant_01", c, 2, true)
	for c in [Vector2i(12, 21), Vector2i(13, 21)]: g.place_building(&"water_tower_01", c, 0, true)
	ev.grid_reset.emit()
	print("power %d/%d water %d/%d" % [gs.utilities.power_use, gs.utilities.power_supply, gs.utilities.water_use, gs.utilities.water_supply])
	var traffic_before = gs.traffic
	ev.tax_rate_requested.emit(12)
	check.call("tax does not recompute", gs.traffic == traffic_before)
	g.remove_road(Vector2i(25, 26))
	var changed: Array[Vector2i] = [Vector2i(25, 26)]
	ev.cells_changed.emit(changed)
	check.call("road change recomputes", gs.traffic != traffic_before)
	traffic_before = gs.traffic
	ev.sim_tick.emit()
	var recomputed_early: bool = gs.traffic != traffic_before
	for i in 5: ev.sim_tick.emit()
	check.call("tick period", not recomputed_early and gs.traffic != traffic_before)

	# --- HUD, подсказки, слой ---
	ev.stats_changed.emit()
	hud._select_tab("filters")
	check.call("traffic filter card", hud._filters._cards[4].text.begins_with("Пробки"))
	zv.set_overlay(zv.Overlay.TRAFFIC)
	var jam_cell := Vector2i(-1, -1)
	for road in g.road_cells:
		if gs.traffic.load_ratio(g, g.index_of(road)) >= 1.0:
			jam_cell = road
			break
	check.call("jam colored red", jam_cell.x >= 0 and zv.multimesh.get_instance_color(g.index_of(jam_cell)).is_equal_approx(zv.TRAFFIC_JAM))

	# --- Машинки ---
	clock.set_speed(1)
	for i in 3:
		cars._process(0.05)
	var expected: int = mini(300, roundi(maxf(0.0, gs.traffic.total_workers - gs.traffic.walkers - gs.traffic.cyclists) / cars.WORKERS_PER_CAR))
	check.call("car count %d/%d" % [cars.visible_car_count(), expected], cars.visible_car_count() == expected)
	var on_road := true
	for i in cars.visible_car_count():
		var p: Vector3 = cars.car_origin(i)
		var c: Vector2i = g.world_to_grid(p)
		if not g.is_road(c): on_road = false
	check.call("cars on roads", on_road)
	# Снос дороги на пути машинки — путь сразу меняется.
	var victim: int = cars._cars[0].path[1]
	var vcell := Vector2i(victim % g.size, victim / g.size)
	g.remove_road(vcell)
	var removed: Array[Vector2i] = [vcell]
	ev.cells_changed.emit(removed)
	cars._process(0.05)
	var still_using := false
	for car in cars._cars:
		if car.path.has(victim): still_using = true
	check.call("broken paths dropped", not still_using)
	g.set_road(vcell)
	ev.cells_changed.emit(removed)
	clock.set_speed(0)
	cars._process(0.05)
	var frozen: Vector3 = cars.car_origin(0)
	cars._process(0.5)
	check.call("cars stop on pause", cars.car_origin(0) == frozen)

	# --- Производительность: 256×256 ---
	var big := CityGrid.new(256)
	for y in range(4, 252, 6):
		for x in range(2, 254): big.set_road(Vector2i(x, y))
	for x in range(4, 252, 12):
		for y in range(2, 254): big.set_road(Vector2i(x, y))
	var placed := 0
	for y in range(5, 251, 6):
		for x in range(3, 253, 2):
			var type_id: StringName = &"res_small_01" if (x / 30) % 2 == 0 else &"ind_small_01"
			var id: int = big.place_building(type_id, Vector2i(x, y), 0)
			if id >= 0:
				big.buildings[id].powered = true
				big.buildings[id].has_water = true
				placed += 1
	var start := Time.get_ticks_msec()
	var tb = TR.compute(big)
	var ms := Time.get_ticks_msec() - start
	print("256x256: roads=%d buildings=%d workers=%.0f compute=%d ms" % [big.road_cells.size(), placed, tb.total_workers, ms])

	# Снимок: слой трафика и машинки.
	clock.set_speed(1)
	var cam: Node3D = main.get_node("RTSCamera")
	cam.position = Vector3(56, 0, 44)
	cam._target_distance = 46.0
	cam._distance = 46.0
	cam._apply_distance()
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(SHOT)
	clock.set_speed(0)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
