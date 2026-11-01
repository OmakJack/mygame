extends SceneTree
## Шкалы света и воды, как в Cities: Skylines: кВт и м³/сут, заливка — потребление, бегунок — мощность;
## во вкладке «Свет и вода» и в легенде фильтров; кВт и м³ в карточке «Инфо» и подсказке станции.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
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
	var hud: Node = main.get_node("HUD")
	var g: CityGrid = gs.grid
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var UM: GDScript = load("res://scripts/ui/utility_meter.gd")
	const POWER := 0
	const WATER := 1
	const OVERLAY_POWER := 1

	# Единицы.
	check.call("digits", Utilities.digits(7) == "7" and Utilities.digits(1000) == "1\u00a0000"
			and Utilities.digits(1234567) == "1\u00a0234\u00a0567" and Utilities.digits(-2500) == "-2\u00a0500")
	check.call("units", Utilities.power_text(100) == "1\u00a0000 кВт" and Utilities.power_text(1) == "10 кВт"
			and Utilities.water_text(131) == "131 м³/сут")

	# Шкала: состояния.
	var meter = UM.new(POWER)
	root.add_child(meter)
	meter.show_values(0, 0, 0)
	check.call("no stations yet", meter._footer.text == "Станций пока нет" and meter._bar.use_share == 0.0)
	meter.show_values(30, 0, 5)
	check.call("no stations, need one", meter._footer.text.begins_with("Нет станций — нужна ТЭЦ")
			and meter._bar.color == UiTheme.BAD and meter._bar.supply_share == 0.0)
	meter.show_values(150, 100, 20)
	print("short: ", meter._value.text, " | ", meter._footer.text)
	check.call("shortage", meter._value.text == "1\u00a0500 / 1\u00a0000 кВт" and meter._footer.text.begins_with("Не хватает 500 кВт")
			and meter._footer.text.ends_with("без света 20 зд.") and meter._bar.color == UiTheme.BAD
			and meter._bar.use_share > meter._bar.supply_share)
	meter.show_values(90, 100, 0)
	check.call("near full", meter._bar.color == UM.WARN and meter._footer.text.contains("пора ставить"))
	meter.show_values(40, 100, 0)
	check.call("plenty", meter._bar.color == UiTheme.GOOD and meter._footer.text == "Запас 600 кВт"
			and is_equal_approx(meter._bar.supply_share, 1.0 / UM.Bar.HEADROOM)
			and is_equal_approx(meter._bar.use_share, 0.4 / UM.Bar.HEADROOM))
	var water = UM.new(WATER)
	root.add_child(water)
	water.show_values(120, 100, 3)
	check.call("water meter", water._value.text == "120 / 100 м³/сут" and water._footer.text.contains("водокачка")
			and water._footer.text.ends_with("без воды 3 зд."))

	# Город: ТЭЦ, водокачка, дома.
	for x in range(10, 30): g.set_road(Vector2i(x, 20))
	g.place_building(&"power_plant_01", Vector2i(10, 19), 2, true)
	g.place_building(&"water_tower_01", Vector2i(11, 19), 2, true)
	for x in range(14, 20):
		g.place_building(&"res_small_01", Vector2i(x, 19), 2)
	ev.grid_reset.emit()
	await process_frame
	var u: Utilities = gs.utilities
	print("city power %d/%d water %d/%d" % [u.power_use, u.power_supply, u.water_use, u.water_supply])

	# Вкладка «Свет и вода»: две шкалы с цифрами города.
	hud._select_tab("utilities")
	await process_frame
	check.call("utilities tab meters", hud._utility_meters.size() == 2 and hud._utility_meters[0].is_visible_in_tree()
			and hud._utility_meters[0]._value.text == "%s / %s" % [Utilities.digits(u.power_use * 10), Utilities.power_text(u.power_supply)]
			and hud._utility_meters[1]._value.text.ends_with("м³/сут"))
	# Новый дом — шкала обновляется со статистикой.
	var before: String = hud._utility_meters[0]._value.text
	g.place_building(&"res_small_01", Vector2i(21, 19), 2)
	ev.grid_reset.emit()
	await process_frame
	check.call("meter follows stats", hud._utility_meters[0]._value.text != before)

	# Фильтры: карточка с загрузкой, в легенде — шкала.
	hud._select_tab("filters")
	ev.overlay_requested.emit(OVERLAY_POWER)
	await process_frame
	var filters: Node = hud._filters
	check.call("power card load", filters._cards[OVERLAY_POWER].text
			== "Свет\nзагрузка %d%%" % roundi(100.0 * gs.utilities.power_use / gs.utilities.power_supply))
	var legend_meters: Array = filters._legend.get_children().filter(func(n: Node) -> bool: return n.get_script() == UM)
	check.call("legend meter", legend_meters.size() == 1 and legend_meters[0].kind == POWER)

	# Карточка «Инфо» и подсказка станции — в кВт и м³.
	ev.cell_inspected.emit(Vector2i(14, 19))
	await process_frame
	var text := ""
	for label in hud.find_children("*", "Label", true, false):
		text += label.text + "|"
	check.call("info card units", text.contains("10 кВт, есть") and text.contains("1 м³/сут, есть"))
	check.call("plant tooltip", hud._service_buttons[&"power_plant_01"].tooltip_text.contains("Даёт свет: 1\u00a0000 кВт"))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
