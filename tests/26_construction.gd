extends SceneTree
## Анимация стройки: срок по размеру здания, площадка на каждое строящееся здание, дом растёт снизу
## вверх, леса до текущей высоты, краны по размеру; после стройки площадка уходит, дом — обычный.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var LV: GDScript = load("res://scripts/simulation/levels.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var cv: Node = main.get_node("ConstructionVisualizer")
	var bv: Node = main.get_node("BuildingVisualizer")
	var g: CityGrid = gs.grid

	# Срок по размеру.
	var small: BuildingData = BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL, 1, Vector2i(1, 1))[0]
	var row: BuildingData = BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL, 1, Vector2i(3, 1))[0]
	var tower: BuildingData = BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL_HIGH, 3, Vector2i(2, 2))[0]
	var office: BuildingData = BuildingCatalog.level_types(CityGrid.Zone.OFFICE, 3, Vector2i(3, 2))[0]
	var t_small: int = LV.construction_ticks_for(small)
	var t_row: int = LV.construction_ticks_for(row)
	var t_tower: int = LV.construction_ticks_for(tower)
	print("ticks: small %d row %d tower %d office %d" % [t_small, t_row, t_tower, LV.construction_ticks_for(office)])
	check.call("small house takes 8 minutes", t_small == 8)
	check.call("bigger takes longer", t_small < t_row and t_row < t_tower)

	# Рост ставит стройку со сроком по размеру.
	for x in range(10, 40): g.set_road(Vector2i(x, 30))
	g.place_building(&"power_plant_01", Vector2i(10, 29), 2, true)
	g.place_building(&"water_tower_01", Vector2i(11, 29), 2, true)
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		var tool: Node = main.get_node("BuildTool")
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	gs.money = 100000
	drag.call(main.get_node("BuildTool").Mode.ZONE_R, Vector2i(14, 29), Vector2i(20, 29))
	var grown: BuildingInstance = null
	for i in 30:
		ev.sim_tick.emit()
		for b: BuildingInstance in g.buildings.values():
			if b.construction_ticks > 0 and BuildingCatalog.get_type(b.type_id).zone == CityGrid.Zone.RESIDENTIAL:
				grown = b
		if grown != null: break
	check.call("growth starts a site", grown != null and grown.construction_total == LV.construction_ticks_for(BuildingCatalog.get_type(grown.type_id))
			and grown.construction_ticks == grown.construction_total)
	check.call("site drawn by construction visualizer", grown != null and cv._sites.has(grown.id)
			and bv.get_cell_item(Vector3i(grown.cell.x, 0, grown.cell.y)) == bv._construction_item
			and bv._layers[bv._construction_item].multimesh.instance_count == 0)

	# Стройки разных размеров — каждая на своей стадии.
	var place := func(data: BuildingData, cell: Vector2i, dir: int) -> BuildingInstance:
		var id: int = g.place_building(data.id, cell, dir)
		var b: BuildingInstance = g.buildings[id]
		LV.start_construction(b, data)
		return b
	var b_small: BuildingInstance = place.call(small, Vector2i(24, 29), 2)
	var b_tower: BuildingInstance = place.call(tower, Vector2i(26, 31), 0)
	var b_office: BuildingInstance = place.call(office, Vector2i(30, 31), 0)
	ev.grid_reset.emit()
	await process_frame
	var s_small = cv._sites[b_small.id]
	var s_tower = cv._sites[b_tower.id]
	var s_office = cv._sites[b_office.id]
	check.call("cranes by size (%d, %d, %d)" % [s_small.cranes.size(), s_tower.cranes.size(), s_office.cranes.size()],
			s_small.cranes.is_empty() and s_tower.cranes.size() >= 1 and s_office.cranes.size() == 2)
	check.call("taller crane for taller building", s_office.mast > s_small.height + 1.0)

	# Плавный рост: фундамент → стены → леса разбирают.
	var progress := func(b: BuildingInstance) -> float:
		return cv.progress_of(b, clock.tick_progress())
	check.call("starts at zero", progress.call(b_tower) < 0.05)
	cv._process(0.016)
	check.call("only foundation at start", s_tower.cut < 0.0 and s_tower.levels == 0)
	var cuts: Array[float] = []
	var levels: Array[int] = []
	var total: int = b_tower.construction_total
	for k in total - 1:
		LV.tick_construction(g)
		cv._process(0.016)
		cuts.append(s_tower.cut)
		levels.append(s_tower.levels)
	var rising := true
	for k in range(1, cuts.size()):
		if cuts[k] < cuts[k - 1]: rising = false
	print("cuts: ", ", ".join(PackedStringArray(cuts.map(func(c: float) -> String: return "%.1f" % c))))
	print("levels: ", levels)
	check.call("walls rise steadily", rising and cuts[cuts.size() / 2] > 0.0 and cuts[cuts.size() / 2] < s_tower.height)
	check.call("scaffold grows with walls", levels.max() >= s_tower.max_levels - 3 and levels[0] == 0
			and levels[cuts.size() / 2] > 0)
	check.call("scaffold dismantled at the end", levels[levels.size() - 1] < s_tower.max_levels)
	check.call("walls shader gets the cut", is_equal_approx(s_tower.walls.get_instance_shader_parameter(&"cut_height"), s_tower.cut))
	var scaffold_mid: int = cv._scaffold.multimesh.instance_count
	check.call("scaffold instances drawn (%d)" % scaffold_mid, scaffold_mid > 0)
	check.call("crane parts drawn", cv._mast.multimesh.instance_count > 0 and cv._jib.multimesh.instance_count >= 3)

	# Готово — площадка уходит, дом рисует BuildingVisualizer.
	LV.tick_construction(g)
	var done: Array[Vector2i] = b_tower.cells()
	ev.cells_changed.emit(done)
	check.call("site removed when done", not cv._sites.has(b_tower.id))
	check.call("building drawn after construction", bv.get_cell_item(Vector3i(b_tower.cell.x, 0, b_tower.cell.y)) not in [-1, bv._construction_item])

	# Плавно между тиками: доля тика двигает срез (новая стройка — прежние уже достроены).
	b_office = place.call(office, Vector2i(30, 27), 2)
	ev.grid_reset.emit()
	clock.set_speed(1)
	var before: float = cv.progress_of(b_office, 0.0)
	var after: float = cv.progress_of(b_office, 0.9)
	check.call("progress between ticks", after > before)
	clock.set_speed(0)

	# Карточка «Инфо»: проценты стройки.
	ev.cell_inspected.emit(b_office.cell)
	await process_frame
	var hud: Node = main.get_node("HUD")
	var text := ""
	for label in hud.find_children("*", "Label", true, false):
		text += label.text + "|"
	check.call("info shows construction percent", text.contains("Стройка") and text.contains("%, ещё"))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
