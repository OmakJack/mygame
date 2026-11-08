extends SceneTree
## Советник вместо плашки подсказок: кнопка со счётчиком в верхней панели, список по срочности,
## «Показать» — камера к месту (по кругу), слой карты, вкладка, карточка дома; строчка о новой записи.
const OUT := "res://tests/out/"

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var HN: GDScript = load("res://scripts/ui/hints.gd")
	var ZV: GDScript = load("res://scripts/grid/zone_visualizer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	var g: CityGrid = gs.grid
	var tool: Node = main.get_node("BuildTool")
	var hud: CanvasLayer = main.get_node("HUD")
	var cam: Node3D = main.get_node("RTSCamera")
	var adv = hud._advisor
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var find := func(id: String):
		for entry in adv.entries:
			if entry.id == id: return entry
		return null
	var frames := func(n: int) -> void:
		for i in n: await process_frame

	# --- Плашки больше нет, кнопка — в верхней панели; пустой город — «Шаг 1» и строчка ---
	check.call("old hints banner removed", hud.get_node_or_null("%HintsPanel") == null)
	check.call("button sits in the top bar", adv.button.get_parent() == hud.get_node("%Speed").get_parent())
	check.call("empty city: one step entry", adv.entries.size() == 1 and adv.entries[0].level == HN.Level.STEP
			and adv.texts()[0].contains("Шаг 1"))
	check.call("badge counts 1", adv._badge.visible and adv._badge_label.text == "1")
	check.call("new step pops a line under the button", adv.bubble.visible and adv._bubble_label.text.contains("Шаг 1"))
	check.call("list closed until clicked", not adv.visible)
	await frames.call(5)
	var under: bool = adv.bubble.global_position.y >= hud.get_node("Root/Margin/Layout/TopBar").get_global_rect().end.y
	check.call("line is under the top bar, at the button", under
			and absf(adv.bubble.global_position.x - adv.button.global_position.x) < 2.0)
	adv.button.button_pressed = true
	await frames.call(4)
	check.call("button opens the list, line hides", adv.visible and not adv.bubble.visible and adv._rows.get_child_count() == 1)
	adv.show_entry("step_road")
	check.call("step: roads tab opens", hud._active_tab == "roads")
	adv.button.button_pressed = false
	check.call("button closes the list", not adv.visible)

	# --- Дорога и зоны без станций: тревоги первыми, у записей места, слой, вкладка ---
	drag.call(tool.Mode.ROAD, Vector2i(5, 20), Vector2i(40, 20))
	drag.call(tool.Mode.ZONE_R, Vector2i(5, 17), Vector2i(39, 19))
	drag.call(tool.Mode.ZONE_I, Vector2i(5, 21), Vector2i(39, 23))
	tool._set_mode(tool.Mode.NONE)
	for i in 15: ev.sim_tick.emit()
	var sorted: bool = true
	for i in range(1, adv.entries.size()):
		if adv.entries[i].level < adv.entries[i - 1].level: sorted = false
	check.call("most urgent first %s" % [adv.entries.map(func(e) -> String: return e.id)], sorted
			and adv.entries[0].level == HN.Level.ALERT)
	check.call("badge: count and colour of the most urgent", adv._badge_label.text == str(adv.entries.size())
			and adv._badge_style.bg_color == adv.LEVEL_COLORS[HN.Level.ALERT])
	var power = find.call("power")
	check.call("no power: places of dark buildings, power layer", power != null and power.cells.size() > 1
			and power.overlay == ZV.Overlay.POWER
			and power.cells.all(func(c: Vector2i) -> bool: return not g.get_building_at(c).powered))
	adv.open_list()
	await frames.call(4)
	check.call("one row per entry", adv._rows.get_child_count() == adv.entries.size() and adv._actions.has("power"))
	var first: int = adv.show_entry("power")
	var second: int = adv.show_entry("power")
	check.call("«Показать» goes round the places", first == 0 and second == 1
			and adv._actions["power"].text == "Показать 2/%d" % power.cells.size())
	check.call("power layer on the map", hud._overlay == ZV.Overlay.POWER and hud._active_tab == hud.FILTER_TAB)
	var flight: int = 0
	while cam._focusing and flight < 3000:
		await process_frame
		flight += 1
	var target: Vector3 = g.grid_to_world(power.cells[1])
	check.call("camera flew to the place", Vector2(cam.position.x, cam.position.z).distance_to(Vector2(target.x, target.z)) < 0.3
			and cam._target_distance <= cam.focus_distance)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "advisor_open.png"))
	adv.show_entry("stations")
	check.call("no stations: utilities tab opens", find.call("stations") != null and hud._active_tab == "utilities")

	# --- Заброшенный дом: «Показать» открывает и карточку дома ---
	var home: BuildingInstance = g.get_building_at(power.cells[0])
	home.abandoned = true
	ev.stats_changed.emit()
	var abandoned = find.call("abandoned")
	adv.show_entry("abandoned")
	check.call("abandoned: card of the building opens", abandoned != null and abandoned.inspect
			and hud._info.visible and g.get_building_at(hud._info.cell) == home)

	# --- Новая тревога при закрытом списке: строчка и вспышка; вернулась быстро — без строчки ---
	adv.close_list()
	adv._hide_bubble()
	adv._announced_at.clear() # казна могла уйти в минус, пока строили дороги
	gs.money = -100
	ev.stats_changed.emit()
	check.call("new alert pops a line", adv.bubble.visible and adv._bubble_label.text.contains("Казна в минусе")
			and adv._flash != null and adv._flash.is_valid())
	await frames.call(20)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "advisor_bubble.png"))
	adv._hide_bubble()
	gs.money = 5000
	ev.stats_changed.emit()
	gs.money = -100
	ev.stats_changed.emit()
	check.call("same alert back soon — no line again", not adv.bubble.visible and find.call("money") != null)
	gs.money = 5000
	ev.stats_changed.emit()

	# --- Подписи ---
	check.call("plural forms", adv._records(1) == "1 запись" and adv._records(3) == "3 записи"
			and adv._records(5) == "5 записей" and adv._records(12) == "12 записей" and adv._records(22) == "22 записи")
	check.call("icon drawn", adv.make_icon(20).get_width() == 20)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
