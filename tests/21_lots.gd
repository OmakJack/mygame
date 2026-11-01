extends SceneTree
## Участки как в Cities: Skylines: размер здания задаёт выделение зоны.
## 1 клетка — дом 1×1; 2 вдоль улицы — дом 2×1; 5 — 5×1; 4 — делится; 3×2 — 3×2; глубже 2 — полосами.
## Рост ставит ровно размер участка фасадом к дороге; снос оставляет участок; снятие зоны — распускает.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var tool: Node = main.get_node("BuildTool")
	var g: CityGrid = gs.grid
	gs.money = 100000
	gs.rank = 3
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	# Длинная улица вдоль x на z = 20; зоны — над ней (z = 19, 18, 17).
	for x in range(2, 60): g.set_road(Vector2i(x, 20))
	ev.grid_reset.emit()
	await process_frame
	var size_at := func(c: Vector2i) -> Vector2i:
		var lot = g.get_lot(c)
		return lot.building_size() if lot != null else Vector2i.ZERO

	drag.call(tool.Mode.ZONE_R, Vector2i(3, 19), Vector2i(3, 19))
	check.call("1 cell → lot 1x1", size_at.call(Vector2i(3, 19)) == Vector2i(1, 1))
	drag.call(tool.Mode.ZONE_R, Vector2i(6, 19), Vector2i(7, 19))
	check.call("2 cells along road → lot 2x1", size_at.call(Vector2i(6, 19)) == Vector2i(2, 1) and g.get_lot(Vector2i(6, 19)) == g.get_lot(Vector2i(7, 19)))
	drag.call(tool.Mode.ZONE_R, Vector2i(10, 19), Vector2i(14, 19))
	check.call("5 cells → lot 5x1", size_at.call(Vector2i(12, 19)) == Vector2i(5, 1))
	drag.call(tool.Mode.ZONE_R, Vector2i(17, 19), Vector2i(20, 19))
	var four: Vector2i = size_at.call(Vector2i(17, 19))
	check.call("4 cells → 2 + 2 (%s + %s)" % [four, size_at.call(Vector2i(20, 19))], four == Vector2i(2, 1) and size_at.call(Vector2i(20, 19)) == Vector2i(2, 1) and g.get_lot(Vector2i(17, 19)) != g.get_lot(Vector2i(20, 19)))
	check.call("planner: 6 → 3+3, 9 → 3+3+3", LotPlanner._split(6, [1, 2, 3, 5], false) == [3, 3] and LotPlanner._split(9, [1, 2, 3, 5], false) == [3, 3, 3] and LotPlanner._split(7, [1, 2, 3, 5, 7], false) == [7])
	drag.call(tool.Mode.ZONE_R, Vector2i(23, 18), Vector2i(25, 19))
	check.call("3x2 selection → lot 3x2", size_at.call(Vector2i(24, 18)) == Vector2i(3, 2))
	drag.call(tool.Mode.ZONE_R, Vector2i(28, 17), Vector2i(30, 19))
	check.call("3 deep → 3x2 front + 3x1 back", size_at.call(Vector2i(29, 19)) == Vector2i(3, 2) and size_at.call(Vector2i(29, 17)) == Vector2i(3, 1))
	check.call("lots face the road (south)", g.get_lot(Vector2i(12, 19)).dir == 2 and g.get_lot(Vector2i(29, 17)).dir == 2)
	# Улица по x = 40 вертикально: участок справа от неё — фасадом на запад, ширина вдоль y.
	for z in range(5, 20): g.set_road(Vector2i(40, z))
	drag.call(tool.Mode.ZONE_I, Vector2i(41, 8), Vector2i(41, 10))
	var lot_w = g.get_lot(Vector2i(41, 9))
	check.call("lot along vertical road: 3x1 facing west", lot_w != null and lot_w.dir == 3 and lot_w.building_size() == Vector2i(3, 1) and lot_w.rect.size == Vector2i(1, 3))

	# Рост: на каждом участке — здание ровно его размера.
	var net := RoadNetwork.new()
	net.update(g)
	var util := Utilities.new()
	for c in net.component_of.values():
		util.spare_power[c] = 100000
		util.spare_water[c] = 100000
	var rng := RandomNumberGenerator.new()
	for i in 40:
		GR.grow_one(g, CityGrid.Zone.RESIDENTIAL, rng, net, util)
		GR.grow_one(g, CityGrid.Zone.INDUSTRIAL, rng, net, util)
	var all_match := true
	var sizes := {}
	for b: BuildingInstance in g.buildings.values():
		var lot = g.get_lot(b.cell)
		var d: BuildingData = BuildingCatalog.get_type(b.type_id)
		if lot == null or lot.rect != Rect2i(b.cell, b.size) or d.size != lot.building_size() or b.orientation != lot.dir:
			all_match = false
		sizes["%dx%d" % [d.size.x, d.size.y]] = true
	check.call("every lot built to its size %s" % str(sizes.keys()), all_match and g.buildings.size() == g.lots.size())
	var b5: BuildingInstance = g.get_building_at(Vector2i(12, 19))
	check.call("5-cell building on 5-cell lot", b5 != null and b5.size == Vector2i(5, 1))

	# Снос дома — участок остаётся и снова строится того же размера.
	g.bulldoze(Vector2i(12, 19))
	check.call("lot stays after bulldoze", size_at.call(Vector2i(12, 19)) == Vector2i(5, 1))
	for i in 10: GR.grow_one(g, CityGrid.Zone.RESIDENTIAL, rng, net, util)
	var regrown: BuildingInstance = g.get_building_at(Vector2i(12, 19))
	check.call("regrows same size", regrown != null and regrown.size == Vector2i(5, 1))

	# Сохранение участков.
	var d2: Dictionary = CS.to_dict(g, "x", 100, 9, 5, 0, 0)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d2)))
	check.call("lots saved", back.ok and back.grid.lots.size() == g.lots.size() and back.grid.get_lot(Vector2i(41, 9)).dir == 3)
	d2.grid.erase("lots")
	back = CS.from_dict(JSON.parse_string(JSON.stringify(d2)))
	check.call("old save without lots loads", back.ok and back.grid.lots.is_empty())

	# Снятие зоны распускает участок.
	g.bulldoze(Vector2i(6, 19))
	drag.call(tool.Mode.DEZONE, Vector2i(6, 19), Vector2i(6, 19))
	check.call("dezone dissolves lot", g.get_lot(Vector2i(7, 19)) == null)

	# Превью разметки: соседние участки — разными оттенками.
	tool._set_mode(tool.Mode.ZONE_C); tool._dragging = true; tool._drag_start = Vector2i(44, 19)
	tool._update_drag(Vector2i(52, 19))
	var preview: Node = main.get_node("ToolPreview")
	var c0: Color = preview.multimesh.get_instance_color(0)
	var different := false
	for i in preview.multimesh.instance_count:
		if preview.multimesh.get_instance_color(i) != c0: different = true
	check.call("preview shows lots (%d cells)" % preview.multimesh.instance_count, preview.multimesh.instance_count == 9 and different)
	tool._end_drag()
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
