extends SceneTree
## Файлы сохранений и окно сохранения: имена, список, автосохранение, Esc.

func _initialize() -> void:
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var clock: Node = root.get_node("SimClock")
	var sm: Node = root.get_node("SaveManager")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	clock.set_speed(0)
	# Без слэша на конце — list_saves должен работать.
	sm.save_dir = "user://test_saves_008"
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
	var zv: MultiMeshInstance3D = main.get_node("ZoneVisualizer")
	var cam: Node3D = main.get_node("RTSCamera")
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)

	# --- 2. Имена файлов ---
	check.call("Autosave", sm.file_id_for("Autosave") == "_Autosave" and sm.file_id_for("QUICKSAVE") == "_QUICKSAVE")
	var long_name: String = "а".repeat(59) + " конец"
	check.call("no trailing space", not sm.file_id_for(long_name).ends_with(" "))
	check.call("path stays in dir", sm._path("../../evil").get_base_dir() == sm.save_dir)

	# Город и сохранения.
	var g: CityGrid = gs.grid
	for x in range(5, 30): g.set_road(Vector2i(x, 20))
	g.place_building(&"power_plant_01", Vector2i(4, 19), 1, true)
	var touched: Array[Vector2i] = [Vector2i(4, 19)]
	ev.cells_changed.emit(touched)
	check.call("save", sm.save_city("Город"))
	gs.minutes += 40 * 1440
	ev.sim_tick.emit()
	var saves: Array = sm.list_saves()
	var auto: Array = saves.filter(func(s): return s.file == "autosave")
	check.call("list without slash", saves.size() == 2 and saves.all(func(s): return not s.broken))
	check.call("autosave city_name", auto.size() == 1 and auto[0].city_name == "Город" and auto[0].name.begins_with("Автосохранение"))

	# --- 1. Окно: Esc с первого раза при фокусе в поле, камера стоит за окном ---
	var dialog: Control = hud._save_dialog
	dialog.open()
	await process_frame
	check.call("focus in edit", root.gui_get_focus_owner() == dialog._name_edit)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	check.call("esc closes first time", not dialog.visible)
	dialog.open()
	dialog._name_edit.release_focus()
	var pos: Vector3 = cam.position
	Input.action_press(&"cam_forward")
	cam._process(0.2)
	check.call("camera still behind dialog", cam.position == pos)
	dialog.close()
	cam._process(0.2)
	check.call("camera moves after close", cam.position != pos)
	Input.action_release(&"cam_forward")
	# Выбор автосохранения подставляет чистое имя.
	dialog.open()
	var auto_index: int = dialog._saves.find(dialog._saves.filter(func(s): return s.file == "autosave")[0])
	dialog._on_item_selected(auto_index)
	check.call("autosave name in field", dialog._name_edit.text == "Город")
	dialog.close()

	# --- 6. Подтверждение «Новый город» ставит паузу ---
	clock.set_speed(3)
	hud.request_new_city()
	check.call("confirm pauses", clock.speed == 0 and cam._modal_open)
	hud._new_city_confirm.hide()
	check.call("confirm restores", clock.speed == 3 and not cam._modal_open)
	clock.set_speed(0)

	# --- 3, 5, 6. Загрузка карты 32×32 со слоем «Свет» ---
	var small := CityGrid.new(32)
	for x in range(2, 20): small.set_road(Vector2i(x, 10))
	small.place_building(&"water_tower_01", Vector2i(5, 11), 0, false)
	small.zone[small.index_of(Vector2i(5, 11))] = CityGrid.Zone.RESIDENTIAL
	var data: Dictionary = CS.to_dict(small, "Маленький", 900, 9, 5, 0)
	# Зона под дорогой в файле.
	var zones := Marshalls.base64_to_raw(data["grid"]["zones"])
	zones[small.index_of(Vector2i(3, 10))] = CityGrid.Zone.COMMERCIAL
	data["grid"]["zones"] = Marshalls.raw_to_base64(zones)
	var f := FileAccess.open(sm.save_dir.path_join("small.city.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	zv.set_overlay(zv.Overlay.POWER)
	cam.position = Vector3(120, 0, 120)
	check.call("load small", sm.load_city("small"))
	g = gs.grid
	check.call("multimesh resized", zv.multimesh.instance_count == 32 * 32)
	check.call("camera clamped", cam.position.x <= 64.0 and cam.position.z <= 64.0)
	check.call("zone under service cleared", g.zone[g.index_of(Vector2i(5, 11))] == CityGrid.Zone.NONE)
	check.call("zone under road cleared", g.zone[g.index_of(Vector2i(3, 10))] == CityGrid.Zone.NONE)
	var direct := CityGrid.new(16)
	direct.tile_type[5] = CityGrid.Tile.ROAD
	direct.zone[5] = CityGrid.Zone.INDUSTRIAL
	direct.rebuild_caches()
	check.call("rebuild clears road zone", direct.zone[5] == CityGrid.Zone.NONE)

	cleanup.call()
	DirAccess.remove_absolute(sm.save_dir)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
