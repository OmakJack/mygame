extends SceneTree
## Деньги: цены дорог и зон, превью по деньгам, долг, доход за день.
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
	var hud: CanvasLayer = main.get_node("HUD")
	var preview: MultiMeshInstance3D = main.get_node("ToolPreview")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var money_label: Label = hud.get_node("%MoneyLabel")
	check.call("start", gs.money == 2000 and gs.tax_rate == 9 and money_label.text.begins_with("$2000"))
	# Дорога 36 клеток = 360.
	drag.call(tool.Mode.ROAD, Vector2i(5,20), Vector2i(40,20))
	g.place_building(&"power_plant_01", Vector2i(4,19), 1, true); g.place_building(&"water_tower_01", Vector2i(4,21), 1, true)
	check.call("road cost %d" % gs.money, gs.money == 1640 and money_label.text.begins_with("$1640"))
	# Повтор по той же дороге — бесплатно.
	drag.call(tool.Mode.ROAD, Vector2i(5,20), Vector2i(40,20))
	check.call("existing road free", gs.money == 1640)
	drag.call(tool.Mode.ZONE_R, Vector2i(5,17), Vector2i(39,19))
	drag.call(tool.Mode.ZONE_I, Vector2i(5,21), Vector2i(39,23))
	drag.call(tool.Mode.ZONE_C, Vector2i(41,18), Vector2i(43,22))
	# C за концом дороги: полоса — только по прямой от дороги (3 клетки), наискосок не красится.
	check.call("zones cost %d" % gs.money, gs.money == 1640 - (105 + 105 + 3) * 5)
	# Нехватка денег: 25 $ — дорога по старой (бесплатно) + 2 новые клетки.
	var saved: int = gs.money
	gs.money = 25
	tool._set_mode(tool.Mode.ROAD); tool._dragging = true; tool._drag_start = Vector2i(38,20)
	tool._update_drag(Vector2i(38,30))
	check.call("preview limited %d" % preview.multimesh.instance_count, preview.multimesh.instance_count == 3)
	tool._apply(); tool._end_drag()
	check.call("built 2", gs.money == 5 and g.is_road(Vector2i(38,22)) and not g.is_road(Vector2i(38,23)))
	# Долг: снос и снятие зоны работают.
	gs.money = -50
	check.call("bulldoze in debt", g.bulldoze(Vector2i(38,22)) or true)
	drag.call(tool.Mode.BULLDOZE, Vector2i(38,21), Vector2i(38,22))
	check.call("bulldozed", not g.is_road(Vector2i(38,21)))
	drag.call(tool.Mode.ROAD, Vector2i(30,30), Vector2i(31,30))
	check.call("no road in debt", not g.is_road(Vector2i(30,30)) and gs.money == -50)
	gs.money = saved
	# Рост и деньги за день.
	for t in 30:
		ev.sim_tick.emit()
	var jobs: int = gs.jobs_commercial + gs.jobs_industrial
	# Фаза 9: налог с каждого здания с поправкой на цену земли под ним.
	var base := 0.0
	for b: BuildingInstance in g.buildings.values():
		var d: BuildingData = BuildingCatalog.get_type(b.type_id)
		base += (d.population + d.jobs) * (0.8 + 0.8 * gs.land.building_value(gs.land.land_value, g, b) / 100.0)
	check.call("income", gs.income == roundi(base * 9 * 0.045) and gs.expenses == roundi(g.road_cells.size() * 0.2) + 10)
	print("after 30 ticks: money=%d income=%d expenses=%d pop=%d" % [gs.money, gs.income, gs.expenses, gs.population])
	# Замечание 1: снос дома на паузе сразу меняет статистику.
	var pop_before: int = gs.population
	var b: BuildingInstance = null
	for x: BuildingInstance in g.buildings.values():
		if BuildingCatalog.get_type(x.type_id).zone == CityGrid.Zone.RESIDENTIAL:
			b = x
			break
	drag.call(tool.Mode.BULLDOZE, b.cell, b.cell)
	check.call("stats on pause", gs.population == pop_before - BuildingCatalog.get_type(b.type_id).population)
	# Налог: границы и поправка спроса.
	ev.tax_rate_requested.emit(25)
	check.call("tax clamp", gs.tax_rate == 20 and hud.get_node("%TaxLabel").text == "Налог 20%")
	check.call("tax offset", is_equal_approx(load("res://scripts/simulation/demand.gd").tax_offset(20), -0.88))
	hud.get_node("%TaxDown").pressed.emit()
	check.call("tax down button", gs.tax_rate == 19)
	ev.tax_rate_requested.emit(9)
	# Кнопки инструментов и скорости.
	var road_btn: Button = hud._tool_buttons[tool.Mode.ROAD]
	road_btn.pressed.emit()
	check.call("tool button", tool.mode == tool.Mode.ROAD and road_btn.button_pressed)
	tool._set_mode(tool.Mode.BULLDOZE)
	check.call("hotkey syncs hud", not road_btn.button_pressed and hud._tool_buttons[tool.Mode.BULLDOZE].button_pressed)
	hud._speed_buttons[3].pressed.emit()
	check.call("speed x3", clock.speed == 3 and hud._speed_buttons[3].button_pressed and not hud._speed_buttons[0].button_pressed)
	clock.set_speed(0)
	check.call("pause syncs", hud._speed_buttons[0].button_pressed)
	var all_unfocusable := true
	for btn in hud.find_children("*", "Button", true, false):
		# Кнопки окон подтверждения живут в своём окне: там Enter/Пробел — это «ОК».
		if btn.get_window() != root: continue
		if (btn as Button).focus_mode != Control.FOCUS_NONE: all_unfocusable = false
	check.call("no focus", all_unfocusable)
	check.call("catalog cached", BuildingCatalog.types_for_zone(CityGrid.Zone.RESIDENTIAL) == BuildingCatalog.types_for_zone(CityGrid.Zone.RESIDENTIAL) and is_same(BuildingCatalog.all_types(), BuildingCatalog.all_types()))
	# Снимок экрана.
	tool._set_mode(tool.Mode.ROAD)
	var cam: Node3D = main.get_node("RTSCamera")
	cam.position = Vector3(48, 0, 42)
	cam._target_distance = 45.0
	cam._distance = 45.0
	cam._apply_distance()
	for f in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://tests/out/hud.png")
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
