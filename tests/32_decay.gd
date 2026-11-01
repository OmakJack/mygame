extends SceneTree
## Видимый упадок (Decay): без дороги дом не исчезает через 3 тика, а через 2 игровых часа пустеет —
## до того значок «нет дороги» и «Опустеет через» в «Инфо»; брошенный дом темнеет (наложение упадка),
## над ним тёмный значок, жителей нет, цена земли вокруг ниже; сохраняется; сносится бульдозером;
## исправили причину — через час въезжают снова (ремонт). Снимок — tests/out/decay.png.

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var sm: Node = root.get_node("SaveManager")
	sm.save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var DC: GDScript = load("res://scripts/simulation/decay.gd")
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	var HN: GDScript = load("res://scripts/ui/hints.gd")
	var tool: Node = main.get_node("BuildTool")
	var badges: Node = main.get_node("BadgeVisualizer")
	var bvis: Node = main.get_node("BuildingVisualizer")
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var run := func(ticks: int) -> void:
		for i in ticks:
			ev.sim_tick.emit()
	# Строки карточки «Инфо» после кадра (старые строки удаляются через queue_free).
	var card_text := func(cell: Vector2i) -> String:
		ev.cell_inspected.emit(cell)
		await process_frame
		var text := ""
		for label in main.get_node("HUD").find_children("*", "Label", true, false):
			text += label.text + "|"
		return text
	var g: CityGrid = gs.grid
	gs.money = 100000
	drag.call(tool.Mode.ROAD, Vector2i(10, 30), Vector2i(50, 30))
	drag.call(tool.Mode.ZONE_R, Vector2i(12, 27), Vector2i(48, 29))
	drag.call(tool.Mode.ZONE_I, Vector2i(14, 31), Vector2i(28, 33))
	g.place_building(&"power_plant_01", Vector2i(10, 31), 0, true)
	g.place_building(&"water_tower_01", Vector2i(11, 31), 0, true)
	g.place_building(&"wind_turbine_02", Vector2i(12, 31), 0, true)
	ev.grid_reset.emit()
	gs.rng.seed = 2026
	run.call(200)
	print("grown %d, population %d" % [g.buildings.size(), gs.population])

	# Сносим восточную часть дороги: дома там без дороги, но не исчезают.
	drag.call(tool.Mode.BULLDOZE, Vector2i(31, 30), Vector2i(50, 30))
	var cut: Array[BuildingInstance] = []
	var sites: Array[int] = []
	for b: BuildingInstance in g.buildings.values():
		if BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.NONE and not g.has_building_road_access(b):
			if b.construction_ticks > 0: sites.append(b.id)
			else: cut.append(b)
	check.call("houses cut off (%d, sites %d)" % [cut.size(), sites.size()], cut.size() >= 4)
	run.call(1)
	check.call("road badges", badges.decay_counts() == Vector2i(cut.size(), 0))
	check.call("hint no road", " ".join(HN.build()).contains("Без дороги %d зд." % (cut.size() + sites.size())))
	var victim: BuildingInstance = cut[0]
	var text: String = await card_text.call(victim.cell)
	check.call("card countdown", text.contains("Опустеет через") and text.contains("1 ч 59 мин — нет дороги"))
	run.call(DC.NO_ROAD_TICKS - 2)
	check.call("not abandoned before deadline", cut.all(func(b: BuildingInstance) -> bool: return not b.abandoned)
			and g.buildings.size() >= cut.size())
	var pop_before: int = gs.population
	run.call(1)
	check.call("abandoned at deadline", cut.all(func(b: BuildingInstance) -> bool:
			return g.buildings.has(b.id) and b.abandoned))
	check.call("sites without road removed", sites.all(func(id: int) -> bool: return not g.buildings.has(id)))
	var cut_people: int = 0
	for b in cut: cut_people += BuildingCatalog.get_type(b.type_id).population
	print("population %d -> %d (cut %d)" % [pop_before, gs.population, cut_people])
	check.call("nobody lives there", gs.population <= pop_before - cut_people + 30 and cut_people > 0)
	check.call("abandoned badges", badges.decay_counts() == Vector2i(0, cut.size()))
	check.call("dark layer", bvis.get_cell_item(Vector3i(victim.cell.x, 0, victim.cell.y)) >= bvis._abandoned_base
			and bvis._layers[bvis.get_cell_item(Vector3i(victim.cell.x, 0, victim.cell.y))].material_overlay != null)
	check.call("no power or water used", gs.utilities.unpowered_count == 0 and gs.utilities.no_water_count == 0)
	check.call("hint abandoned", " ".join(HN.build()).contains("Заброшено %d зд." % cut.size()))
	text = await card_text.call(victim.cell)
	check.call("card abandoned", text.contains("заброшено") and text.contains("Не въезжают") and text.contains("нет дороги")
			and not text.contains("Счастье"))
	# Цена земли вокруг брошенных ниже, чем была бы без упадка.
	var with_decay = LV.compute(g, gs.traffic)
	for b in cut: b.abandoned = false
	var without = LV.compute(g, gs.traffic)
	for b in cut: b.abandoned = true
	var lv_with: int = with_decay.building_value(with_decay.land_value, g, victim)
	var lv_without: int = without.building_value(without.land_value, g, victim)
	check.call("land value drops (%d < %d)" % [lv_with, lv_without], lv_with < lv_without)

	# Снимок: слева живая улица, справа брошенные дома без дороги (карточку и сетку зон прячем).
	tool._set_mode(tool.Mode.NONE)
	main.get_node("HUD")._info.hide()
	for i in 10: await process_frame
	var cam: Node3D = main.get_node("RTSCamera")
	cam.position = Vector3(60, 0, 57)
	cam.rotation.y = deg_to_rad(-12.0)
	cam._target_distance = 15.0
	cam._distance = 15.0
	cam._apply_distance()
	for i in 20: await process_frame
	root.get_texture().get_image().save_png("res://tests/out/decay.png")

	# Сохранение: брошенные остаются брошенными.
	victim.recover_ticks = 7
	check.call("save", sm.save_city("Упадок"))
	check.call("load", sm.load_city(sm.file_id_for("Упадок")))
	g = gs.grid
	var loaded: Array = g.buildings.values().filter(func(b: BuildingInstance) -> bool: return b.abandoned)
	check.call("abandoned saved", loaded.size() == cut.size() and g.buildings[victim.id].recover_ticks == 7)
	victim = g.buildings[victim.id]

	# Бульдозер сносит брошенный дом, зона остаётся.
	var doomed: BuildingInstance = loaded[-1]
	var doomed_cell: Vector2i = doomed.cell
	drag.call(tool.Mode.BULLDOZE, doomed_cell, doomed_cell)
	check.call("bulldoze abandoned", g.get_building_at(doomed_cell) == null
			and g.get_zone(doomed_cell) == CityGrid.Zone.RESIDENTIAL)

	# Вернули дорогу — через час (при спросе) в брошенные дома въезжают снова, после ремонта.
	drag.call(tool.Mode.ROAD, Vector2i(31, 30), Vector2i(50, 30))
	run.call(1)
	var blockers: PackedStringArray = DC.recover_blockers(g, victim, BuildingCatalog.get_type(victim.type_id),
			gs.network, gs.land, gs.traffic, gs.tax_rate, gs.demand_by_zone())
	print("blockers after road: ", blockers)
	victim.recover_ticks = 0
	check.call("road fixes the cause", not blockers.has("нет дороги") and not blockers.has("нет света")
			and not blockers.has("нет воды"))
	var demand_all: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 1.0,
			CityGrid.Zone.COMMERCIAL: 1.0, CityGrid.Zone.INDUSTRIAL: 1.0}
	for i in DC.RECOVER_TICKS - 1:
		DC.step(g, gs.network, gs.land, gs.traffic, gs.tax_rate, demand_all)
	check.call("still abandoned before the hour", victim.abandoned)
	DC.step(g, gs.network, gs.land, gs.traffic, gs.tax_rate, demand_all)
	check.call("residents return after repair", not victim.abandoned and victim.construction_ticks > 0)
	# Без спроса никто не въезжает.
	DC.abandon(g, victim)
	var no_demand: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: -0.2,
			CityGrid.Zone.COMMERCIAL: 0.0, CityGrid.Zone.INDUSTRIAL: 0.0}
	for i in DC.RECOVER_TICKS + 5:
		DC.step(g, gs.network, gs.land, gs.traffic, gs.tax_rate, no_demand)
	check.call("no demand — stays abandoned", victim.abandoned)

	# Служебные здания не пустеют.
	var plant: BuildingInstance = g.get_building_at(Vector2i(10, 31))
	plant.no_road_ticks = DC.NO_ROAD_TICKS + 5
	DC.step(g, gs.network, gs.land, gs.traffic, gs.tax_rate, demand_all)
	check.call("services never abandon", not plant.abandoned)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
