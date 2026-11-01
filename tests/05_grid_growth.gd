extends SceneTree
## Сетка, спрос, рост у дороги, снос инструментом.
func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g: CityGrid = gs.grid
	var tool: Node = main.get_node("BuildTool")
	var bvis = main.get_node("BuildingVisualizer")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	# Каталог.
	check.call("catalog", BuildingCatalog.all_types().size() == 388 and BuildingCatalog.types_for_zone(CityGrid.Zone.RESIDENTIAL).size() == 63 and BuildingCatalog.get_type(&"res_small_01") != null)
	# Направление на дорогу.
	g.set_road(Vector2i(10,10))
	check.call("dir N", g.find_nearest_road_dir(Vector2i(10,12)) == 0)
	check.call("dir W", g.find_nearest_road_dir(Vector2i(12,10)) == 3)
	check.call("dir E", g.find_nearest_road_dir(Vector2i(8,10)) == 1)
	check.call("dir S", g.find_nearest_road_dir(Vector2i(10,7)) == 2)
	check.call("dir diag", g.find_nearest_road_dir(Vector2i(12,11)) == 3)
	check.call("dir none", g.find_nearest_road_dir(Vector2i(14,10)) == -1)
	g.remove_road(Vector2i(10,10))
	# Спрос пустого города.
	check.call("demand start", is_equal_approx(gs.demand_r, 7.0 / 17.0) and is_equal_approx(gs.demand_i, 5.0 / 13.0) and gs.demand_c == 0.0)
	# Город: дорога y=20, R сверху, I снизу, C на конце.
	drag.call(tool.Mode.ROAD, Vector2i(5,20), Vector2i(40,20))
	g.place_building(&"power_plant_01", Vector2i(4,19), 1, true); g.place_building(&"water_tower_01", Vector2i(4,21), 1, true)
	drag.call(tool.Mode.ZONE_R, Vector2i(5,17), Vector2i(39,19))
	drag.call(tool.Mode.ZONE_I, Vector2i(5,21), Vector2i(39,23))
	drag.call(tool.Mode.ZONE_C, Vector2i(41,18), Vector2i(43,22))
	var cache_ok := func() -> bool:
		for z in [CityGrid.Zone.RESIDENTIAL, CityGrid.Zone.COMMERCIAL, CityGrid.Zone.INDUSTRIAL]:
			var brute := {}
			for y in g.size:
				for x in g.size:
					var i: int = g.index_of(Vector2i(x,y))
					if g.tile_type[i] == CityGrid.Tile.EMPTY and g.zone[i] == z:
						brute[Vector2i(x,y)] = true
			if brute.size() != g.zoned_empty_cells[z].size(): return false
			for c in brute:
				if not g.zoned_empty_cells[z].has(c): return false
		return true
	check.call("cache after zoning", cache_ok.call())
	var cells_signals := [0]
	ev.cells_changed.connect(func(c): cells_signals[0] += 1)
	for t in 40:
		ev.sim_tick.emit()
	print("after 40 ticks: buildings=%d pop=%d jobs C=%d I=%d demand R=%.2f C=%.2f I=%.2f" % [g.buildings.size(), gs.population, gs.jobs_commercial, gs.jobs_industrial, gs.demand_r, gs.demand_c, gs.demand_i])
	check.call("grew", gs.population > 0 and gs.jobs_industrial > 0 and gs.jobs_commercial > 0)
	check.call("one signal per tick", cells_signals[0] <= 40)
	check.call("cache after growth", cache_ok.call())
	var faces_ok := true
	var vis_ok := true
	for b: BuildingInstance in g.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(b.type_id)
		if data.zone != g.get_zone(b.cell): faces_ok = false
		if data.zone != CityGrid.Zone.NONE and b.cell.y < 20 and b.cell.x <= 40 and b.orientation != 2: faces_ok = false
		if data.zone != CityGrid.Zone.NONE and b.cell.y > 20 and b.cell.x <= 40 and b.orientation != 0: faces_ok = false
		if data.zone != CityGrid.Zone.NONE and bvis.get_cell_item(Vector3i(b.cell.x, 0, b.cell.y)) == -1: vis_ok = false
	check.call("zone match + facing road", faces_ok)
	check.call("visualizer", vis_ok)
	# Снос дома инструментом: зона остаётся, клетка снова в кэше.
	var some: BuildingInstance = g.buildings.values()[-1]
	var cell: Vector2i = some.cell
	drag.call(tool.Mode.BULLDOZE, cell, cell)
	check.call("bulldoze building", g.get_building_at(cell) == null and g.get_zone(cell) != CityGrid.Zone.NONE and g.zoned_empty_cells[g.get_zone(cell)].has(cell))
	check.call("vis cleared", bvis.get_cell_item(Vector3i(cell.x,0,cell.y)) == -1)
	# Снять зону под домом нельзя.
	var other: BuildingInstance = g.buildings.values()[0]
	check.call("no dezone under building", not g.can_zone(other.cell, CityGrid.Zone.NONE))
	# Упадок (Decay): сносим дорогу — дома стоят NO_ROAD_TICKS тиков, потом пустеют (а не исчезают).
	var no_road_ticks: int = load("res://scripts/simulation/decay.gd").NO_ROAD_TICKS
	drag.call(tool.Mode.BULLDOZE, Vector2i(5,20), Vector2i(40,20))
	var n: int = g.buildings.size()
	for i in no_road_ticks - 1: ev.sim_tick.emit()
	check.call("kept until the deadline", g.buildings.size() == n and gs.population > 0)
	ev.sim_tick.emit()
	var left: Array = g.buildings.values().filter(func(b: BuildingInstance) -> bool:
		return BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE)
	check.call("abandoned at the deadline", gs.population == 0 and not left.is_empty()
			and left.all(func(b: BuildingInstance) -> bool: return b.abandoned))
	check.call("zones kept", g.get_zone(Vector2i(10,18)) == CityGrid.Zone.RESIDENTIAL)
	check.call("cache after abandon", cache_ok.call())
	# SimClock.
	var ticks := [0]
	ev.sim_tick.connect(func(): ticks[0] += 1)
	var m0: int = gs.minutes
	# Автосохранение считает от времени старта (07:00), а не от минуты 0.
	check.call("autosave counts from start time", root.get_node("SaveManager")._last_autosave_minute == gs.minutes)
	clock.set_speed(1)
	clock._process(1.0); clock._process(1.2)
	check.call("tick x1 = one minute", ticks[0] == 1 and gs.minutes == m0 + 1)
	# Игровое время: часы с минутами, сутки из 24 тиков.
	check.call("clock text %s" % clock.time_text(), clock.time_text().length() == 5 and clock.time_text()[2] == ":")
	check.call("game time", GameTime.day_of(0) == 1 and GameTime.day_of(1439) == 1 and GameTime.day_of(1440) == 2
			and GameTime.clock(1440 + 14 * 60 + 5) == "14:05" and GameTime.clock(GameTime.START_MINUTES) == "07:00"
			and GameTime.clock(1439) == "23:59" and GameTime.from_old_days(3) == 3 * 1440 + 7 * 60
			and GameTime.from_old_hours(30) == 1800 and GameTime.per_hour(7) == 420.0)
	# Темп как в SimCity: час — 2 мин на ×1, сутки — 48 мин.
	check.call("simcity pace", is_equal_approx(clock.seconds_per_hour(1), 120.0) and is_equal_approx(clock.seconds_per_hour(8), 15.0))
	var mm: int = gs.minutes
	gs.minutes = 1439
	check.call("day from minutes", gs.day == 1)
	gs.minutes = 1440
	check.call("next day at midnight", gs.day == 2)
	gs.minutes = mm
	clock.toggle_pause()
	clock._process(20.0)
	check.call("paused", ticks[0] == 1 and clock.speed == 0)
	clock.toggle_pause()
	check.call("unpause back to 1", clock.speed == 1)
	clock.set_speed(8)
	clock._process(0.25)
	check.call("x8 tick every 0.25 s", ticks[0] == 2)
	clock.set_speed(3)
	clock._process(20.0)
	check.call("capped", ticks[0] == 5)
	clock.set_speed(0)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
