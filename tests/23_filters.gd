extends SceneTree
## Вкладка «Фильтры»: V открывает и закрывает, карточка включает слой, повторный клик и другая
## вкладка — снова зоны, станции и службы сами показывают свой слой, снос слой не сбрасывает.
func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hud: CanvasLayer = main.get_node("HUD")
	var zv: MultiMeshInstance3D = main.get_node("ZoneVisualizer")
	var tool: Node = main.get_node("BuildTool")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)
	var press_v := func() -> void:
		var event := InputEventAction.new()
		event.action = &"overlay_next"
		event.pressed = true
		hud._unhandled_input(event)
	var title := func() -> String:
		var first: Node = hud._filters._legend.get_child(0)
		# У света и воды легенда начинается со шкалы (UtilityMeter, 2026-11-01) — заголовок у неё.
		if first.has_method("show_values"):
			return "Свет" if first.kind == 0 else "Вода"
		return first.text
	# Верхняя панель без плашек света, воды и пробок.
	check.call("no power/water/traffic chips", hud.find_child("PowerLabel", true, false) == null
			and hud.find_child("WaterLabel", true, false) == null and hud.find_child("TrafficLabel", true, false) == null)
	# V — открыть фильтры.
	press_v.call()
	check.call("V opens filters", hud._active_tab == "filters" and hud.get_node("%ToolPanel").visible and hud._filters.is_visible_in_tree())
	check.call("no filter yet", zv.overlay == zv.Overlay.ZONES and title.call() == "Фильтры карты")
	# Карточка «Свет».
	hud._filters._cards[zv.Overlay.POWER].pressed.emit()
	check.call("power on", zv.overlay == zv.Overlay.POWER and title.call() == "Свет" and hud._filters._cards[zv.Overlay.POWER].button_pressed)
	hud._filters._cards[zv.Overlay.POWER].pressed.emit()
	check.call("power off again", zv.overlay == zv.Overlay.ZONES and not hud._filters._cards[zv.Overlay.POWER].button_pressed)
	# Все фильтры строят легенду без ошибок.
	for filter in load("res://scripts/ui/filter_panel.gd").FILTERS:
		hud._filters._cards[filter.overlay].pressed.emit()
		check.call("legend %s" % filter.name, zv.overlay == filter.overlay and title.call() == filter.name and hud._filters._legend.get_child_count() >= 2)
	# Другая вкладка — снова зоны.
	hud._tab_buttons["roads"].pressed.emit()
	check.call("other tab -> zones", zv.overlay == zv.Overlay.ZONES and hud._active_tab == "roads")
	# Станции и службы сами показывают свой слой (как в SimCity).
	ev.building_place_requested.emit(&"power_plant_01")
	check.call("power plant -> power", zv.overlay == zv.Overlay.POWER and hud._active_tab == "utilities")
	ev.building_place_requested.emit(&"water_tower_01")
	check.call("water tower -> water", zv.overlay == zv.Overlay.WATER)
	ev.building_place_requested.emit(&"school_01")
	check.call("school -> services", zv.overlay == zv.Overlay.SERVICES and hud._active_tab == "services")
	ev.tool_requested.emit(tool.Mode.ROAD)
	check.call("road -> zones", zv.overlay == zv.Overlay.ZONES and hud._active_tab == "roads")
	# Снос не сбрасывает выбранный фильтр.
	press_v.call()
	hud._filters._cards[zv.Overlay.WATER].pressed.emit()
	ev.tool_requested.emit(tool.Mode.BULLDOZE)
	check.call("bulldoze keeps filter", zv.overlay == zv.Overlay.WATER and hud._active_tab == "filters")
	# V ещё раз — закрыть, карта снова с зонами.
	press_v.call()
	check.call("V closes filters", hud._active_tab == "" and not hud.get_node("%ToolPanel").visible and zv.overlay == zv.Overlay.ZONES)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
