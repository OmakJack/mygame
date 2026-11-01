extends SceneTree
## Сохранения: сериализатор туда и обратно, повреждения, имена файлов.
const SHOT := "res://tests/out/phase7.png"

func _initialize() -> void:
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var clock: Node = root.get_node("SimClock")
	var sm: Node = root.get_node("SaveManager")
	clock.set_speed(0)
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	sm.save_dir = "user://test_saves/"
	var cleanup := func() -> void:
		var d := DirAccess.open(sm.save_dir)
		if d:
			for f in d.get_files(): d.remove(f)
	cleanup.call()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var tool: Node = main.get_node("BuildTool")
	var hud: CanvasLayer = main.get_node("HUD")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	# Пустой город не автосохраняется.
	gs.minutes = 30 * 1440
	ev.sim_tick.emit()
	check.call("no autosave of empty city", not FileAccess.file_exists(sm.save_dir + "autosave.city.json"))
	# Город.
	var g: CityGrid = gs.grid
	drag.call(tool.Mode.ROAD, Vector2i(5,20), Vector2i(40,20))
	drag.call(tool.Mode.ZONE_R, Vector2i(5,17), Vector2i(39,19))
	drag.call(tool.Mode.ZONE_I, Vector2i(5,21), Vector2i(39,23))
	g.place_building(&"power_plant_01", Vector2i(4,19), 1, true)
	g.place_building(&"water_tower_01", Vector2i(4,21), 1, true)
	var touched: Array[Vector2i] = [Vector2i(4,19)]
	ev.cells_changed.emit(touched)
	for i in 40: ev.sim_tick.emit()
	var some: BuildingInstance = g.buildings.values()[5]
	some.no_road_ticks = 2
	some.no_power_ticks = 7
	gs.tax_rate = 12
	gs.money = 1234
	gs.minutes = 77 * 1440 + 15 * 60 + 25
	# --- Сериализатор: туда и обратно через текст JSON ---
	var data: Dictionary = CS.to_dict(g, "Тест", gs.money, gs.tax_rate, gs.minutes, gs.population)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var r = CS.from_dict(parsed)
	check.call("roundtrip ok " + r.error, r.ok and r.warnings.is_empty())
	if r.ok:
		var g2: CityGrid = r.grid
		check.call("roads", g2.road_cells.size() == g.road_cells.size())
		check.call("zones", g2.zone == g.zone)
		check.call("tiles", g2.tile_type == g.tile_type and g2.building_at == g.building_at)
		var same: bool = g2.buildings.size() == g.buildings.size()
		for id in g.buildings:
			var a: BuildingInstance = g.buildings[id]
			var b: BuildingInstance = g2.buildings.get(id)
			if b == null or b.type_id != a.type_id or b.cell != a.cell or b.orientation != a.orientation or b.no_road_ticks != a.no_road_ticks or b.no_power_ticks != a.no_power_ticks or b.no_water_ticks != a.no_water_ticks:
				same = false
		check.call("buildings", same)
		check.call("ids ascending", g2.buildings.keys() == g.buildings.keys())
		check.call("zoned cache", g2.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].size() == g.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].size())
		check.call("state", r.money == 1234 and r.tax_rate == 12 and r.minutes == 77 * 1440 + 15 * 60 + 25 and r.name == "Тест")
		# Старое сохранение: в state день вместо часов — тот же день, утро.
		var old: Dictionary = JSON.parse_string(JSON.stringify(data))
		old.state.erase("minutes")
		old.state["day"] = 77
		var r_old = CS.from_dict(old)
		check.call("old save days -> minutes", r_old.ok and r_old.minutes == 77 * 1440 + GameTime.START_MINUTES)
		old.state["hours"] = 100
		r_old = CS.from_dict(old)
		check.call("old save hours -> minutes", r_old.ok and r_old.minutes == 6000)
		check.call("int types", typeof(g2.buildings.keys()[0]) == TYPE_INT and typeof(g2.next_building_id) == TYPE_INT)
	# Повреждения.
	check.call("not json", not CS.from_dict(null).ok)
	var bad: Dictionary = parsed.duplicate(true)
	bad["format"] = "other"
	check.call("format", not CS.from_dict(bad).ok)
	bad = parsed.duplicate(true)
	bad["version"] = 99
	check.call("newer version", CS.from_dict(bad).error.contains("новой версии"))
	bad = parsed.duplicate(true)
	bad["grid"]["size"] = 7
	check.call("size", not CS.from_dict(bad).ok)
	bad = parsed.duplicate(true)
	var z := Marshalls.base64_to_raw(bad["grid"]["zones"])
	z[100] = 9
	bad["grid"]["zones"] = Marshalls.raw_to_base64(z)
	check.call("zone byte", not CS.from_dict(bad).ok)
	bad = parsed.duplicate(true)
	bad["grid"]["next_building_id"] = 0
	bad["buildings"].append({"id": 9000, "type": "castle_99", "x": 1, "y": 1, "o": 0})
	bad["buildings"].append({"id": 9001, "type": "res_small_01", "x": 10, "y": 20, "o": 0})
	bad["buildings"].append({"id": 9002, "type": "res_small_01", "x": some.cell.x, "y": some.cell.y, "o": 0})
	bad["buildings"].append("мусор")
	var rb = CS.from_dict(bad)
	check.call("skips with warnings %d" % rb.warnings.size(), rb.ok and rb.warnings.size() == 4 and rb.grid.buildings.size() == g.buildings.size())
	check.call("next id fixed", rb.ok and rb.grid.next_building_id > rb.grid.buildings.keys().max())
	# --- Имена файлов ---
	check.call("file ids", sm.file_id_for("CON") == "_CON" and sm.file_id_for("autosave") == "_autosave" and sm.file_id_for("a/b:c?") == "a_b_c_" and sm.file_id_for("  ") == "city" and sm.file_id_for("Мой город-1") == "Мой город-1")
	# --- SaveManager: сохранить, испортить город, загрузить ---
	var pop_before: int = gs.population
	var unpowered_before: int = gs.utilities.unpowered_count
	var n_before: int = g.buildings.size()
	check.call("save", sm.save_city("Мой город: тест?"))
	check.call("save twice (overwrite)", sm.save_city("Мой город: тест?"))
	var saves: Array = sm.list_saves().filter(func(s): return s.file != "autosave")
	check.call("list", saves.size() == 1 and saves[0].name == "Мой город: тест?" and saves[0].day == 78 and saves[0].file == "Мой город_ тест_")
	check.call("autosave once during ticks", FileAccess.file_exists(sm.save_dir + "autosave.city.json"))
	check.call("no tmp left", not FileAccess.file_exists(sm.save_dir + "Мой город_ тест_.city.json.tmp"))
	drag.call(tool.Mode.BULLDOZE, Vector2i(5,17), Vector2i(40,23))
	gs.money = 1
	var reset_count := [0]
	ev.grid_reset.connect(func(): reset_count[0] += 1)
	check.call("load", sm.load_city(saves[0].file))
	g = gs.grid
	#print("AFTER LOAD n=", g.buildings.size(), " before=", n_before, " money=", gs.money, " day=", gs.day, " tax=", gs.tax_rate, " resets=", reset_count[0], " label=", hud.get_node("%DayLabel").text, " vis=", main.get_node("BuildingVisualizer").get_used_cells().size())
	check.call("restored", g.buildings.size() == n_before and gs.money == 1234 and gs.minutes == 77 * 1440 + 15 * 60 + 25 and gs.tax_rate == 12 and reset_count[0] == 1)
	check.call("stats recomputed", gs.population == pop_before and gs.utilities.unpowered_count == unpowered_before and gs.utilities.power_supply == 100)
	check.call("hud name", hud.get_node("%DayLabel").text.begins_with("Мой город: тест?"))
	# Многоклеточные здания (Argon): видимых клеток — сумма площадей участков.
	var cells_now := 0
	for b in g.buildings.values(): cells_now += b.size.x * b.size.y
	check.call("visual rebuilt", main.get_node("BuildingVisualizer").get_used_cells().size() == cells_now)
	# Битый файл не трогает город.
	var f := FileAccess.open(sm.save_dir + "broken.city.json", FileAccess.WRITE)
	f.store_string("{ это не json")
	f.close()
	var errors := [""]
	ev.save_error.connect(func(m): errors[0] = m)
	check.call("broken refused", not sm.load_city("broken") and g == gs.grid and g.buildings.size() == n_before and errors[0].begins_with("Не удалось загрузить"))
	# Автосохранение: после загрузки (день 77) — не сразу, а через 30 дней.
	DirAccess.remove_absolute(sm.save_dir + "autosave.city.json")
	gs.minutes = 77 * 1440 + 15 * 60 + 25 + 100
	ev.sim_tick.emit()
	check.call("no autosave right after load", not FileAccess.file_exists(sm.save_dir + "autosave.city.json"))
	gs.minutes = 77 * 1440 + 15 * 60 + 25 + 120
	ev.sim_tick.emit()
	check.call("autosave after 2 game hours", FileAccess.file_exists(sm.save_dir + "autosave.city.json"))
	# Новый город.
	sm.new_city()
	check.call("new city", gs.grid.buildings.is_empty() and gs.grid.road_cells.size() == gs.grid.highway_cells.size() and gs.money == 2000 and gs.minutes == GameTime.START_MINUTES and gs.day == 1 and gs.city_name == "Новый город" and gs.population == 0)
	check.call("load after new", sm.load_city("Мой город_ тест_") and gs.grid.buildings.size() == n_before)
	# --- Окно сохранений ---
	clock.set_speed(3)
	var dialog: Control = hud._save_dialog
	dialog.open()
	check.call("dialog pauses", clock.speed == 0 and dialog.visible and tool.mode == tool.Mode.NONE)
	check.call("dialog list %d" % dialog._list.item_count, dialog._list.item_count == 3)
	# Камера не едет, пока печатаем.
	var cam: Node3D = main.get_node("RTSCamera")
	var cam_pos: Vector3 = cam.position
	Input.action_press(&"cam_forward")
	cam._process(0.2)
	check.call("camera ignores typing", cam.position == cam_pos)
	dialog._name_edit.release_focus()
	cam._process(0.2)
	check.call("camera still while dialog open", cam.position == cam_pos)
	Input.action_release(&"cam_forward")
	dialog._name_edit.grab_focus()
	dialog._name_edit.text = "Из окна"
	dialog._save()
	check.call("dialog save", dialog._list.item_count == 4 and hud.get_node("%DayLabel").text.begins_with("Из окна"))
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(SHOT)
	dialog.close()
	check.call("dialog restores speed", clock.speed == 3 and not dialog.visible)
	clock.set_speed(0)
	cleanup.call()
	DirAccess.remove_absolute(sm.save_dir)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
