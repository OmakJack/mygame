extends SceneTree
## Фаза 10: плотность, уровни, перестройка, счастье, упадок, звания, замки, стройплощадка, сохранения.
const OUT := "res://tests/out/"

func _initialize() -> void:
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var sm: Node = root.get_node("SaveManager")
	root.get_node("SimClock").set_speed(0)
	sm.save_dir = OUT + "saves14/"
	sm.with_river = false
	DirAccess.make_dir_recursive_absolute(sm.save_dir)
	var LV: GDScript = load("res://scripts/simulation/levels.gd")
	var HP: GDScript = load("res://scripts/simulation/happiness.gd")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var sim: Node = main.get_node("Simulation")
	var tool: Node = main.get_node("BuildTool")

	# --- Данные ---
	check.call("old zone values kept", CityGrid.Zone.RESIDENTIAL == 1 and CityGrid.Zone.INDUSTRIAL == 3 and CityGrid.Zone.OFFICE == 6)
	check.call("categories", CityGrid.zone_category(CityGrid.Zone.OFFICE) == CityGrid.Zone.INDUSTRIAL and CityGrid.zone_category(CityGrid.Zone.RESIDENTIAL_HIGH) == CityGrid.Zone.RESIDENTIAL)
	var all_levels := true
	for z in [1, 2, 3, 4, 5, 6]:
		for lvl in [1, 2, 3]:
			if BuildingCatalog.level_types(z, lvl).is_empty(): all_levels = false
	check.call("every zone has levels 1-3", all_levels)
	check.call("growth only level 1", BuildingCatalog.growable_types(1).all(func(d): return d.level == 1))

	# --- Замки и звания ---
	gs.rank = 0
	ev.tool_requested.emit(8)
	check.call("high density locked at village", tool.mode == 0)
	var got_signal := [false]
	ev.rank_changed.connect(func(_r): got_signal[0] = true)
	var m0: int = gs.money
	sim._update_rank(650)
	check.call("rank up with reward", gs.rank == 2 and gs.money == m0 + 500 + 1500 and got_signal[0])
	sim._update_rank(100)
	check.call("rank never drops", gs.rank == 2)
	ev.tool_requested.emit(8)
	check.call("high density unlocked at town", tool.mode == 8)
	ev.tool_requested.emit(10)
	check.call("offices still locked", tool.mode == 8)
	ev.tool_requested.emit(0)

	# --- Перекраска плотности и перестройка ---
	var g: CityGrid = gs.grid
	for x in range(10, 30): g.set_road(Vector2i(x, 20))
	g.place_building(&"power_plant_01", Vector2i(10, 21), 0, true)
	g.place_building(&"water_tower_01", Vector2i(11, 21), 0, true)
	g.set_zone(Vector2i(15, 19), CityGrid.Zone.RESIDENTIAL)
	var hid: int = g.place_building(&"res_small_01", Vector2i(15, 19), 2)
	check.call("repaint density over house", g.can_zone(Vector2i(15, 19), CityGrid.Zone.RESIDENTIAL_HIGH) and not g.can_zone(Vector2i(15, 19), CityGrid.Zone.OFFICE))
	g.set_zone(Vector2i(15, 19), CityGrid.Zone.RESIDENTIAL_HIGH)
	ev.grid_reset.emit()
	await process_frame
	var rng := RandomNumberGenerator.new()
	var demands: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 0.5, CityGrid.Zone.COMMERCIAL: 0.5, CityGrid.Zone.INDUSTRIAL: 0.5}
	for i in 20:
		LV.step(g, rng, gs.network, gs.utilities, gs.land, gs.happiness, demands)
	var rebuilt: BuildingData = BuildingCatalog.get_type(g.buildings[hid].type_id)
	check.call("house rebuilt as apartment block", rebuilt.zone == CityGrid.Zone.RESIDENTIAL_HIGH and rebuilt.level == 1)
	check.call("construction site set", g.buildings[hid].construction_ticks == LV.construction_ticks_for(rebuilt)
			and g.buildings[hid].construction_total == g.buildings[hid].construction_ticks)
	var bv = main.get_node("BuildingVisualizer")
	ev.cells_changed.emit([Vector2i(15, 19)] as Array[Vector2i])
	check.call("construction drawn", bv.get_cell_item(Vector3i(15, 0, 19)) == bv._construction_item)
	for i in LV.construction_ticks_for(rebuilt): LV.tick_construction(g)
	ev.cells_changed.emit([Vector2i(15, 19)] as Array[Vector2i])
	check.call("building drawn after construction", bv.get_cell_item(Vector3i(15, 0, 19)) != bv._construction_item)

	# --- Повышение уровня у парков ---
	g.set_zone(Vector2i(20, 19), CityGrid.Zone.RESIDENTIAL)
	var uid: int = g.place_building(&"res_small_01", Vector2i(20, 19), 2)
	for c in [Vector2i(19, 18), Vector2i(21, 18), Vector2i(20, 17)]:
		g.place_building(&"park_plaza", c, 0, true)
	g.place_building(&"school_01", Vector2i(19, 21), 0, true)
	g.place_building(&"health_01", Vector2i(21, 21), 0, true)
	ev.grid_reset.emit()
	await process_frame
	var b: BuildingInstance = g.buildings[uid]
	var data: BuildingData = BuildingCatalog.get_type(b.type_id)
	print("   land=%d happy=%d blockers=%s" % [gs.land.value_at(gs.land.land_value, g, b.cell), gs.happiness.by_building.get(uid, -1), str(LV.blockers(g, b, data, gs.land, gs.happiness))])
	for i in 30:
		LV.step(g, rng, gs.network, gs.utilities, gs.land, gs.happiness, demands)
	check.call("house upgraded near parks", BuildingCatalog.get_type(g.buildings[uid].type_id).level >= 2)

	# --- Счастье и упадок ---
	var hp = HP.new()
	hp.by_building[uid] = 5
	for i in LV.DECLINE_TICKS - 1: LV.decline(g, hp)
	check.call("unhappy house still there", g.buildings.has(uid))
	var gone: Array = LV.decline(g, hp)
	check.call("unhappy house leaves", not g.buildings.has(uid) and gone.size() == 1)
	var dirty := CityGrid.new(32)
	for x in range(5, 25): dirty.set_road(Vector2i(x, 10))
	var home: int = dirty.place_building(&"res_small_01", Vector2i(12, 11), 0)
	var clean_mood: int = HP.compute(dirty, LandValue.compute(dirty, Traffic.new()), Traffic.new(), 9).by_building[home]
	for c in [Vector2i(11, 9), Vector2i(12, 9), Vector2i(13, 9)]:
		dirty.place_building(&"ind_small_01", c, 0)
	for bb in dirty.buildings.values(): bb.powered = true; bb.has_water = true
	var dirty_mood: int = HP.compute(dirty, LandValue.compute(dirty, Traffic.new()), Traffic.new(), 9).by_building[home]
	check.call("pollution lowers happiness (%d → %d)" % [clean_mood, dirty_mood], dirty_mood < clean_mood)

	# --- Сохранение ---
	g.buildings[hid].unhappy_ticks = 7
	var d: Dictionary = CS.to_dict(g, "x", 100, 9, 5, 650, 2)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("rank and unhappy days saved", back.ok and back.rank == 2 and back.grid.buildings[hid].unhappy_ticks == 7)
	d.state.erase("rank")
	back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("old save rank = -1", back.rank == -1)

	# --- HUD ---
	var hud: Node = main.get_node("HUD")
	hud._refresh_stats()
	check.call("rank chip", hud._rank_label.text.begins_with("Городок"))
	check.call("zone cards (7) and office locked", hud._tab_cards["zones"].get_child_count() == 7 and hud._tool_buttons[10].disabled)
	ev.cell_inspected.emit(Vector2i(15, 19))
	var has_mood := false
	for child in hud._info._rows.get_children():
		if child is Label and child.text == "Счастье": has_mood = true
	check.call("info shows happiness", has_mood)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
