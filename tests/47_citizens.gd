extends SceneTree
## Карточка жителя: имя, возраст, работа, дом, семья выводятся из дома и зерна фигурки (одни и те же —
## один человек); щелчок по пешеходу открывает карточку над ним; за выбранным следят — доехав,
## он едет обратно; карточка закрывается щелчком по карте и Esc. Снимок — tests/out/citizen_card.png.

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
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var CZ: GDScript = load("res://scripts/simulation/citizens.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	sm.with_river = false
	sm.with_highway = false
	sm.new_city()
	await process_frame

	# Улица: дома к северу, магазины и пекарни к югу — короткие пути, много пеших.
	var g: CityGrid = gs.grid
	for x in range(6, 30): g.set_road(Vector2i(x, 20))
	for x in range(8, 16):
		g.place_building(&"res_small_01", Vector2i(x, 19), 2)
	for x in range(10, 22):
		var id: int = g.place_building(&"com_corner_bakery_1x1" if x % 2 == 0 else &"com_boutique_giftshop_1x1",
				Vector2i(x, 21), 0)
		g.buildings[id].powered = true
		g.buildings[id].has_water = true
	ev.grid_reset.emit()
	await process_frame
	for b: BuildingInstance in g.buildings.values():
		b.powered = true
		b.has_water = true
	var t = TR.compute(g)
	gs.traffic = t
	print("   walkers=%.1f walk_paths=%d homes=%d job_sites=%d" % [t.walkers, t.walk_paths.size(), t.walk_homes.size(),
			t.job_sites.size()])
	check.call("paths know their homes", t.walk_paths.size() > 0 and t.walk_homes.size() == t.walk_paths.size()
			and t.sample_homes.size() == t.sample_paths.size() and t.bike_homes.size() == t.bike_paths.size())
	var homes_ok: bool = true
	for i: int in t.walk_paths.size():
		var home: BuildingInstance = g.buildings.get(t.walk_homes[i])
		if home == null or g.index_of(g.find_building_road(home)) != t.walk_paths[i][0]:
			homes_ok = false
	check.call("home of a path is next to its first cell", homes_ok)

	# Житель: одни и те же дом, путь и зерно — тот же человек; другое зерно — обычно другой.
	var path: PackedInt32Array = t.walk_paths[0]
	var home_id: int = t.walk_homes[0]
	var a = CZ.make(g, t.job_sites, home_id, path, 12345, CZ.Gender.FEMALE)
	var b = CZ.make(g, t.job_sites, home_id, path, 12345, CZ.Gender.FEMALE)
	print("   %s, %d · %s · %s · %s · %s" % [a.full_name(), a.age, a.job, a.family, a.pet, a.hobby])
	check.call("same seed — same person", a.full_name() == b.full_name() and a.age == b.age and a.family == b.family)
	var names: Dictionary = {}
	for s: int in 20:
		names[CZ.make(g, t.job_sites, home_id, path, s).full_name()] = true
	check.call("different seeds — different people (%d of 20)" % names.size(), names.size() >= 15)
	check.call("female name and surname", CZ.FEMALE_NAMES.has(a.first_name) and not a.male)
	var work: BuildingInstance = g.buildings.get(a.work_id)
	check.call("works at a shop at the end of the path", work != null
			and g.index_of(g.find_building_road(work)) == path[path.size() - 1]
			and CZ.JOBS[CityGrid.Zone.COMMERCIAL].any(func(pair: Array) -> bool: return pair[1] == a.job))
	check.call("family text", not a.family.is_empty() and a.age >= 19 and a.age <= 64)
	var big_ok: bool = true
	for s: int in 40:
		var person = CZ.make(g, t.job_sites, home_id, path, s)
		if person.family_size < 1 or person.family_size > 6 or person.family.is_empty():
			big_ok = false
		if person.family.contains("дети") and person.age < 21:
			big_ok = false
	check.call("families make sense over 40 people", big_ok)

	# Фигурки на улице; камера над ними.
	var walkers: Node = main.get_node("Walkers")
	clock.set_speed(1)
	for i in 3:
		walkers._process(0.05)
	check.call("walkers on the street (%d)" % walkers.visible_people_count(), walkers.visible_people_count() > 0)
	var cam: Node3D = main.get_node("RTSCamera")
	var first: Vector3 = walkers.agent_position(walkers._cars[0])
	cam.min_distance = 1.0
	cam.pitch_degrees = 56.0
	# Фигурка — пониже центра экрана, чтобы карточка над ней поместилась.
	cam.position = Vector3(first.x, 0.0, first.z - 1.6)
	cam._target_distance = 8.0
	cam._distance = 8.0
	cam._apply_distance()
	main.get_node("BadgeVisualizer").hide()
	main.get_node("HUD")._advisor.bubble.hide()
	clock.set_speed(0)
	for i in 5: await process_frame
	var tool: Node = main.get_node("BuildTool")
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	check.call("no one at an empty spot", not tool.pick_citizen(Vector2(4, 4)))
	var car = walkers._cars[0]
	var screen: Vector2 = camera.unproject_position(walkers.agent_position(car) + Vector3.UP * 0.18)
	check.call("click on a walker picks him", tool.pick_citizen(screen + Vector2(3, -2)))
	await process_frame
	await process_frame
	var card: Node = main.get_node("HUD")._citizen_card
	var rows: Dictionary = card.rows()
	print("   card: %s | %s | %s" % [card.title_text(), card.subtitle_text(), rows])
	check.call("card open for that walker", card.is_open() and card.visible and car.followed)
	check.call("card title — name and age", card.title_text() == "%s, %s" % [card.citizen.full_name(),
			card.age_text(card.citizen.age)])
	var work_b: BuildingInstance = g.buildings.get(card.citizen.work_id)
	check.call("card rows", rows.has("Живёт") and rows.has("Семья") and rows.has("Увлечение") and rows.has("Настроение")
			and work_b != null and rows.get("Работает") == BuildingCatalog.get_type(work_b.type_id).display_name
			and String(rows.get("Дорога", "")).ends_with("пешком"))
	check.call("subtitle says what he does", card.subtitle_text().contains(card.citizen.job)
			and card.subtitle_text().contains("идёт"))
	var gender_ok: bool = card.citizen.male == walkers.WALKER_MODELS[car.model].ends_with("_m.glb")
	check.call("gender follows the model", gender_ok)
	var bottom: float = card.position.y + card.size.y
	var head: Vector2 = camera.unproject_position(walkers.agent_position(car) + Vector3.UP * card.ANCHOR_HEIGHT)
	check.call("card hangs above the walker (bottom %.0f, head %.0f)" % [bottom, head.y],
			bottom <= head.y + 1.0 and bottom >= head.y - card.TAIL - 30.0
			and absf(card.position.x + card.size.x * 0.5 - head.x) < card.size.x * 0.5)
	check.call("ring under him", card._ring.is_inside_tree()
			and card._ring.global_position.distance_to(walkers.agent_position(car)) < 0.1)
	root.get_texture().get_image().save_png("res://tests/out/citizen_card.png")

	# Доехав, выбранный разворачивается — тот же человек едет обратно.
	var seed_before: int = car.citizen_seed
	var forward_before: bool = car.forward
	clock.set_speed(1)
	car.distance = car.route.length() - 0.001
	walkers._process(0.05)
	check.call("followed walker turns around", walkers.has_agent(car) and car.citizen_seed == seed_before
			and car.forward != forward_before and card.is_open())
	await process_frame
	check.call("subtitle flips direction", card.subtitle_text().contains("домой" if forward_before else "на работу"))
	# Фигурок стало меньше — выбранного не убирают.
	walkers._cars.erase(car)
	walkers._cars.append(car)
	var walkers_before: float = t.walkers
	t.walkers = walkers.WORKERS_PER_PERSON * 1.0
	walkers._sync_car_count()
	check.call("followed one stays when crowd shrinks (%d left)" % walkers._cars.size(),
			walkers._cars.size() == 1 and walkers.has_agent(car))
	t.walkers = walkers_before
	clock.set_speed(0)

	# Закрытие: щелчок по карте (cell_inspected), Esc; агент пропал — закрывается сама.
	ev.cell_inspected.emit(Vector2i(10, 19))
	await process_frame
	check.call("map click closes card", not card.is_open() and not card.visible and not car.followed
			and not card._ring.is_inside_tree())
	ev.citizen_selected.emit(walkers, car)
	await process_frame
	var esc := InputEventAction.new()
	esc.action = &"tool_cancel"
	esc.pressed = true
	card._unhandled_input(esc)
	check.call("Esc closes card", not card.is_open())
	ev.citizen_selected.emit(walkers, car)
	walkers._cars.erase(car)
	await process_frame
	check.call("agent gone — card closes", not card.is_open())

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
