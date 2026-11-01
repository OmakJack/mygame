extends SceneTree
## Детерминизм: зерно случайности симуляции (GameState.rng) — в сохранении. Одно зерно и те же действия
## дают тот же город; загрузка продолжает ту же последовательность; старое сохранение без зерна грузится.

func _initialize() -> void:
	var sm: Node = root.get_node("SaveManager")
	sm.save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	sm.with_river = false
	sm.with_highway = false
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
	var tool: Node = main.get_node("BuildTool")
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	# Новый город с дорогой, зонами, ТЭЦ и водокачкой; зерно задаём сами.
	var build := func(rng_seed: int) -> void:
		sm.new_city()
		gs.money = 100000
		drag.call(tool.Mode.ROAD, Vector2i(10, 30), Vector2i(50, 30))
		drag.call(tool.Mode.ROAD, Vector2i(30, 20), Vector2i(30, 40))
		drag.call(tool.Mode.ZONE_R, Vector2i(12, 26), Vector2i(28, 29))
		drag.call(tool.Mode.ZONE_C, Vector2i(32, 26), Vector2i(40, 29))
		drag.call(tool.Mode.ZONE_I, Vector2i(12, 31), Vector2i(28, 34))
		gs.grid.place_building(&"power_plant_01", Vector2i(42, 31), 0, true)
		gs.grid.place_building(&"water_tower_01", Vector2i(43, 31), 0, true)
		ev.grid_reset.emit()
		gs.rng.seed = rng_seed
	var run := func(ticks: int) -> void:
		for i in ticks:
			ev.sim_tick.emit()
	# Снимок города: здания со всеми счётчиками и деньги.
	var snapshot := func() -> String:
		var data: Dictionary = CS.to_dict(gs.grid, "", gs.money, gs.tax_rate, 0, 0)
		return JSON.stringify([data.buildings, data.grid.lots, gs.money])

	build.call(777)
	run.call(240)
	var first: String = snapshot.call()
	var grown: int = gs.grid.buildings.size()
	build.call(777)
	run.call(240)
	check.call("same seed — same city (%d buildings)" % grown, grown > 10 and snapshot.call() == first)
	build.call(778)
	run.call(240)
	check.call("other seed — other city", snapshot.call() != first)

	# Сохранение хранит зерно и положение: после загрузки — те же случайные числа.
	build.call(42)
	run.call(120)
	check.call("save", sm.save_city("Зерно"))
	var saved_seed: int = gs.rng.seed
	var saved_state: int = gs.rng.state
	var next_numbers: Array[float] = [gs.rng.randf(), gs.rng.randf()]
	gs.rng.randomize()
	check.call("load", sm.load_city(sm.file_id_for("Зерно")))
	check.call("rng restored", gs.rng.seed == saved_seed and gs.rng.state == saved_state
			and [gs.rng.randf(), gs.rng.randf()] == next_numbers)

	# Город после загрузки растёт так же, как без неё (стройплощадки тоже сохраняются).
	build.call(5)
	run.call(150)
	check.call("save mid-game", sm.save_city("Продолжение"))
	run.call(150)
	var continued: String = snapshot.call()
	sm.load_city(sm.file_id_for("Продолжение"))
	run.call(150)
	check.call("load continues the same city", snapshot.call() == continued)

	# Старое сохранение без поля rng грузится со случайным зерном.
	var old: Dictionary = CS.to_dict(gs.grid, "Старый", 500, 9, 600, 0, 0, gs.rng)
	old.state.erase("rng")
	var result = CS.from_dict(JSON.parse_string(JSON.stringify(old)))
	check.call("old save without rng", result.ok and result.rng_state.is_empty())
	var fresh = CS.from_dict(JSON.parse_string(JSON.stringify(
			CS.to_dict(gs.grid, "Новый", 500, 9, 600, 0, 0, gs.rng))))
	check.call("rng survives json", fresh.rng_state == [gs.rng.seed, gs.rng.state])

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
