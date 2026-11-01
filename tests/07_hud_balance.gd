extends SceneTree
## Плашка денег: прогноз на паузе, налог, полоски спроса, превью.
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
	# 1. Баланс на паузе: дорога 36 клеток → расходы 7 сразу, без тика.
	drag.call(tool.Mode.ROAD, Vector2i(5,20), Vector2i(40,20))
	check.call("expenses on pause %d" % gs.expenses, gs.expenses == 7 and money_label.text.ends_with("(-420/ч)"))
	check.call("tooltip", money_label.tooltip_text.contains("−$420"))
	g.place_building(&"power_plant_01", Vector2i(4,19), 1, true); g.place_building(&"water_tower_01", Vector2i(4,21), 1, true)
	drag.call(tool.Mode.ZONE_R, Vector2i(5,17), Vector2i(39,19))
	drag.call(tool.Mode.ZONE_I, Vector2i(5,21), Vector2i(39,23))
	for t in 20:
		ev.sim_tick.emit()
	gs.rank = 5  # без награды за звание в этот день
	var m0: int = gs.money
	var inc: int = gs.income
	var exp: int = gs.expenses
	ev.sim_tick.emit()
	# Тик начисляет прогноз, посчитанный по зданиям после роста этого тика.
	check.call("tick applies forecast", gs.money == m0 + gs.income - gs.expenses)
	var inc_before: int = gs.income
	ev.tax_rate_requested.emit(15)
	check.call("tax changes forecast on pause", gs.income > inc_before and money_label.text.contains("/ч)"))
	# 3. Кнопки налога на границах.
	ev.tax_rate_requested.emit(0)
	check.call("tax down disabled", hud.get_node("%TaxDown").disabled and not hud.get_node("%TaxUp").disabled)
	ev.tax_rate_requested.emit(20)
	check.call("tax up disabled", hud.get_node("%TaxUp").disabled and not hud.get_node("%TaxDown").disabled)
	ev.tax_rate_requested.emit(9)
	# 2. Полоски спроса.
	var bars: Array = hud._demand_bars
	check.call("bars", bars.size() == 3 and is_equal_approx(bars[0].value, gs.demand_r) and is_equal_approx(bars[2].value, gs.demand_i))
	# 4. Превью обновляется по stats_changed: денег стало мало, мышь не двигалась.
	tool._set_mode(tool.Mode.ROAD); tool._dragging = true; tool._drag_start = Vector2i(10,30)
	tool._update_drag(Vector2i(20,30))
	check.call("preview full", preview.multimesh.instance_count == 11)
	gs.money = 30
	ev.stats_changed.emit()
	check.call("preview shrinks on stats %d" % preview.multimesh.instance_count, preview.multimesh.instance_count == 3)
	# grid_reset прерывает протягивание и обнуляет часы.
	clock._accumulator = 0.7
	ev.grid_reset.emit()
	check.call("reset", not tool._dragging and preview.multimesh.instance_count == 0 and clock._accumulator == 0.0)
	gs.money = 2000
	ev.stats_changed.emit()
	ev.tax_rate_requested.emit(13)
	var cam: Node3D = main.get_node("RTSCamera")
	cam.position = Vector3(48, 0, 42)
	cam._target_distance = 45.0; cam._distance = 45.0; cam._apply_distance()
	for f in 10:
		await process_frame
	root.get_texture().get_image().get_region(Rect2i(0, 0, 1152, 40)).save_png("res://tests/out/hud_top.png")
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
