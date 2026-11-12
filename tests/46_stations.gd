extends SceneTree
## Станции с модулями (как в SimCity): вместо ТЭЦ, водокачки и отдельных ветряков в меню — ветростанция
## и водозабор на участке 4×3; первый модуль стоит сразу, остальные игрок ставит на карте рядом
## (кнопка в карточке «Инфо» → щелчок по клетке): ветряки — вдоль служебной дороги (тянется мышью,
## бесплатно) или у станции, насосы и башни — вплотную к станции или друг к другу; бульдозер сносит
## модуль один; свет, вода, расход и содержание — с модулями; сохранение; старые здания работают.


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
	# --- До щелчка: под мышью контур станции в полный размер, а не курсор в одну клетку ---
	var hover := func(type: StringName, cell: Vector2i, slot: FreeStrips.Slot) -> void:
		tool._set_mode(tool.Mode.PLACE, type)
		tool.cursor.has_cell = true
		tool.cursor.hovered_slot = slot
		tool.cursor.hovered_cell = cell
		tool._process(0.0)
	hover.call(&"wind_station", Vector2i(10, 41), null)
	var shown: int = tool.preview.multimesh.instance_count
	check.call("hover before the click: the whole 4×3 lot outlined (%d cells), cell marker hidden" % shown,
			shown == 12 and tool.cursor.suppressed
			and tool.preview.multimesh.get_instance_color(0) == tool.CURSOR_COLORS[tool.Mode.PLACE])
	hover.call(&"wind_station", Vector2i(10, 20), null)
	check.call("hover away from roads: the outline is red", tool.preview.multimesh.instance_count == 12
			and tool.preview.multimesh.get_instance_color(0) == tool.INVALID_COLOR)
	tool.cursor.has_cell = false
	tool._process(0.0)
	check.call("pointer off the map: outline gone", tool.preview.multimesh.instance_count == 0)
	tool._set_mode(tool.Mode.NONE)
	check.call("another tool: the cell marker is back", not tool.cursor.suppressed)

	var money: int = gs.money
	var wind: BuildingInstance = place.call(&"wind_station", Vector2i(10, 41))
	check.call("wind station placed: 12 cells, paid $%d" % (money - gs.money), wind != null and wind.cells().size() == 12
			and money - gs.money == wind_type.cost and g.has_building_road_access(wind))
	check.call("gives the power of its first turbine (%d)" % gs.utilities.power_supply,
			gs.utilities.power_supply == wind_type.power_supply and wind_type.power_supply == StationModules.module(&"wind_small").power)
	var pad0: Vector3 = (g.building_transform(wind) * Transform3D(Basis.IDENTITY,
			Vector3(StationModules.BUILTIN_PAD.x, StationModules.PAD_TOP, StationModules.BUILTIN_PAD.y))).origin
	check.call("first turbine drawn on its pad, rotor spins", mv.counts() == {&"wind_small": 1}
			and mv.transform_of(&"wind_small", 0).origin.distance_to(pad0) < 0.01 and rv.counts() == Vector2i(1, 1))

	# --- Модули ставятся на карте, как в SimCity: щелчок по клетке рядом со станцией ---
	var put := func(station: BuildingInstance, id: StringName, cell: Vector2i) -> bool:
		tool.start_module(station.id, id)
		tool.cursor.has_cell = true
		tool.cursor.hovered_slot = null
		tool.cursor.hovered_cell = cell
		tool._dragging = true
		tool._drag_start = cell
		tool._update_drag(cell)
		var had: int = station.modules.size()
		tool._apply()
		tool._end_drag()
		return station.modules.size() > had and station.module_cells.has(cell)
	var drag_road := func(station: BuildingInstance, from: Vector2i, to: Vector2i) -> int:
		tool.start_module(station.id, StationModules.ROAD)
		tool.cursor.has_cell = true
		tool.cursor.hovered_slot = null
		tool.cursor.hovered_cell = to
		tool._dragging = true
		tool._drag_start = from
		tool._update_drag(to)
		var had: int = StationModules.road_count(station)
		tool._apply()
		tool._end_drag()
		return StationModules.road_count(station) - had
	var small: StationModules.Module = StationModules.module(&"wind_small")
	var large: StationModules.Module = StationModules.module(&"wind_large")
	money = gs.money
	check.call("turbine right by the station: placed on its cell, paid, power up",
			put.call(wind, &"wind_small", Vector2i(14, 41)) and money - gs.money == small.cost
			and gs.utilities.power_supply == wind_type.power_supply + small.power
			and g.get_building_at(Vector2i(14, 41)) == wind and g.tile_type[g.index_of(Vector2i(14, 41))] == CityGrid.Tile.BUILDING)
	money = gs.money
	check.call("turbine away from the station and its road: refused",
			not put.call(wind, &"wind_small", Vector2i(20, 47)) and gs.money == money
			and StationModules.why_not_at(g, wind, &"wind_small", Vector2i(20, 47)).contains("вдоль служебной дороги"))
	check.call("a module of another station does not fit",
			StationModules.why_not_at(g, wind, &"water_pump", Vector2i(14, 42)).contains("не подходит"))
	check.call("not on the street", StationModules.why_not_at(g, wind, &"wind_small", Vector2i(12, 40)) == "клетка занята")
	# Служебная дорога — бесплатно, тянется мышью от участка станции.
	money = gs.money
	var laid: int = drag_road.call(wind, Vector2i(14, 43), Vector2i(14, 50))
	check.call("service road dragged from the lot: 8 cells, free (%d)" % laid, laid == 8 and gs.money == money
			and StationModules.road_count(wind) == 8 and mv.road_cells == 8)
	check.call("road must start at the station or its end", drag_road.call(wind, Vector2i(30, 50), Vector2i(32, 50)) == 0
			and StationModules.why_not_at(g, wind, StationModules.ROAD, Vector2i(30, 50)).contains("тянется"))
	check.call("dragging from the road end extends it", drag_road.call(wind, Vector2i(14, 50), Vector2i(16, 50)) == 2)
	check.call("turbines along the service road", put.call(wind, &"wind_large", Vector2i(15, 47))
			and put.call(wind, &"wind_small", Vector2i(13, 49)))
	var farm_power: int = wind_type.power_supply + small.power * 2 + large.power
	check.call("power and upkeep with modules (%d, $%d)" % [gs.utilities.power_supply, StationModules.upkeep(wind, wind_type)],
			gs.utilities.power_supply == farm_power and StationModules.power_supply(wind, wind_type) == farm_power
			and StationModules.upkeep(wind, wind_type) == wind_type.upkeep + small.upkeep * 2 + large.upkeep)
	check.call("modules drawn on their cells, rotors spin", mv.counts() == {&"wind_small": 3, &"wind_large": 1}
			and mv.transform_of(&"wind_large", 0).origin.distance_to(g.grid_to_world(Vector2i(15, 47))) < 0.01
			and rv.counts() == Vector2i(4, 4))

	# --- Постановка до щелчка: свободные клетки подсвечены, под мышью — модель ветряка ---
	tool.start_module(wind.id, &"wind_small")
	tool.cursor.has_cell = true
	tool.cursor.hovered_slot = null
	tool.cursor.hovered_cell = Vector2i(15, 48)
	tool._process(0.0)
	var lit: int = tool.preview.multimesh.instance_count
	check.call("hover: free cells along the road lit (%d), model under the mouse" % lit,
			lit >= 10 and tool.preview.has_ghost() and tool.cursor.suppressed
			and lit == StationModules.free_cells(g, wind, &"wind_small").size())
	tool.cursor.hovered_cell = Vector2i(25, 50)
	tool._process(0.0)
	check.call("hover far away: the model turns red", tool.preview.has_ghost()
			and tool.preview._ghost_material.albedo_color == tool.INVALID_COLOR)
	tool._set_mode(tool.Mode.NONE)

	# --- Карточка «Инфо»: щелчок по ветряку открывает станцию, кнопки включают постановку ---
	ev.cell_inspected.emit(Vector2i(15, 47))
	check.call("clicking a turbine opens its station card", info.visible and info._title.text == wind_type.display_name
			and info._module_buttons.size() == 3)
	info._module_buttons[StationModules.ROAD].pressed.emit()
	check.call("road button starts placing the road for this station", tool.mode == tool.Mode.MODULE
			and tool.place_type == StationModules.ROAD and tool.place_station == wind.id)
	gs.money = 10
	ev.stats_changed.emit()
	check.call("no money: turbine buttons off, the free road still on", info._module_buttons[&"wind_small"].disabled
			and info._module_buttons[&"wind_small"].tooltip_text.contains("денег")
			and not info._module_buttons[StationModules.ROAD].disabled)
	gs.money = 5000
	tool._set_mode(tool.Mode.NONE)

	# --- Бульдозер: модуль сносится один; то, на чём держатся другие, — нет ---
	var bulldoze := func(from: Vector2i, to: Vector2i) -> void:
		tool._set_mode(tool.Mode.BULLDOZE)
		tool._dragging = true
		tool._drag_start = from
		tool._update_drag(to)
		tool._apply()
		tool._end_drag()
	bulldoze.call(Vector2i(14, 47), Vector2i(14, 47))
	check.call("road piece holding a turbine and the far road: stays",
			StationModules.road_count(wind) == 10 and g.buildings.has(wind.id)
			and StationModules.why_not_remove(g, wind, StationModules.index_at(wind, Vector2i(14, 47))).contains("держатся"))
	money = gs.money
	bulldoze.call(Vector2i(15, 47), Vector2i(15, 47))
	check.call("turbine bulldozed alone: station stays, no refund, power down",
			g.buildings.has(wind.id) and not wind.module_cells.has(Vector2i(15, 47)) and gs.money == money
			and gs.utilities.power_supply == farm_power - large.power
			and g.tile_type[g.index_of(Vector2i(15, 47))] == CityGrid.Tile.EMPTY and rv.counts() == Vector2i(3, 3))
	bulldoze.call(Vector2i(13, 44), Vector2i(16, 50))
	check.call("bulldozer over the farm: turbine and road gone (turbine first), station stays",
			g.buildings.has(wind.id) and wind.modules == [&"wind_small", StationModules.ROAD]
			and wind.module_cells == [Vector2i(14, 41), Vector2i(14, 43)] and mv.road_cells == 1)

	# --- Водозабор: насосы и башни — вплотную к станции или друг к другу; им нужен свет ---
	var water: BuildingInstance = place.call(&"water_station", Vector2i(24, 41))
	var pump: StationModules.Module = StationModules.module(&"water_pump")
	var tower: StationModules.Module = StationModules.module(&"water_tower")
	check.call("water station: water of its first pump (%d)" % gs.utilities.water_supply,
			water != null and gs.utilities.water_supply == water_type.water_supply and water_type.water_supply == pump.water)
	check.call("tower by the station, pump by the tower", put.call(water, &"water_tower", Vector2i(28, 41))
			and put.call(water, &"water_pump", Vector2i(29, 41)))
	check.call("pump far from the station and its modules: refused", not put.call(water, &"water_pump", Vector2i(31, 44))
			and StationModules.why_not_at(g, water, &"water_pump", Vector2i(31, 44)).contains("вплотную"))
	check.call("tower and pump added: water %d, takes power %d" % [gs.utilities.water_supply, StationModules.power_use(water, water_type)],
			gs.utilities.water_supply == water_type.water_supply + tower.water + pump.water
			and StationModules.power_use(water, water_type) == water_type.power_use + tower.power_use + pump.power_use
			and gs.utilities.power_use == StationModules.power_use(water, water_type))
	bulldoze.call(Vector2i(28, 41), Vector2i(28, 41))
	check.call("tower holding the pump: stays", water.module_cells.has(Vector2i(28, 41)))
	check.call("pump and tower drawn", mv.counts().get(&"water_pump", 0) == 2 and mv.counts().get(&"water_tower", 0) == 1)

	# --- Сохранение: модули на своих клетках; чужие и не держащиеся отбрасываются; старый вид — рядом ---
	var second: BuildingInstance = place.call(&"wind_station", Vector2i(16, 37))
	var third: BuildingInstance = place.call(&"wind_station", Vector2i(32, 41))
	var second_right: int = second.cell.x + second.size.x
	var saved: Dictionary = JSON.parse_string(JSON.stringify(CS.to_dict(g, "S", 1000, 10, 0, 0)))
	for entry: Dictionary in saved.buildings:
		if int(entry.id) == second.id:
			entry["m"] = ["wind_small", second_right, second.cell.y, "bogus", second_right, second.cell.y + 1,
					"water_pump", second_right, second.cell.y + 2, "wind_small", 50, 20, "wind_small", second.cell.x - 1, second.cell.y]
		if int(entry.id) == third.id:
			entry["m"] = ["wind_small", "service_road", "wind_large"]
	var loaded = CS.from_dict(saved)
	var g2: CityGrid = loaded.grid if loaded.ok else null
	check.call("save/load keeps modules on their cells", g2 != null and g2.buildings[wind.id].modules == wind.modules
			and g2.buildings[wind.id].module_cells == wind.module_cells and g2.buildings[water.id].module_cells == water.module_cells
			and g2.get_building_at(Vector2i(29, 41)).id == water.id)
	check.call("load drops foreign, unknown and loose modules", g2 != null
			and g2.buildings[second.id].modules == [&"wind_small", &"wind_small"]
			and g2.buildings[second.id].module_cells == [Vector2i(second_right, second.cell.y), Vector2i(second.cell.x - 1, second.cell.y)]
			and not loaded.warnings.is_empty() and g2.tile_type[g2.index_of(Vector2i(50, 20))] == CityGrid.Tile.EMPTY)
	var legacy_ok: bool = g2 != null and g2.buildings[third.id].modules == [&"wind_small", &"wind_large"]
	if legacy_ok:
		for cell: Vector2i in g2.buildings[third.id].module_cells:
			legacy_ok = legacy_ok and StationModules.index_at(g2.buildings[third.id], cell) != -1 \
					and g2.get_building_at(cell) == g2.buildings[third.id]
	check.call("old save (modules on lot pads): turbines set right by the station, old road dropped", legacy_ok)

	# --- Предел модулей у станции ---
	drag_road.call(third, Vector2i(36, 43), Vector2i(36, 52))
	for y in range(43, 53):
		put.call(third, &"wind_small", Vector2i(37, y))
	put.call(third, &"wind_small", Vector2i(31, 41))
	put.call(third, &"wind_small", Vector2i(31, 42))
	check.call("station full: %d modules, no more" % StationModules.module_count(third),
			StationModules.module_count(third) == StationModules.MAX_MODULES
			and StationModules.why_not(third, &"wind_small").contains("больше нельзя")
			and not put.call(third, &"wind_small", Vector2i(35, 44)))

	# --- Старая ТЭЦ из сохранений работает; без света водозабор воды не даёт ---
	var before_plant: int = gs.utilities.power_supply
	g.place_building(&"power_plant_01", Vector2i(40, 41), 0, true)
	ev.cells_changed.emit([Vector2i(40, 41)] as Array[Vector2i])
	check.call("old power plant still gives its 100 (%d)" % gs.utilities.power_supply,
			gs.utilities.power_supply == before_plant + 100)
	for cell: Vector2i in [Vector2i(40, 41), wind.cells()[0], second.cells()[0], third.cells()[0]]:
		bulldoze.call(cell, cell)
	check.call("stations bulldozed: modules, road and rotors gone, no power — no water",
			not g.buildings.has(wind.id) and not g.buildings.has(second.id) and not g.buildings.has(third.id)
			and rv.counts() == Vector2i.ZERO and not mv.counts().has(&"wind_small") and mv.road_cells == 0
			and g.tile_type[g.index_of(Vector2i(14, 41))] == CityGrid.Tile.EMPTY
			and g.tile_type[g.index_of(Vector2i(37, 45))] == CityGrid.Tile.EMPTY
			and gs.utilities.power_supply == 0 and gs.utilities.water_supply == 0)

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
		hover.call(&"wind_station", RoadGraph.cell_of(seat.center), seat)
		check.call("hover by a diagonal road: the station outline at the road angle",
				tool.preview.quad_count() == 1 and tool.preview.multimesh.instance_count == 0)
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
	var follows: bool = angled != null and angled.is_free()
	if follows:
		var spots: Array[Vector2i] = StationModules.free_cells(g, angled, &"wind_large")
		follows = not spots.is_empty() and put.call(angled, &"wind_large", spots[0])
		if follows:
			var want := Transform3D(g.building_transform(angled).basis, g.grid_to_world(spots[0]))
			follows = false
			for i in mv.counts().get(&"wind_large", 0):
				var got: Transform3D = mv.transform_of(&"wind_large", i)
				if got.origin.distance_to(want.origin) < 0.01 and got.basis.is_equal_approx(want.basis): follows = true
		follows = follows and absf(fposmod(angled.yaw, PI * 0.5)) > 0.05
	check.call("station by a diagonal road: at its angle, a module next to it turns with it", follows)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
