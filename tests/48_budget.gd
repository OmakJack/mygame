extends SceneTree
## Вкладка «Бюджет», как в Cities: Skylines: статьи доходов и расходов сходятся с итогами, история
## по часам копится и сохраняется, панель открывается кнопкой и щелчком по деньгам, налог — ползунком.
## Снимки — tests/out/budget_flow.png, budget_money.png.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.size = Vector2i(1600, 900)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var sm: Node = root.get_node("SaveManager")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var BG: GDScript = load("res://scripts/simulation/budget.gd")
	var BC: GDScript = load("res://scripts/ui/budget_charts.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	sm.with_river = false
	sm.with_highway = false
	sm.new_city()
	await process_frame
	var hud: Node = main.get_node("HUD")
	var sim: Node = main.get_node("Simulation")
	var panel: Node = hud._budget

	# Город: улица и проспект, жильё, магазины, промзона, станции, школа, парк.
	var g: CityGrid = gs.grid
	for x in range(4, 30): g.set_road(Vector2i(x, 30))
	for x in range(30, 46): g.set_road(Vector2i(x, 30), 2)
	for x in range(4, 26):
		for y in range(26, 30): g.set_zone(Vector2i(x, y), CityGrid.Zone.RESIDENTIAL)
	for x in range(4, 14):
		for y in range(31, 35): g.set_zone(Vector2i(x, y), CityGrid.Zone.COMMERCIAL)
	for x in range(32, 46):
		for y in range(31, 35): g.set_zone(Vector2i(x, y), CityGrid.Zone.INDUSTRIAL)
	for x in range(30, 46):
		for y in range(26, 30): g.set_zone(Vector2i(x, y), CityGrid.Zone.RESIDENTIAL)
	g.place_building(&"wind_station", Vector2i(14, 31), 0, true)
	g.place_building(&"water_station", Vector2i(18, 31), 0, true)
	g.place_building(&"school_01", Vector2i(23, 31), 0, true)
	g.place_building(&"park_square", Vector2i(26, 31), 0, true)
	gs.money = 30000
	ev.grid_reset.emit()
	await process_frame
	# Сутки с половиной игры — по тикам, как SimClock (и история копится по часам).
	var started: int = Time.get_ticks_msec()
	for i in 36 * 60:
		gs.minutes += 1
		sim._on_sim_tick()
	print("   36 h simulated in %d ms: pop %d, money %d, income %d/tick, expenses %d/tick" % [
			Time.get_ticks_msec() - started, gs.population, gs.money, gs.income, gs.expenses])
	ev.grid_reset.emit()
	await process_frame

	# Статьи сходятся с итогами.
	var budget = gs.budget
	var income_sum: float = 0.0
	for item in budget.income: income_sum += item.per_tick
	var expense_sum: float = 0.0
	for item in budget.expenses: expense_sum += item.per_tick
	check.call("totals are the game's income and expenses", budget.income_total == gs.income
			and budget.expenses_total == gs.expenses and gs.income > 0 and gs.expenses > 0)
	check.call("income items add up (%.2f / %d)" % [income_sum, gs.income], absf(income_sum - gs.income) < 0.01)
	check.call("expense items add up (%.2f / %d)" % [expense_sum, gs.expenses], absf(expense_sum - gs.expenses) < 0.01)
	var streets = budget.item(&"street")
	var avenues = budget.item(&"avenue")
	check.call("roads by type", streets.count == 26 and avenues.count == 16
			and is_equal_approx(avenues.per_tick / streets.per_tick, (16 * 0.5) / (26 * 0.2)))
	check.call("stations, school and park", budget.item(&"power").count == 1 and budget.item(&"water").count == 1
			and budget.item(&"school").count == 1 and budget.item(&"parks").count == 1)
	check.call("homes and shops pay tax", budget.item(&"res").per_tick > 0.0 and budget.item(&"res").count > 0
			and budget.item(&"com").per_tick + budget.item(&"ind").per_tick > 0.0)

	# История: 36 часов, суммы часа — 60 тиков.
	var history = gs.budget_history
	check.call("36 hours recorded (%d)" % history.size(), history.size() == 36)
	check.call("hour numbers follow", history.hours[history.size() - 1] == gs.minutes / 60 - 1
			and history.hours[1] == history.hours[0] + 1)
	check.call("money at hour end", history.money[history.size() - 1] == gs.money)
	var h = BG.History.new()
	for t in 150: h.record(60 + t + 1, 10, 3, 1000 + t)
	check.call("hour sums", h.size() == 2 and h.income[0] == 600 and h.expenses[1] == 180 and h.hour_income == 300)
	var back = BG.History.from_dict(JSON.parse_string(JSON.stringify(h.to_dict())))
	check.call("history round trip", back.size() == 2 and back.income[1] == 600 and back.money[0] == h.money[0]
			and back.hour_expenses == 90)
	check.call("bad history — empty", BG.History.from_dict({"h": [1, 2], "i": [1]}).size() == 0
			and BG.History.from_dict(null).size() == 0)
	var long_h = BG.History.new()
	for t in (BG.History.MAX_HOURS + 10) * 60: long_h.record(t + 1, 1, 1, t)
	check.call("keeps last week only", long_h.size() == BG.History.MAX_HOURS and long_h.hours[0] == 10)

	# Сохранение и загрузка — история на месте.
	var saved_size: int = history.size()
	var saved_last: int = history.income[saved_size - 1]
	check.call("save", sm.save_city("budgettest"))
	sm.new_city()
	await process_frame
	check.call("new city — empty history", gs.budget_history.size() == 0)
	check.call("load", sm.load_city("budgettest"))
	await process_frame
	check.call("history loaded", gs.budget_history.size() == saved_size
			and gs.budget_history.income[saved_size - 1] == saved_last)

	# Панель: кнопка внизу, вкладка инструментов закрывается; статьи со строками.
	hud._select_tab("zones")
	hud._budget_button.pressed.emit()
	await process_frame
	check.call("budget opens, tool panel closes", panel.visible and hud._active_tab == ""
			and hud._budget_button.button_pressed)
	var rows: Dictionary = panel.rows_text()
	print("   rows: ", rows, " | ", panel.balance_text())
	check.call("rows for city items", rows.has("Частные дома") and rows.has("Улицы") and rows.has("Проспекты")
			and rows.has("Свет") and rows.has("Школы") and not rows.has("Полиция"))
	check.call("street row in $/h", rows["Улицы"] == BC.money_text(gs.budget.item(&"street").per_hour()))
	var balance: float = (gs.income - gs.expenses) * 60.0
	check.call("balance in head", panel.balance_text() == BC.money_text(balance, true) + "/ч")
	check.call("donuts have segments", panel._income_donut.segments.size() > 0 and panel._expense_donut.segments.size() >= 5)
	check.call("chart points = 24 h window", panel.chart.points().size() == 24)
	panel.set_span(168)
	check.call("week window — all hours + now", panel.chart.points().size() == saved_size + 1)
	panel.set_span(72)
	# Налог ползунком.
	var tax_before: int = gs.tax_rate
	panel._tax_slider.value = tax_before + 3
	await process_frame
	check.call("slider sets tax", gs.tax_rate == tax_before + 3 and panel._tax_value.text == "%d%%" % gs.tax_rate)
	panel._tax_slider.value = tax_before
	await process_frame
	# Снимки: доходы и расходы с подсказкой, потом казна.
	main.get_node("BadgeVisualizer").hide()
	hud._advisor.bubble.hide()
	panel.set_mode(1)
	panel.chart.hover_at(panel.chart.points().size() - 6)
	panel._expense_donut.set_highlight(0)
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("res://tests/out/budget_flow.png")
	panel.set_mode(0)
	panel.chart.hover_at(-1)
	panel._expense_donut.set_highlight(-1)
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("res://tests/out/budget_money.png")
	var view: Vector2 = root.get_visible_rect().size
	var box: Rect2 = panel.get_global_rect()
	print("   panel %s in %s" % [box, view])
	check.call("panel fits the screen", box.position.y >= 90.0 and box.end.y <= view.y - 60.0 and box.position.x >= 0.0
			and box.end.x <= view.x)

	# Другая вкладка и Esc закрывают; щелчок по деньгам — открывает.
	hud._select_tab("roads")
	check.call("other tab closes budget", not panel.visible and not hud._budget_button.button_pressed)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud.get_node("%MoneyLabel").gui_input.emit(click)
	check.call("money click opens budget", panel.visible)
	var esc := InputEventAction.new()
	esc.action = &"tool_cancel"
	esc.pressed = true
	panel._unhandled_input(esc)
	check.call("Esc closes budget", not panel.visible)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
