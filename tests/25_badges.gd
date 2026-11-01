extends SceneTree
## Дома растут без света и воды, над ними — значки (BadgeVisualizer); провели свет и воду — значки
## пропали. Без света дом не пустеет от несчастья и не повышается, сносится только через
## Decay.NO_UTILITY_TICKS (тогда пустеет); стройплощадка без значка и без счётчика.

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
	var tool: Node = main.get_node("BuildTool")
	var badges: Node = main.get_node("BadgeVisualizer")
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var g: CityGrid = gs.grid
	gs.money = 100000
	drag.call(tool.Mode.ROAD, Vector2i(20, 30), Vector2i(50, 30))
	drag.call(tool.Mode.ZONE_R, Vector2i(22, 27), Vector2i(35, 29))
	drag.call(tool.Mode.ZONE_I, Vector2i(22, 31), Vector2i(35, 33))
	check.call("no badges in empty city", badges.counts() == Vector2i.ZERO)

	# Ни ТЭЦ, ни водокачки — а дома всё равно растут.
	for tick in 40:
		ev.sim_tick.emit()
	var homes := 0
	var factories := 0
	var dark := 0
	var sites := 0
	for b: BuildingInstance in g.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(b.type_id)
		if data.zone == CityGrid.Zone.RESIDENTIAL: homes += 1
		if data.zone == CityGrid.Zone.INDUSTRIAL: factories += 1
		if not b.powered and not b.has_water: dark += 1
		if b.construction_ticks > 0: sites += 1
	print("homes=%d factories=%d dark=%d sites=%d badges=%s pop=%d" % [homes, factories, dark, sites, badges.counts(), gs.population])
	check.call("homes and factories grow without power and water", homes >= 1 and factories >= 1 and gs.population > 0)
	check.call("all are without power and water", dark == g.buildings.size())
	var built: int = g.buildings.size() - sites
	check.call("two badges over each built house (%s, %d built)" % [badges.counts(), built],
			badges.counts() == Vector2i(built, built) and built > 0)
	var sample: BuildingInstance = null
	for b: BuildingInstance in g.buildings.values():
		if b.construction_ticks == 0:
			sample = b
			break
	var sample_data: BuildingData = BuildingCatalog.get_type(sample.type_id)
	var blockers: PackedStringArray = load("res://scripts/simulation/levels.gd").blockers(g, sample, sample_data, gs.land, gs.happiness)
	check.call("no level up without power and water (%s)" % ", ".join(blockers),
			"нет света" in blockers and "нет воды" in blockers)

	# Стройплощадке не нужны ни значок, ни счётчик.
	var site: BuildingInstance = null
	for b: BuildingInstance in g.buildings.values():
		if b.construction_ticks > 0:
			site = b
	if site == null:
		site = sample
		site.construction_ticks = 5
		badges.refresh()
	site.no_power_ticks = 0
	ev.sim_tick.emit()
	check.call("construction site counts no outage", site.no_power_ticks == 0)
	site.construction_ticks = 0

	# Долго без света — дома стоят: не пустеют от несчастья, не сносятся раньше срока.
	var before: int = g.buildings.size()
	var removed := 0
	var known: Dictionary[int, bool] = {}
	for b: BuildingInstance in g.buildings.values():
		known[b.id] = true
	for tick in 120:
		ev.sim_tick.emit()
	for id: int in known:
		if not g.buildings.has(id): removed += 1
	print("after 120 ticks: buildings %d -> %d, removed %d" % [before, g.buildings.size(), removed])
	check.call("no houses lost before the deadline", removed == 0)

	# Срок вышел — дом пустеет (Decay), зона остаётся.
	var victim: BuildingInstance = null
	for b: BuildingInstance in g.buildings.values():
		if b.construction_ticks == 0 and BuildingCatalog.get_type(b.type_id).zone == CityGrid.Zone.RESIDENTIAL:
			victim = b
			break
	var victim_id: int = victim.id
	var victim_cell: Vector2i = victim.cell
	victim.no_power_ticks = load("res://scripts/simulation/decay.gd").NO_UTILITY_TICKS - 1
	ev.sim_tick.emit()
	check.call("abandoned after the deadline", g.buildings.has(victim_id) and victim.abandoned
			and g.get_zone(victim_cell) == CityGrid.Zone.RESIDENTIAL)

	# ТЭЦ и водокачка у дороги — значки пропадают.
	g.place_building(&"power_plant_01", Vector2i(46, 29), 2, true)
	g.place_building(&"power_plant_01", Vector2i(47, 29), 2, true)
	g.place_building(&"water_tower_01", Vector2i(48, 29), 2, true)
	g.place_building(&"water_tower_01", Vector2i(49, 29), 2, true)
	var stations: Array[Vector2i] = [Vector2i(46, 29), Vector2i(47, 29), Vector2i(48, 29), Vector2i(49, 29)]
	ev.cells_changed.emit(stations)
	var u = gs.utilities
	print("power %d/%d water %d/%d badges %s" % [u.power_use, u.power_supply, u.water_use, u.water_supply, badges.counts()])
	check.call("badges gone with power and water", badges.counts() == Vector2i.ZERO and u.unpowered_count == 0)

	# Свет есть, воды нет (водокачки снесены) — значок только с каплей, один, по центру.
	for b: BuildingInstance in g.buildings.values().duplicate():
		if b.type_id == &"water_tower_01":
			g.remove_building(b.id)
	var towers: Array[Vector2i] = [Vector2i(48, 29), Vector2i(49, 29)]
	ev.cells_changed.emit(towers)
	var water_only: Vector2i = badges.counts()
	check.call("only water badges (%s)" % water_only, water_only.x == 0 and water_only.y > 0)
	var single := true
	for i: int in badges._water.multimesh.instance_count:
		if not is_equal_approx(badges._water.multimesh.get_instance_custom_data(i).g, 0.5): single = false
	check.call("single badge stays centered", single)
	# Значок над крышей, а не в доме.
	var top: float = badges._water.multimesh.get_instance_transform(0).origin.y
	check.call("badge above the roof (%.2f m)" % top, top > 1.0)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
