extends SceneTree
## Фаза 9: вода, мост, слои загрязнения / шума / цены земли, рост, налог, парки, карточка «Инфо».
const OUT := "res://tests/out/"

func _initialize() -> void:
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var sm: Node = root.get_node("SaveManager")
	root.get_node("SimClock").set_speed(0)
	sm.save_dir = OUT + "saves13/"
	DirAccess.make_dir_recursive_absolute(sm.save_dir)
	var E: GDScript = load("res://scripts/simulation/economy.gd")
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var ZV: GDScript = load("res://scripts/grid/zone_visualizer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# --- Размытие: одиночный источник ---
	var g := CityGrid.new(32)
	g.set_road(Vector2i(10, 11))
	g.place_building(&"power_plant_01", Vector2i(10, 10), 0, true)
	var lv = LV.compute(g, TR.new())
	var at := func(layer: PackedByteArray, c: Vector2i) -> int: return layer[g.index_of(c)]
	check.call("source keeps strength", at.call(lv.pollution, Vector2i(10, 10)) == 70)
	check.call("fades with distance", at.call(lv.pollution, Vector2i(12, 10)) < 70 and at.call(lv.pollution, Vector2i(12, 10)) > 0)
	check.call("zero past radius", at.call(lv.pollution, Vector2i(15, 10)) == 0)
	var ge := CityGrid.new(32)
	for x in range(0, 32): ge.set_road(Vector2i(x, 5))
	ge.place_building(&"power_plant_01", Vector2i(0, 4), 0, true)
	var le = LV.compute(ge, TR.new())
	check.call("edge source keeps strength", le.pollution[ge.index_of(Vector2i(0, 4))] == 70)
	var gc := CityGrid.new(32)
	gc.place_building(&"school_01", Vector2i(10, 10), 0, true)
	var lc = LV.compute(gc, TR.new())
	check.call("inactive service gives no bonus", lc.land_value[gc.index_of(Vector2i(11, 10))] <= roundi(LV.BASE_VALUE))
	check.call("pollution lowers value", at.call(lv.land_value, Vector2i(10, 10)) < roundi(LV.BASE_VALUE))
	g.place_building(&"park_plaza", Vector2i(20, 20), 0, true)
	lv = LV.compute(g, TR.new())
	check.call("park raises value", at.call(lv.land_value, Vector2i(21, 20)) > roundi(LV.BASE_VALUE))

	# --- Вода ---
	sm.new_city()
	await process_frame
	var city: CityGrid = gs.grid
	var water_cells: Array[Vector2i] = []
	for y in city.size:
		for x in city.size:
			if city.is_water(Vector2i(x, y)): water_cells.append(Vector2i(x, y))
	check.call("new city has river (%d cells)" % water_cells.size(), water_cells.size() >= city.size * 2)
	var wv: Node = main.get_node("WaterVisualizer")
	check.call("water drawn", wv.water_cell_count() == water_cells.size())
	var w: Vector2i = water_cells[water_cells.size() / 2]
	check.call("no zone on water", not city.can_zone(w, CityGrid.Zone.RESIDENTIAL))
	check.call("no building on water", city.place_building(&"park_square", w, 0, true) == -1)
	check.call("road on water allowed", city.can_set_road(w))
	# Мост не даёт доступа к дороге клеткам берега.
	var gb := CityGrid.new(16)
	for z in range(0, 16): gb.water[gb.index_of(Vector2i(8, z))] = 1
	gb.set_road(Vector2i(8, 5))
	check.call("bridge gives no road access", not gb.has_road_access(Vector2i(7, 5)) and not gb.has_road_access(Vector2i(9, 6)))
	# Мост дороже дороги — через инструмент.
	var tool: Node = main.get_node("BuildTool")
	ev.tool_requested.emit(1)
	tool._drag_start = w
	tool._update_drag(w)
	var m0: int = gs.money
	tool._apply()
	tool._end_drag()
	check.call("bridge costs more", city.is_road(w) and m0 - gs.money == E.BRIDGE_COST)
	city.remove_road(w)
	check.call("water stays after road removed", city.is_water(w))
	# Сохранение воды.
	sm.save_city("Река")
	var copy: Dictionary = CS.to_dict(city, "x", 0, 9, 0, 0)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(copy)))
	check.call("water saved", back.ok and back.grid.water == city.water)
	copy.grid.erase("water")
	back = CS.from_dict(JSON.parse_string(JSON.stringify(copy)))
	check.call("old save without water loads", back.ok and back.grid.water.count(1) == 0)

	# --- Рост и налог на ровной суше ---
	sm.with_river = false
	sm.with_highway = false
	sm.new_city()
	gs.rng.seed = 20261109  # своё зерно: с «домом по стадиям» число домов от случая скачет 8–14
	await process_frame
	city = gs.grid
	for x in range(10, 56): city.set_road(Vector2i(x, 20))
	city.place_building(&"power_plant_01", Vector2i(10, 21), 0, true)
	city.place_building(&"water_tower_01", Vector2i(11, 21), 0, true)
	city.place_building(&"water_tower_01", Vector2i(12, 21), 0, true)
	# Жилая зона у ТЭЦ и далеко от неё.
	for x in range(13, 39):
		for z in [18, 19, 21, 22]:
			city.set_zone(Vector2i(x, z), CityGrid.Zone.RESIDENTIAL)
	for x in range(39, 44):
		for z in [18, 19, 21, 22]:
			city.set_zone(Vector2i(x, z), CityGrid.Zone.COMMERCIAL)
	for x in range(46, 55):
		for z in [18, 19, 21, 22]:
			city.set_zone(Vector2i(x, z), CityGrid.Zone.INDUSTRIAL)
	for c in [Vector2i(13, 23), Vector2i(14, 23)]:
		city.place_building(&"power_plant_01", c, 0, true)
	for c in [Vector2i(15, 23), Vector2i(16, 23)]:
		city.place_building(&"water_tower_01", c, 0, true)
	ev.grid_reset.emit()
	await process_frame
	for i in 80: ev.sim_tick.emit()
	var dirty_homes := 0
	var homes := 0
	for b: BuildingInstance in city.buildings.values():
		if BuildingCatalog.get_type(b.type_id).population > 0:
			homes += 1
			if gs.land.value_at(gs.land.pollution, city, b.cell) >= GR.MAX_HOME_POLLUTION: dirty_homes += 1
	check.call("homes grew (%d, pop %d)" % [homes, gs.population], homes >= 8 and gs.population > 30)
	check.call("no homes in pollution", dirty_homes == 0)
	var base := 0.0
	for b: BuildingInstance in city.buildings.values():
		var d: BuildingData = BuildingCatalog.get_type(b.type_id)
		if b.abandoned: continue  # брошенные налогов не платят (Decay)
		base += (d.population + d.jobs) * E.land_factor(gs.land.building_value(gs.land.land_value, city, b))
	check.call("income uses land value", gs.income == E.daily_income(base, gs.tax_rate))
	# Парк поднимает доход.
	var income_before: int = gs.income
	for x in [22, 28, 34]:
		city.place_building(&"park_plaza", Vector2i(x, 23), 0, true)
	ev.cells_changed.emit([Vector2i(22, 23)] as Array[Vector2i])
	check.call("parks raise income (%d → %d)" % [income_before, gs.income], gs.income > income_before)

	# --- Слои карты и карточка «Инфо» ---
	var zv: Node = main.get_node("ZoneVisualizer")
	for o in [5, 6, 7]:
		zv.set_overlay(o)
	check.call("overlays exist", ZV.OVERLAY_NAMES.size() == 8)
	zv.set_overlay(0)
	var hud: Node = main.get_node("HUD")
	ev.cell_inspected.emit(Vector2i(22, 23))
	check.call("info panel shows park", hud._info.visible and hud._info._title.text == "Площадь")
	check.call("parks tab", hud._tab_cards.has("parks") and hud._tab_cards["parks"].get_child_count() == 3)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
