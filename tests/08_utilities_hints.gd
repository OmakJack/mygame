extends SceneTree
## Свет и вода, постановка станций, подсказки «Шаг 1/2/3».
func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g: CityGrid = gs.grid
	var tool: Node = main.get_node("BuildTool")
	var hud: CanvasLayer = main.get_node("HUD")
	var zv: MultiMeshInstance3D = main.get_node("ZoneVisualizer")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var cursor: Node = main.get_node("CellCursor")
	var place := func(type_id: StringName, cell: Vector2i) -> void:
		ev.building_place_requested.emit(type_id)
		cursor.has_cell = true
		tool._dragging = true; tool._drag_start = cell
		tool._update_drag(cell); tool._apply(); tool._end_drag()
	var hints_text := func() -> String:
		var parts: PackedStringArray = []
		for l in hud.get_node("%Hints").get_children():
			if not l.is_queued_for_deletion(): parts.append(l.text)
		return "|".join(parts)
	var tick := func(n: int) -> void:
		for i in n: ev.sim_tick.emit()
	check.call("catalog", BuildingCatalog.buildable_types().size() == 14 and hud._service_buttons.size() == 14)
	check.call("step 1 hint", hints_text.call().contains("Шаг 1"))
	drag.call(tool.Mode.ROAD, Vector2i(5,20), Vector2i(40,20))
	check.call("step 2 hint", hints_text.call().contains("Шаг 2"))
	drag.call(tool.Mode.ZONE_R, Vector2i(5,17), Vector2i(39,19))
	drag.call(tool.Mode.ZONE_I, Vector2i(5,21), Vector2i(39,23))
	# Без станций — растёт (со значками над крышами), подсказки про свет и ТЭЦ.
	tick.call(15)
	var dark_homes: int = 0
	for b: BuildingInstance in g.buildings.values():
		if not b.powered and not b.has_water: dark_homes += 1
	check.call("growth without utilities", not g.buildings.is_empty() and dark_homes == g.buildings.size())
	check.call("hint no utilities", hints_text.call().contains("Нет света у") and hints_text.call().contains("Нет ТЭЦ или водокачки"))
	# Постановка ТЭЦ на клетку жилой зоны: зона стирается, деньги списываются.
	# Дома растут и до станций — освобождаем клетки под ТЭЦ и водокачку.
	for c in [Vector2i(20,19), Vector2i(21,21)]:
		var occupant: BuildingInstance = g.get_building_at(c)
		if occupant != null: g.remove_building(occupant.id)
	gs.money = 2000
	var m: int = gs.money
	place.call(&"power_plant_01", Vector2i(20,19))
	var plant: BuildingInstance = g.get_building_at(Vector2i(20,19))
	check.call("plant placed", plant != null and plant.orientation == 2 and gs.money == m - 250 and g.get_zone(Vector2i(20,19)) == CityGrid.Zone.NONE)
	check.call("tool mode place", tool.mode == tool.Mode.PLACE and hud._service_buttons[&"power_plant_01"].button_pressed and not hud._tool_buttons[tool.Mode.ROAD].button_pressed)
	# Нельзя: занято / нет дороги.
	check.call("cannot place occupied", not tool._can_place(Vector2i(20,19)))
	check.call("cannot place no road", not tool._can_place(Vector2i(20,10)))
	place.call(&"water_tower_01", Vector2i(21,21))
	# На паузе: свет и вода сразу.
	check.call("utilities on pause", gs.utilities.power_supply == 100 and gs.utilities.water_supply == 100 and gs.utilities.power_use > 2)
	hud._select_tab("filters")
	check.call("power filter card", hud._filters._cards[1].text == "Свет
загрузка %d%%" % gs.utilities.power_use)
	hud._select_tab("utilities")
	check.call("expenses include upkeep", gs.expenses == roundi(36 * 0.2) + 10)
	# Рост с запасом.
	tick.call(60)
	var homes: int = 0
	for b: BuildingInstance in g.buildings.values():
		if BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE: homes += 1
	print("after 60 ticks: homes=%d pop=%d power %d/%d water %d/%d money=%d" % [homes, gs.population, gs.utilities.power_use, gs.utilities.power_supply, gs.utilities.water_use, gs.utilities.water_supply, gs.money])
	check.call("grew (%d homes, pop %d)" % [homes, gs.population], homes >= 5 and gs.population > 30)
	# Значок — над каждым готовым зданием, которому не хватило.
	var want := Vector2i.ZERO
	for b: BuildingInstance in g.buildings.values():
		var bd: BuildingData = BuildingCatalog.get_type(b.type_id)
		if b.construction_ticks > 0: continue
		if bd.power_use > 0 and not b.powered: want.x += 1
		if bd.water_use > 0 and not b.has_water: want.y += 1
	check.call("badges match outages (%s)" % want, main.get_node("BadgeVisualizer").counts() == want)
	var last_grown: BuildingInstance = null
	for b: BuildingInstance in g.buildings.values():
		if BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE: last_grown = b
	check.call("grown zone kept", last_grown != null and g.get_zone(last_grown.cell) != CityGrid.Zone.NONE)
	# Домов меньше, чем до 2026-11-01 (жителей в доме втрое меньше, рост раньше упирается в спрос
	# без магазинов) — если на восток никто не вырос, ставим дом там сами.
	var has_east := false
	for b: BuildingInstance in g.buildings.values():
		if b.cell.x > 31 and BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE: has_east = true
	for x in range(32, 40):
		if not has_east:
			has_east = g.place_building(&"res_small_01", Vector2i(x, 19), 2) >= 0
	# Разрыв дороги: восточная часть без света.
	gs.money = 5000
	drag.call(tool.Mode.BULLDOZE, Vector2i(30,20), Vector2i(30,20))
	check.call("split network", gs.network.component_count == 2)
	var east: Array[BuildingInstance] = []
	for b: BuildingInstance in g.buildings.values():
		if b.cell.x > 31 and BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE: east.append(b)
	var east_dark: bool = not east.is_empty()
	for b in east:
		if b.powered: east_dark = false
	check.call("east dark on pause (%d)" % east.size(), east_dark and gs.utilities.unpowered_count >= east.size())
	# Школа на востоке (без света) не сносится и не работает.
	var school_cell := Vector2i(-1, -1)
	for y in range(17, 24):
		for x in range(32, 40):
			var c := Vector2i(x, y)
			if school_cell.x < 0 and g.can_set_road(c) and g.has_road_access(c): school_cell = c
	place.call(&"school_01", school_cell)
	var school: BuildingInstance = g.get_building_at(school_cell)
	check.call("school placed", school != null)
	tick.call(9)
	var east_alive: int = 0
	for b in east:
		if g.buildings.has(b.id): east_alive += 1
	check.call("east kept 9 ticks", east_alive == east.size())
	# Срок без света — 6 игровых часов: подводим счётчики к концу срока.
	for b in east:
		b.construction_ticks = 0
		b.no_power_ticks = main.get_node("Simulation").UTILITY_ABANDON_TICKS - 1
	tick.call(1)
	east_alive = 0
	for b in east:
		if g.buildings.has(b.id): east_alive += 1
	check.call("east abandoned at deadline", east_alive == 0)
	check.call("services never abandon", g.buildings.has(school.id) and g.buildings.has(plant.id))
	check.call("school inactive", gs.service_coverage.get(BuildingData.Service.SCHOOL, 0.0) == 0.0)
	if gs.population >= 150:
		check.call("hint school", hints_text.call().contains("школа"))
	# Отпускание над панелью UI ничего не ставит.
	var n_before: int = g.buildings.size()
	ev.building_place_requested.emit(&"police_01")
	cursor.has_cell = true
	tool._dragging = true; tool._drag_start = Vector2i(12,21); tool._update_drag(Vector2i(12,22))
	cursor.has_cell = false
	tool._apply(); tool._end_drag()
	check.call("no place over UI", g.buildings.size() == n_before)
	check.call("tooltip", hud._service_buttons[&"school_01"].tooltip_text.contains("с 150 жителей") and hud._service_buttons[&"water_tower_01"].tooltip_text.contains("Даёт воду: 100"))
	# Восстановить дорогу — школа заработает.
	drag.call(tool.Mode.ROAD, Vector2i(30,20), Vector2i(30,20))
	check.call("school active", school.powered and school.has_water and Services.is_active(g, school, BuildingCatalog.get_type(&"school_01")))
	check.call("offset", is_equal_approx(Services.demand_offset({BuildingData.Service.SCHOOL: 0.0}, 150), -0.125) and is_equal_approx(Services.demand_offset({}, 50), 0.0))
	# Рост без запаса идёт — дом без света и воды.
	var empty_util := Utilities.new()
	var rng := RandomNumberGenerator.new()
	var grown: Vector2i = Growth.grow_one(g, CityGrid.Zone.RESIDENTIAL, rng, gs.network, empty_util)
	var grown_b: BuildingInstance = g.get_building_at(grown) if grown != CityGrid.NO_CELL else null
	check.call("no capacity still grows", g.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].is_empty()
			or (grown_b != null and not grown_b.powered and not grown_b.has_water))
	# Слои карты.
	zv.set_overlay(zv.Overlay.POWER)
	check.call("filter shows power", hud._filters.overlay == 1 and hud._filters._cards[1].button_pressed)
	check.call("plant color", zv.multimesh.get_instance_color(g.index_of(plant.cell)).is_equal_approx(zv.POWER_SOURCE))
	check.call("road color", zv.multimesh.get_instance_color(g.index_of(Vector2i(10,20))).is_equal_approx(zv.POWER_ROAD))
	# Обесточить один дом для снимка: снести ТЭЦ.
	drag.call(tool.Mode.BULLDOZE, plant.cell, plant.cell)
	var some_home: BuildingInstance = null
	for b: BuildingInstance in g.buildings.values():
		if BuildingCatalog.get_type(b.type_id).power_use > 0 and BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE:
			some_home = b
			break
	check.call("unserved color", some_home != null and zv.multimesh.get_instance_color(g.index_of(some_home.cell)).is_equal_approx(zv.UNSERVED))
	tool._set_mode(tool.Mode.NONE)
	var cam: Node3D = main.get_node("RTSCamera")
	cam.position = Vector3(46, 0, 42)
	cam._target_distance = 40.0; cam._distance = 40.0; cam._apply_distance()
	for f in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://tests/out/phase6.png")
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
