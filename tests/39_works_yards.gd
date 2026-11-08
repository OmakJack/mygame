extends SceneTree
## Дворы заводов (YardVisualizer.Works): один вид на участок — склад (ряды контейнеров у задней границы,
## ярусами), погрузка (грузовики у цеха), баки — за бетонным забором; зелёный двор; у большинства — просто
## трава без забора; вещи — только на клетках двора своего вида; земля двора — по виду; доли видов.
## До 2026-11-08 — контейнеры вразнобой на 70 % клеток.

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var YV: GDScript = load("res://scripts/grid/yard_visualizer.gd")
	var ZV: GDScript = load("res://scripts/grid/zone_visualizer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var tool: Node = main.get_node("BuildTool")
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var g: CityGrid = gs.grid
	gs.money = 1000000
	drag.call(tool.Mode.ROAD, Vector2i(2, 30), Vector2i(44, 30))
	drag.call(tool.Mode.ROAD, Vector2i(2, 39), Vector2i(44, 39))
	drag.call(tool.Mode.ZONE_I, Vector2i(3, 26), Vector2i(43, 29))
	drag.call(tool.Mode.ZONE_I, Vector2i(3, 31), Vector2i(43, 34))
	drag.call(tool.Mode.ZONE_I, Vector2i(3, 35), Vector2i(43, 38))
	tool._set_mode(tool.Mode.NONE)
	ev.grid_reset.emit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 120:
		GR.grow_one(g, CityGrid.Zone.INDUSTRIAL, rng, gs.network, gs.utilities, null, rng.randf_range(0.0, 1.0))
	ev.grid_reset.emit()
	var yards: Node = main.get_node("YardVisualizer")
	var zones: MultiMeshInstance3D = main.get_node("ZoneVisualizer")
	var counts: Dictionary = yards.counts()
	print("   ", counts)

	# Виды дворов по участкам и клетки двора.
	var kinds: Dictionary = {}
	var yard_cells: int = 0
	for lot: CityGrid.Lot in g.lots.values():
		var building: BuildingInstance = g.building_on_lot(lot)
		if building == null or BuildingCatalog.get_type(building.type_id).zone != CityGrid.Zone.INDUSTRIAL:
			continue
		var has_yard: bool = false
		for c: Vector2i in lot.cells():
			if g.is_yard(c):
				yard_cells += 1
				has_yard = true
		if has_yard:
			kinds[YV.works_kind(lot)] = kinds.get(YV.works_kind(lot), 0) + 1
	var furnished: int = 0
	var factories: int = 0
	for kind in kinds:
		factories += kinds[kind]
		if kind in YV.WALLED: furnished += kinds[kind]
	check.call("all five kinds of factory yard on the street %s" % [kinds], kinds.size() == 5)
	check.call("not every factory has a furnished yard (%d of %d)" % [furnished, factories],
			furnished > 0 and furnished * 2 < factories)
	# Бетонный забор — только у обставленных дворов: с одной из сторон бруса — двор склада, погрузки или баков.
	var walls_ok: bool = counts.walls > 0 and counts.fence == 0
	for i in yards._walls.multimesh.instance_count:
		var t: Transform3D = yards._walls.multimesh.get_instance_transform(i)
		var normal: Vector3 = t.basis.z.normalized()
		var walled := false
		for sign in [-1.0, 1.0]:
			var cell: Vector2i = g.world_to_grid(t.origin + normal * 0.3 * sign)
			var lot: CityGrid.Lot = g.get_lot(cell)
			if lot != null and g.is_yard(cell) and YV.works_kind(lot) in YV.WALLED: walled = true
		if not walled: walls_ok = false
	check.call("concrete walls only around furnished yards", walls_ok)
	check.call("far fewer containers than one per yard cell (%d on %d cells)" % [counts.containers, yard_cells],
			counts.containers > 0 and counts.containers < yard_cells)

	# Каждая вещь — на клетке двора завода нужного вида.
	var placed_right := func(layers: Array, allowed: Array) -> bool:
		for layer: MultiMeshInstance3D in layers:
			for i in layer.multimesh.instance_count:
				var cell: Vector2i = g.world_to_grid(layer.multimesh.get_instance_transform(i).origin)
				var lot: CityGrid.Lot = g.get_lot(cell)
				if lot == null or not g.is_yard(cell) or not YV.works_kind(lot) in allowed:
					return false
		return true
	check.call("nothing in plain yards; containers only in storage and loading yards", placed_right.call(yards._containers,
			[YV.Works.STORAGE, YV.Works.LOADING]))
	check.call("trucks only in storage and loading yards", counts.trucks > 0 and placed_right.call(yards._trucks,
			[YV.Works.STORAGE, YV.Works.LOADING]))
	check.call("tanks only in tank yards", counts.tanks > 0 and placed_right.call([yards._tanks, yards._tanks_large],
			[YV.Works.TANKS]))
	# Склад: контейнеры вдоль улицы, часть — во втором ярусе.
	var stacked: bool = false
	var aligned: bool = true
	for layer: MultiMeshInstance3D in yards._containers:
		for i in layer.multimesh.instance_count:
			var t: Transform3D = layer.multimesh.get_instance_transform(i)
			if t.origin.y > 0.1: stacked = true
			var lot: CityGrid.Lot = g.get_lot(g.world_to_grid(t.origin))
			# Длинная сторона контейнера — вдоль улицы участка (ось X модели повёрнута на неё или поперёк — по модели).
			var side := Vector3(CityGrid.NEIGHBORS[(lot.dir + 1) % 4].x, 0, CityGrid.NEIGHBORS[(lot.dir + 1) % 4].y)
			var axis: Vector3 = (t.basis.x if yards._container_turn == 0.0 else t.basis.z).normalized()
			if absf(absf(axis.dot(side)) - 1.0) > 0.01: aligned = false
	check.call("containers stacked in tiers", stacked)
	check.call("containers in rows along the street", aligned)

	# Земля двора — по виду: погрузка — бетон, зелёный — газон.
	var ground_ok: bool = true
	var colors: Dictionary = ZV.get_script_constant_map()
	var expect: Dictionary = {YV.Works.STORAGE: colors.YARD_GRAVEL, YV.Works.LOADING: colors.YARD_CONCRETE,
			YV.Works.TANKS: colors.YARD_TANKS, YV.Works.GREEN: colors.YARD_LAWN, YV.Works.PLAIN: colors.YARD_LAWN}
	for lot: CityGrid.Lot in g.lots.values():
		for c: Vector2i in lot.cells():
			if g.is_yard(c) and g.get_zone(c) == CityGrid.Zone.INDUSTRIAL \
					and zones.multimesh.get_instance_color(g.index_of(c)) != expect[YV.works_kind(lot)]:
				ground_ok = false
	check.call("yard ground by kind", ground_ok)

	# Вид — от участка, доли — как WORKS_SHARES.
	var tally: Array[int] = [0, 0, 0, 0, 0]
	for y in 50:
		for x in 40:
			tally[YV.works_kind(CityGrid.Lot.new(0, Rect2i(x * 3, y * 4, 2, 4), 0))] += 1
	var shares_ok: bool = true
	for k in 5:
		if absf(tally[k] / 2000.0 - YV.WORKS_SHARES[k]) > 0.04: shares_ok = false
	check.call("kind shares %s" % [tally], shares_ok)
	var lot_a := CityGrid.Lot.new(1, Rect2i(7, 9, 2, 4), 2)
	var lot_b := CityGrid.Lot.new(9, Rect2i(7, 9, 2, 4), 0)
	check.call("kind depends on the lot place only (same after reload)", YV.works_kind(lot_a) == YV.works_kind(lot_b))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
