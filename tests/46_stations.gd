extends SceneTree
## Станции с модулями (как в SimCity): вместо ТЭЦ, водокачки и отдельных ветряков в меню — ветростанция
## и водозабор на участке 4×3; первый модуль стоит сразу, остальные достраиваются в карточке «Инфо»
## (три площадки, со служебной дорогой — шесть); свет, вода, расход и содержание — с модулями; модули
## и роторы рисуются на площадках и поворачиваются со станцией; сохранение; старые здания работают.


func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var sm: Node = root.get_node("SaveManager")
	sm.save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	sm.with_river = false
	sm.with_highway = false
	sm.new_city()
	await process_frame
	var g: CityGrid = gs.grid
	var tool: Node = main.get_node("BuildTool")
	var hud: Node = main.get_node("HUD")
	var mv: Node = main.get_node("ModuleVisualizer")
	var rv: Node = main.get_node("RotorVisualizer")
	var info: Node = null
	for node: Node in hud.find_children("*", "InfoPanel", true, false): info = node
	gs.money = 5000
	gs.rank = 3
	for x in range(4, 61): g.set_road(Vector2i(x, 40))
	ev.cells_changed.emit([Vector2i(4, 40)] as Array[Vector2i])

	# --- Меню: станции вместо ТЭЦ, водокачки и отдельных ветряков; старые типы остались для сохранений ---
	var menu: Array[String] = []
	for data: BuildingData in hud._tab_buildings("utilities"): menu.append(String(data.id))
	check.call("menu «Свет и вода»: wind station, water station %s" % str(menu), menu == ["wind_station", "water_station"])
	var retired: bool = true
	for id: StringName in [&"power_plant_01", &"water_tower_01", &"wind_turbine_01", &"wind_turbine_02"]:
		var old: BuildingData = BuildingCatalog.get_type(id)
		if old == null or old.buildable or BuildingCatalog.buildable_types().has(old): retired = false
	check.call("old plant, tower and turbines: kept for saves, not in the menu", retired)
	var wind_type: BuildingData = BuildingCatalog.get_type(&"wind_station")
	var water_type: BuildingData = BuildingCatalog.get_type(&"water_station")
	check.call("station types: 4×3 lots with models", wind_type != null and water_type != null
			and wind_type.size == Vector2i(4, 3) and water_type.size == Vector2i(4, 3)
			and wind_type.model != null and water_type.model != null)
	check.call("station icons", ResourceLoader.exists("res://assets/ui/icons/wind_station.png")
			or FileAccess.file_exists("res://assets/ui/icons/wind_station.png"))

	# --- Ветростанция: ставится инструментом, первый ветряк стоит и крутится сразу ---
	var place := func(type: StringName, cell: Vector2i) -> BuildingInstance:
		tool._set_mode(tool.Mode.PLACE, type)
		tool.cursor.has_cell = true
		tool.cursor.hovered_slot = null
		tool.cursor.hovered_cell = cell
		tool._dragging = true
		tool._drag_start = cell
		tool._update_drag(cell)
		var ids: Array = g.buildings.keys()
		tool._apply()
		tool._end_drag()
		for id: int in g.buildings:
			if not ids.has(id): return g.buildings[id]
		return null
	var money: int = gs.money
	var wind: BuildingInstance = place.call(&"wind_station", Vector2i(10, 41))
	check.call("wind station placed: 12 cells, paid $%d" % (money - gs.money), wind != null and wind.cells().size() == 12
			and money - gs.money == wind_type.cost and g.has_building_road_access(wind))
	check.call("gives the power of its first turbine (%d)" % gs.utilities.power_supply,
			gs.utilities.power_supply == wind_type.power_supply and wind_type.power_supply == StationModules.module(&"wind_small").power)
	var pad0: Vector3 = (g.building_transform(wind) * StationModules.pad_transform(0)).origin
	check.call("first turbine drawn on its pad, rotor spins", mv.counts() == {&"wind_small": 1}
			and mv.transform_of(&"wind_small", 0).origin.distance_to(pad0) < 0.01 and rv.counts() == Vector2i(1, 1))

	# --- Модули: три площадки, служебная дорога открывает ещё три ---
	money = gs.money
	var bought: bool = info.buy_module(wind.id, &"wind_small") and info.buy_module(wind.id, &"wind_large")
	var small: StationModules.Module = StationModules.module(&"wind_small")
	var large: StationModules.Module = StationModules.module(&"wind_large")
	check.call("two modules bought: paid $%d, power %d" % [money - gs.money, gs.utilities.power_supply],
			bought and money - gs.money == small.cost + large.cost
			and gs.utilities.power_supply == wind_type.power_supply + small.power + large.power)
	money = gs.money
	check.call("three pads taken: the next turbine needs a service road",
			StationModules.why_not(wind, &"wind_small").contains("служебная дорога")
			and not info.buy_module(wind.id, &"wind_small") and gs.money == money and wind.modules.size() == 2)
	check.call("a module of another station does not fit", not info.buy_module(wind.id, &"water_pump"))
	var road_ok: bool = info.buy_module(wind.id, StationModules.ROAD)
	check.call("service road: six pads, only one road", road_ok and StationModules.pad_count(wind) == 6
			and not info.buy_module(wind.id, StationModules.ROAD))
	for id: StringName in [&"wind_large", &"wind_large", &"wind_small"]: info.buy_module(wind.id, id)
	check.call("station full: 6 of 6, no more modules", StationModules.used_pads(wind) == 6
			and StationModules.why_not(wind, &"wind_small") == "все площадки заняты" and not info.buy_module(wind.id, &"wind_large"))
	var full_power: int = wind_type.power_supply + small.power * 2 + large.power * 3
	check.call("power and upkeep with modules (%d, $%d)" % [gs.utilities.power_supply, StationModules.upkeep(wind, wind_type)],
			gs.utilities.power_supply == full_power and StationModules.power_supply(wind, wind_type) == full_power
			and StationModules.upkeep(wind, wind_type) == wind_type.upkeep + small.upkeep * 2 + large.upkeep * 3)
	# Все модули — на участке станции, каждый на своей площадке; роторов — по числу ветряков.
	var drawn: Dictionary = mv.counts()
	var spots: Dictionary = {}
	var inside: bool = true
	var lot := Rect2(Vector2(wind.cell) * 2.0, Vector2(wind.size) * 2.0)
	for id: StringName in [&"wind_small", &"wind_large"]:
		for i in drawn.get(id, 0):
			var at: Vector3 = mv.transform_of(id, i).origin
			spots[Vector2i(roundi(at.x * 10.0), roundi(at.z * 10.0))] = true
			if not lot.has_point(Vector2(at.x, at.z)): inside = false
	check.call("modules drawn: 3 small, 3 large, the road; each on its own pad inside the lot",
			drawn == {&"wind_small": 3, &"wind_large": 3, &"service_road": 1} and spots.size() == 6 and inside)
	check.call("six rotors spin", rv.counts() == Vector2i(6, 6))

	# --- Карточка «Инфо»: модули и кнопки ---
	ev.cell_inspected.emit(wind.cells()[5])
	check.call("info card: three module buttons, all off on a full station", info.visible and info._module_buttons.size() == 3
			and info._module_buttons[&"wind_small"].disabled and info._module_buttons[&"wind_small"].tooltip_text.contains("Нельзя"))
	var second: BuildingInstance = place.call(&"wind_station", Vector2i(16, 37))
	ev.cell_inspected.emit(second.cells()[0])
	var button: Button = info._module_buttons[&"wind_large"]
	money = gs.money
	button.pressed.emit()
	check.call("button adds a module", not button.disabled and second.modules == [&"wind_large"] and money - gs.money == large.cost)
	gs.money = 10
	ev.stats_changed.emit()
	check.call("no money: buttons off", info._module_buttons[&"wind_small"].disabled
			and info._module_buttons[&"wind_small"].tooltip_text.contains("денег"))
	gs.money = 5000
	# Станция через улицу смотрит на неё: модули повёрнуты вместе с ней.
	var turned: Vector3 = (g.building_transform(second) * StationModules.pad_transform(1)).origin
	var seen: bool = false
	for i in mv.counts().get(&"wind_large", 0):
		if mv.transform_of(&"wind_large", i).origin.distance_to(turned) < 0.01: seen = true
	check.call("station across the street: faces it, its module follows", second.orientation != wind.orientation and seen
			and Rect2(Vector2(second.cell) * 2.0, Vector2(second.size) * 2.0).has_point(Vector2(turned.x, turned.z)))

	# --- Водозабор: вода идёт, пока есть свет; насосам и башням нужен свет ---
	var water: BuildingInstance = place.call(&"water_station", Vector2i(24, 41))
	var pump: StationModules.Module = StationModules.module(&"water_pump")
	var tower: StationModules.Module = StationModules.module(&"water_tower")
	check.call("water station: water of its first pump (%d)" % gs.utilities.water_supply,
			water != null and gs.utilities.water_supply == water_type.water_supply and water_type.water_supply == pump.water)
	info.buy_module(water.id, &"water_tower")
	info.buy_module(water.id, &"water_pump")
	check.call("tower and pump added: water %d, takes power %d" % [gs.utilities.water_supply, StationModules.power_use(water, water_type)],
			gs.utilities.water_supply == water_type.water_supply + tower.water + pump.water
			and StationModules.power_use(water, water_type) == water_type.power_use + tower.power_use + pump.power_use
			and gs.utilities.power_use == StationModules.power_use(water, water_type))
	check.call("pump and tower drawn", mv.counts().get(&"water_pump", 0) == 2 and mv.counts().get(&"water_tower", 0) == 1)

	# --- Сохранение: модули на месте, чужие и лишние отбрасываются ---
	var saved: Dictionary = JSON.parse_string(JSON.stringify(CS.to_dict(g, "S", 1000, 10, 0, 0)))
	for entry: Dictionary in saved.buildings:
		if int(entry.id) == second.id:
			entry["m"] = ["bogus", "water_pump", "wind_small", "wind_small", "wind_small", "wind_small"]
	var loaded = CS.from_dict(saved)
	var g2: CityGrid = loaded.grid if loaded.ok else null
	check.call("save/load keeps modules", g2 != null and loaded.warnings.is_empty() and g2.buildings[wind.id].modules == wind.modules
			and g2.buildings[water.id].modules == water.modules)
	check.call("load drops foreign and extra modules", g2 != null and g2.buildings[second.id].modules == [&"wind_small", &"wind_small"])

	# --- Старая ТЭЦ из сохранений работает; без света водозабор воды не даёт ---
	g.place_building(&"power_plant_01", Vector2i(40, 41), 0, true)
	ev.cells_changed.emit([Vector2i(40, 41)] as Array[Vector2i])
	var with_plant: int = gs.utilities.power_supply
	tool._set_mode(tool.Mode.BULLDOZE)
	for cell: Vector2i in [Vector2i(40, 41), wind.cells()[0], second.cells()[0]]:
		tool._dragging = true
		tool._drag_start = cell
		tool._update_drag(cell)
		tool._apply()
		tool._end_drag()
	check.call("old power plant still gives its 100 (%d)" % with_plant,
			with_plant == full_power + wind_type.power_supply + large.power + 100)
	check.call("stations bulldozed: modules and rotors gone, no power — no water",
			not g.buildings.has(wind.id) and not g.buildings.has(second.id) and rv.counts() == Vector2i.ZERO
			and not mv.counts().has(&"wind_small") and gs.utilities.power_supply == 0 and gs.utilities.water_supply == 0)

	# --- Убрать модуль: достроенный — можно, встроенный — нет, дорогу — когда её площадки пусты ---
	var third: BuildingInstance = place.call(&"wind_station", Vector2i(32, 41))
	info.buy_module(third.id, &"wind_small")
	info.buy_module(third.id, &"wind_large")
	money = gs.money
	var removed: bool = info.remove_module(third.id, &"wind_small")
	var shifted: Vector3 = (g.building_transform(third) * StationModules.pad_transform(1)).origin
	check.call("module removed: no refund, power down, the next one moves to its pad",
			removed and third.modules == [&"wind_large"] and gs.money == money
			and gs.utilities.power_supply == wind_type.power_supply + large.power
			and mv.counts().get(&"wind_small", 0) == 1 and mv.counts().get(&"wind_large", 0) == 1
			and mv.transform_of(&"wind_large", 0).origin.distance_to(shifted) < 0.01 and rv.counts() == Vector2i(2, 2))
	check.call("the built-in first turbine stays with the station", not info.remove_module(third.id, &"wind_small")
			and StationModules.why_not_remove(third, &"wind_small").contains("нет"))
	for id: StringName in [StationModules.ROAD, &"wind_small", &"wind_small"]: info.buy_module(third.id, id)
	check.call("service road in use: cannot be removed", StationModules.used_pads(third) == 4
			and StationModules.why_not_remove(third, StationModules.ROAD).contains("сначала")
			and not info.remove_module(third.id, StationModules.ROAD))
	ev.cell_inspected.emit(third.cells()[0])
	check.call("info card: a remove button per kind, the road one is off",
			info._remove_buttons.size() == 3 and info._remove_buttons[StationModules.ROAD].disabled
			and not info._remove_buttons[&"wind_small"].disabled and info._remove_buttons[&"wind_small"].text.contains("стоит 2"))
	info._remove_buttons[&"wind_small"].pressed.emit()
	check.call("button removes one module; now the road can go", third.modules.count(&"wind_small") == 1
			and StationModules.used_pads(third) == 3 and info.remove_module(third.id, StationModules.ROAD)
			and StationModules.pad_count(third) == 3)

	# --- У кривой дороги станция встаёт под её углом, модули — вместе с ней ---
	var graph: RoadGraph = g.roads
	graph.sync(g)
	var pa := RoadGraph.RoadPoint.new(RoadGraph.cell_center(Vector2i(50, 40)))
	pa.segment = graph.segment_near(pa.pos, 0.8)
	var pb := RoadGraph.RoadPoint.new(RoadGraph.cell_center(Vector2i(30, 10)))
	var plan: RoadGraph.Plan = graph.plan(g, pa, pb, null, 1, 1000000)
	if plan.ok: ev.cells_changed.emit(graph.build(g, plan))
	g.ensure_strips()
	var diagonal: int = graph.segment_near(RoadGraph.cell_center(Vector2i(40, 25)), 0.6)
	var seat: FreeStrips.Slot = g.free_strips.slot_in(diagonal, 1, g.free_strips.frames[diagonal].count / 2, 1) if diagonal != -1 else null
	var angled: BuildingInstance = null
	if seat != null:
		tool._set_mode(tool.Mode.PLACE, &"wind_station")
		tool.cursor.has_cell = true
		tool.cursor.hovered_slot = seat
		tool.cursor.hovered_cell = RoadGraph.cell_of(seat.center)
		tool._dragging = true
		tool._drag_start = tool.cursor.hovered_cell
		tool._update_drag(tool._drag_start)
		var ids: Array = g.buildings.keys()
		tool._apply()
		tool._end_drag()
		for id: int in g.buildings:
			if not ids.has(id): angled = g.buildings[id]
	var follows: bool = angled != null and angled.is_free() and info.buy_module(angled.id, &"wind_large")
	if follows:
		var want: Transform3D = g.building_transform(angled) * StationModules.pad_transform(1)
		follows = false
		for i in mv.counts().get(&"wind_large", 0):
			var got: Transform3D = mv.transform_of(&"wind_large", i)
			if got.origin.distance_to(want.origin) < 0.01 and got.basis.is_equal_approx(want.basis): follows = true
		follows = follows and absf(fposmod(angled.yaw, PI * 0.5)) > 0.05
	check.call("station by a diagonal road: at its angle, the module turns with it", follows)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
