extends SceneTree
## Ветряки (модели Argon): обычный даёт мало, вертикальный — больше; без дыма; ротор — на оси
## и крутится, пока игра идёт; у ветряка без дороги стоит; во вкладке «Свет и вода» — первыми.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hud: Node = main.get_node("HUD")
	var rv: Node = main.get_node("RotorVisualizer")
	var g: CityGrid = gs.grid

	# Типы.
	var small: BuildingData = BuildingCatalog.get_type(&"wind_turbine_01")
	var big: BuildingData = BuildingCatalog.get_type(&"wind_turbine_02")
	var plant: BuildingData = BuildingCatalog.get_type(&"power_plant_01")
	check.call("types exist", small != null and big != null and small.zone == CityGrid.Zone.NONE and not small.grows
			and small.rotor != null and big.rotor != null)
	check.call("small gives less than big", small.power_supply > 0 and small.power_supply < big.power_supply
			and big.power_supply < plant.power_supply)
	check.call("no smoke", small.pollution == 0 and big.pollution == 0)
	check.call("cost per kW above coal", float(small.cost) / small.power_supply > float(plant.cost) / plant.power_supply
			and float(big.cost) / big.power_supply > float(plant.cost) / plant.power_supply)
	print("small %s $%d, big %s $%d" % [Utilities.power_text(small.power_supply), small.cost,
			Utilities.power_text(big.power_supply), big.cost])

	# Во вкладке «Свет и вода»: сначала свет (ветряки по цене, ТЭЦ), потом вода.
	var order: Array = []
	for data: BuildingData in hud._tab_buildings("utilities"):
		order.append(String(data.id))
	print("tab order: ", order)
	check.call("utilities tab order", order == ["wind_station", "water_station"])
	check.call("wind icons", ResourceLoader.exists("res://assets/ui/icons/wind_turbine_01.png")
			and ResourceLoader.exists("res://assets/ui/icons/wind_turbine_02.png"))

	# Ставим ветряки у дороги и один без дороги.
	for x in range(10, 30): g.set_road(Vector2i(x, 20))
	var id_small: int = g.place_building(&"wind_turbine_01", Vector2i(12, 19), 2, true)
	var id_big: int = g.place_building(&"wind_turbine_02", Vector2i(14, 21), 0, true)
	var id_far: int = g.place_building(&"wind_turbine_01", Vector2i(12, 26), 2, true)
	ev.grid_reset.emit()
	await process_frame
	var u: Utilities = gs.utilities
	check.call("wind gives power", u.power_supply == small.power_supply + big.power_supply)
	check.call("rotors drawn, far one still", rv.counts() == Vector2i(3, 2))

	# Ротор — на оси: у обычного над башней у фасада (к улице), у вертикального — над основанием.
	var layer_small: MultiMeshInstance3D = rv._layers[&"wind_turbine_01"]
	var hub: Vector3 = Vector3.ZERO
	for i in layer_small.multimesh.instance_count:
		var origin: Vector3 = layer_small.multimesh.get_instance_transform(i).origin
		var cell_center: Vector3 = g.grid_to_world(Vector2i(12, 19))
		if Vector2(origin.x - cell_center.x, origin.z - cell_center.z).length() < 1.0: hub = origin
	var center: Vector3 = g.grid_to_world(Vector2i(12, 19))
	print("hub ", hub, " center ", center)
	check.call("small rotor on its hub, facing the street", is_equal_approx(hub.y, 3.38)
			and is_equal_approx(hub.x, center.x) and is_equal_approx(hub.z, center.z + 0.44))
	var big_origin: Vector3 = rv._layers[&"wind_turbine_02"].multimesh.get_instance_transform(0).origin
	check.call("big rotor on its base", is_equal_approx(big_origin.y, 1.04)
			and big_origin.distance_to(g.grid_to_world(Vector2i(14, 21)) + Vector3(0, 1.04, 0)) < 0.01)

	# Крутится, пока игра идёт; на паузе и без дороги стоит.
	var basis_of := func(id: StringName, i: int) -> Basis:
		return rv._layers[id].multimesh.get_instance_transform(i).basis
	var before: Basis = basis_of.call(&"wind_turbine_02", 0)
	rv._process(0.5)
	check.call("paused: still", basis_of.call(&"wind_turbine_02", 0).is_equal_approx(before))
	clock.set_speed(1)
	var still_far: Array[Basis] = []
	for i in layer_small.multimesh.instance_count: still_far.append(basis_of.call(&"wind_turbine_01", i))
	rv._process(0.5)
	var turned_far := 0
	for i in layer_small.multimesh.instance_count:
		if not basis_of.call(&"wind_turbine_01", i).is_equal_approx(still_far[i]): turned_far += 1
	check.call("running: spins", not basis_of.call(&"wind_turbine_02", 0).is_equal_approx(before) and turned_far == 1)
	clock.set_speed(0)

	# Снос — ротор уходит.
	g.remove_building(id_far)
	var changed: Array[Vector2i] = [Vector2i(12, 26)]
	ev.cells_changed.emit(changed)
	check.call("demolished rotor removed", rv.counts() == Vector2i(2, 2))

	# Подсказки: только воды нет — про водокачку, не про ТЭЦ.
	for x in range(15, 19):
		g.set_zone(Vector2i(x, 19), CityGrid.Zone.RESIDENTIAL)
	ev.grid_reset.emit()
	await process_frame
	var hints: String = "|".join(hud._advisor.texts())
	print("hints: ", hints)
	check.call("hint about water only", hints.contains("водозабор") and not hints.contains("ветростанц"))

	# Шкала: что даёт каждая станция — в подсказке.
	var meter: Node = hud._utility_meters[0]
	check.call("meter tooltip lists stations", meter.tooltip_text.contains("ветростанция — 250 кВт")
			and meter.tooltip_text.contains("ветряк — +250 кВт") and meter.tooltip_text.contains("вертикальный ветряк — +550 кВт"))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
