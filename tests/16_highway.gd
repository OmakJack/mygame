extends SceneTree
## Трасса за картой: въезд на новой карте, защита от сноса, рост только у связанных дорог,
## приезжие в трафике, сохранение въезда, трасса и машины за картой.
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
	sm.save_dir = OUT + "saves16/"
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var HN: GDScript = load("res://scripts/ui/hints.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Новые карты: въезд на краю, отрезок трассы на суше (и с рекой).
	var all_ok := true
	for i in 12:
		sm.new_city()
		var g0: CityGrid = gs.grid
		if not g0.has_entry() or g0.highway_cells.size() != 5: all_ok = false; continue
		var e: Vector2i = g0.entry
		if not (e.x == 0 or e.y == 0 or e.x == g0.size - 1 or e.y == g0.size - 1): all_ok = false
		for c in g0.highway_cells:
			if g0.is_water(c) or not g0.is_road(c): all_ok = false
	check.call("entry on edge, highway on land", all_ok)
	var g: CityGrid = gs.grid
	var hw: Vector2i = g.highway_cells.keys()[2]
	check.call("highway protected", not g.bulldoze(hw) and g.is_road(hw))

	# Рост: на ровной карте — улица от трассы и отдельная улица без связи.
	sm.with_river = false
	sm.new_city()
	g = gs.grid
	var inward: Vector2i = -CityGrid.NEIGHBORS[g.entry_dir]
	var side := Vector2i(inward.y, inward.x)
	var mid: Vector2i = g.entry + inward * 12
	for k in range(5, 13): g.set_road(g.entry + inward * k)
	for k in range(-8, 9): g.set_road(mid + side * k)
	var far: Vector2i = g.entry + inward * 40
	for k in range(-8, 9): g.set_road(far + side * k)
	for road_mid in [mid, far]:
		g.place_building(&"power_plant_01", road_mid + side * 9 + inward, 0, true)
		g.place_building(&"water_tower_01", road_mid + side * 8 + inward, 0, true)
		g.place_building(&"water_tower_01", road_mid + side * 7 + inward, 0, true)
		for k in range(-7, 6):
			for d in [-1, 1]:
				var c: Vector2i = road_mid + side * k + inward * d
				if g.can_zone(c, 1): g.set_zone(c, 1 if k < 0 else 3)
	ev.grid_reset.emit()
	await process_frame
	for i in 60: ev.sim_tick.emit()
	var near_count := 0
	var far_count := 0
	for b in g.buildings.values():
		if BuildingCatalog.get_type(b.type_id).zone == CityGrid.Zone.NONE: continue
		var dm: Vector2i = b.cell - mid
		if absi(dm.x * inward.x + dm.y * inward.y) <= 2: near_count += 1
		var dfar: Vector2i = b.cell - far
		if absi(dfar.x * inward.x + dfar.y * inward.y) <= 2: far_count += 1
	check.call("connected district grows (%d)" % near_count, near_count > 5)
	check.call("cut-off district does not grow (%d)" % far_count, far_count == 0)
	var hint_found := false
	for h in HN.build():
		if h.contains("не связаны с трассой"): hint_found = true
	check.call("hint about cut-off zones", hint_found)

	# Приезжие едут с въезда: нагрузка на трассе.
	var t = TR.compute(g)
	check.call("commuters load the highway", t.road_load[g.index_of(g.entry)] > 0.0)

	# Сохранение и старые сохранения.
	var d: Dictionary = CS.to_dict(g, "x", 100, 9, 5, 0, 0)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("entry saved", back.ok and back.grid.entry == g.entry and back.grid.highway_cells.size() == 5)
	d.grid.erase("entry")
	back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("old save has no entry (grows freely)", back.ok and not back.grid.has_entry())

	# Вид: трасса за картой и машины.
	var hv: Node = main.get_node("HighwayVisualizer")
	await process_frame
	check.call("outside road drawn", hv.visible and hv._road.multimesh.instance_count == hv.OUTSIDE_CELLS)
	check.call("cars on highway", hv.car_count() > 0)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
