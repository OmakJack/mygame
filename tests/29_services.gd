extends SceneTree
## Службы Argon: полиция, пожарные и поликлиника 1×1 — новые модели под старыми id (сохранения целы),
## большие 2×1 — дороже, радиус больше; ставятся инструментом у дороги и покрывают больше домов.

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
	var tool: Node = main.get_node("BuildTool")
	var cursor: Node = main.get_node("CellCursor")
	var g: CityGrid = gs.grid

	# Типы: 1×1 — модели Argon без вывески, 2×1 — крупнее во всём.
	for pair in [[&"health_01", &"health_02"], [&"fire_01", &"fire_02"], [&"police_01", &"police_02"]]:
		var small: BuildingData = BuildingCatalog.get_type(pair[0])
		var big: BuildingData = BuildingCatalog.get_type(pair[1])
		check.call("%s: Argon model, no sign" % pair[0], small.model.resource_path.contains("blender/services/")
				and small.sign_color.a == 0.0 and small.size == Vector2i.ONE)
		check.call("%s: 2x1, same service, wider and dearer" % pair[1], big != null and big.size == Vector2i(2, 1)
				and big.service == small.service and big.service_radius > small.service_radius
				and big.cost > small.cost and big.upkeep > small.upkeep and big.zone == CityGrid.Zone.NONE
				and big.model.resource_path.contains("blender/services/") and big.sign_color.a == 0.0)
		check.call("%s icon" % pair[1], ResourceLoader.exists("res://assets/ui/icons/%s.png" % pair[1]))
	var order: Array = []
	for data: BuildingData in hud._tab_buildings("services"):
		order.append(String(data.id))
	print("services tab: ", order)
	check.call("services tab order", order == ["school_01", "health_01", "health_02", "fire_01", "fire_02",
			"police_01", "police_02"])
	# Меш 2×1 вписан в участок 2×1.
	var box: AABB = BuildingMeshes.mesh_for(BuildingCatalog.get_type(&"fire_02")).get_aabb()
	print("fire_02 mesh ", box)
	check.call("2x1 mesh fits its lot", box.size.x > 3.0 and box.size.x <= 3.81 and box.size.z <= 1.81)

	# Ставим инструментом: управление полиции 2×1 у дороги.
	for x in range(5, 60): g.set_road(Vector2i(x, 30))
	g.place_building(&"power_plant_01", Vector2i(5, 29), 2, true)
	g.place_building(&"water_tower_01", Vector2i(6, 29), 2, true)
	gs.money = 5000
	var money: int = gs.money
	ev.building_place_requested.emit(&"police_02")
	cursor.has_cell = true
	tool._dragging = true; tool._drag_start = Vector2i(30, 29)
	tool._update_drag(Vector2i(30, 29)); tool._apply(); tool._end_drag()
	var placed: BuildingInstance = g.get_building_at(Vector2i(30, 29))
	check.call("2x1 placed by tool", placed != null and placed.type_id == &"police_02" and placed.size == Vector2i(2, 1)
			and g.get_building_at(Vector2i(31, 29)) == placed and gs.money == money - 450)
	ev.grid_reset.emit()
	await process_frame
	check.call("2x1 service works", Services.is_active(g, placed, BuildingCatalog.get_type(&"police_02")))

	# Дома вдоль улицы: большое управление покрывает дальние, маленький участок — нет.
	for x in range(8, 58):
		if g.get_building_at(Vector2i(x, 31)) == null:
			g.place_building(&"res_small_01", Vector2i(x, 31), 0)
	ev.grid_reset.emit()
	await process_frame
	var big_cover: float = gs.service_coverage[BuildingData.Service.POLICE]
	g.remove_building(placed.id)
	g.place_building(&"police_01", Vector2i(30, 29), 2, true)
	ev.grid_reset.emit()
	await process_frame
	var small_cover: float = gs.service_coverage[BuildingData.Service.POLICE]
	print("police coverage: big %.2f small %.2f" % [big_cover, small_cover])
	check.call("bigger station covers more", big_cover > small_cover and small_cover > 0.0)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
