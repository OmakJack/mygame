extends SceneTree
## Темп роста (застройщик по месту, Р5): попыток роста за тик — от населения, но тик не перерастает спрос
## (запас = спрос × шкала); шкалы и буферы спроса растут с городом; подсказка, когда спросу не хватает земли;
## слои земли на тике — раз в LAND_PERIOD и не вместе с трафиком; счастье без служб не перебирает город.

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	# Классы, что зависят от автозагрузок, — через load() (в --script их имена не видны).
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var HN: GDScript = load("res://scripts/ui/hints.gd")
	var HP: GDScript = load("res://scripts/simulation/happiness.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var sim: Node = main.get_node("Simulation")
	var tool: Node = main.get_node("BuildTool")
	var DM: GDScript = load("res://scripts/simulation/demand.gd")
	var tax: int = gs.tax_rate

	# --- Шкалы и буферы спроса ---
	check.call("scale: small city — old numbers",
			DM.scale_of(CityGrid.Zone.RESIDENTIAL, 100) == DM.R_SCALE
			and DM.scale_of(CityGrid.Zone.INDUSTRIAL, 100) == DM.I_SCALE
			and DM.scale_of(CityGrid.Zone.COMMERCIAL, 100) == DM.C_SCALE)
	check.call("scale: city of 2000 — R 100, I 70, C 30",
			is_equal_approx(DM.scale_of(CityGrid.Zone.RESIDENTIAL, 2000), 100.0)
			and is_equal_approx(DM.scale_of(CityGrid.Zone.INDUSTRIAL, 2000), 70.0)
			and is_equal_approx(DM.scale_of(CityGrid.Zone.COMMERCIAL, 2000), 30.0))
	check.call("demand: empty city unchanged (7/17)",
			is_equal_approx(DM.residential(0, 0, 0, tax), DM.R_BUFFER / DM.R_SCALE))
	var big: float = DM.residential(2000, 600, 1400, tax)
	check.call("demand: big city with jobs for all still wants people (%.2f)" % big, is_equal_approx(big, 0.4))
	var after: float = DM.residential(2040, 600, 1400, tax)
	check.call("demand: 40 more people in a city of 2000 move R by ~0.4, not 2 (%.2f → %.2f)" % [big, after],
			big - after > 0.35 and big - after < 0.45)
	check.call("demand: industry of a big city keeps a buffer (%.2f)" % DM.industrial(2000, 1400, tax),
			is_equal_approx(DM.industrial(2000, 1400, tax), 0.4))

	# --- Попыток роста за тик ---
	check.call("tries: 1 / 1 / 2 / 4 / 5 / 5",
			sim.growth_tries(0) == 1 and sim.growth_tries(249) == 1 and sim.growth_tries(250) == 2
			and sim.growth_tries(999) == 4 and sim.growth_tries(1000) == 5 and sim.growth_tries(100000) == 5)

	# Город: улицы через 10 клеток, жильё — кварталы 9×9, свет и вода у восточной улицы.
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var g: CityGrid = gs.grid
	gs.money = 1000000
	for k in range(0, 5):
		drag.call(tool.Mode.ROAD, Vector2i(4, 4 + k * 10), Vector2i(44, 4 + k * 10))
		drag.call(tool.Mode.ROAD, Vector2i(4 + k * 10, 4), Vector2i(4 + k * 10, 44))
	for bx in 3:
		for by in 3:
			var a := Vector2i(5 + bx * 10, 5 + by * 10)
			drag.call(tool.Mode.ZONE_R, a, a + Vector2i(8, 8))
	for y in range(5, 15): g.place_building(&"power_plant_01", Vector2i(45, y), 0, true)
	for y in range(16, 26): g.place_building(&"water_tower_01", Vector2i(45, y), 0, true)
	ev.grid_reset.emit()
	var homes := func() -> Array:
		return g.buildings.values().filter(func(b: BuildingInstance) -> bool:
			return BuildingCatalog.get_type(b.type_id).zone == CityGrid.Zone.RESIDENTIAL)
	var people_of := func(list: Array) -> int:
		var sum := 0
		for b: BuildingInstance in list: sum += BuildingCatalog.get_type(b.type_id).population
		return sum

	# --- Малый город: одна попытка на зону ---
	gs.rng.seed = 5
	var most_small := 0
	for i in 10:
		gs.population = 0
		gs.demand_r = 1.0
		gs.demand_c = -1.0
		gs.demand_i = -1.0
		var before: int = homes.call().size()
		var changed: Array[Vector2i] = []
		sim._grow(g, changed)
		most_small = maxi(most_small, homes.call().size() - before)
	check.call("small city: at most 1 house per tick (%d)" % most_small, most_small == 1)

	# --- Большой город: несколько домов за тик, но не больше запаса спроса ---
	var most_big := 0
	var over := 0
	for i in 12:
		gs.population = 1000
		gs.demand_r = 0.3 if i % 2 == 0 else 1.0
		gs.demand_c = -1.0
		gs.demand_i = -1.0
		var room: float = gs.demand_r * DM.scale_of(CityGrid.Zone.RESIDENTIAL, 1000)
		var old: Array = homes.call()
		var changed: Array[Vector2i] = []
		sim._grow(g, changed)
		var added: Array = homes.call().filter(func(b: BuildingInstance) -> bool: return not old.has(b))
		most_big = maxi(most_big, added.size())
		# Запас кончается на последнем доме: без него стройки тика меньше запаса.
		if added.size() > 1:
			var last: BuildingInstance = added[0]
			for b: BuildingInstance in added:
				if b.id > last.id: last = b
			if people_of.call(added) - people_of.call([last]) >= room:
				over += 1
	check.call("big city: several houses in one tick (up to %d)" % most_big, most_big >= 2 and most_big <= 5)
	check.call("big city: a tick never builds past the demand room (%d over)" % over, over == 0)

	# --- Общий context попыток: новый дом виден следующей ---
	var ctx: Dictionary = {}
	var cell: Vector2i = GR.grow_one(g, CityGrid.Zone.RESIDENTIAL, gs.rng, gs.network, gs.utilities, gs.land, 0.5,
			gs.traffic, ctx)
	var seen: bool = false
	if cell != CityGrid.NO_CELL:
		for home: Array in ctx.get("homes", []):
			if home[0] == g.get_building_at(cell).cell: seen = true
	check.call("grow_one: fills the shared context and adds the new house to it", cell != CityGrid.NO_CELL and seen)

	# --- Подсказка: спросу нужна земля ---
	ev.cells_changed.emit([] as Array[Vector2i])
	gs.population = 300
	gs.demand_r = 0.2
	gs.demand_c = 0.8
	gs.demand_i = 0.1
	var hints: Array[String] = HN.build()
	var has := func(list: Array[String], prefix: String) -> bool:
		return list.any(func(t: String) -> bool: return t.begins_with(prefix))
	check.call("hint: shops want land and there is no commercial zone", has.call(hints, "Магазинам нужна земля: спрос 80%"))
	check.call("hint: no land hint for low demand", not has.call(hints, "Заводам нужна земля"))
	gs.demand_r = 0.9
	hints = HN.build()
	check.call("hint: homes with free frontage — no land hint",
			HN.has_free_frontage(g, gs.network, CityGrid.Zone.RESIDENTIAL) and not has.call(hints, "Жилью нужна земля"))
	check.call("frontage: none for industry (no zone)",
			not HN.has_free_frontage(g, gs.network, CityGrid.Zone.INDUSTRIAL))

	# --- Слои земли на тике: раз в LAND_PERIOD и не в тик трафика; вне тика — сразу ---
	# Заводы и магазины — чтобы город рос (жилью нужна работа).
	drag.call(tool.Mode.ZONE_I, Vector2i(35, 5), Vector2i(43, 13))
	drag.call(tool.Mode.ZONE_C, Vector2i(35, 15), Vector2i(43, 23))
	gs.rng.seed = 11
	var land_ticks: Array[int] = []
	var together := 0
	for t in 30:
		var land_before: LandValue = gs.land
		var traffic_before: Traffic = gs.traffic
		ev.sim_tick.emit()
		var land_new: bool = gs.land != land_before
		if land_new: land_ticks.append(t)
		if land_new and gs.traffic != traffic_before: together += 1
	var gaps_ok: bool = land_ticks.size() >= 2
	for i in range(1, land_ticks.size()):
		if land_ticks[i] - land_ticks[i - 1] < sim.LAND_PERIOD: gaps_ok = false
	check.call("land on ticks: every %d+ ticks %s" % [sim.LAND_PERIOD, land_ticks], gaps_ok)
	check.call("land on ticks: never in the traffic tick (%d)" % together, together == 0)
	var land_paused: LandValue = gs.land
	var park: int = g.place_building(&"park_square", Vector2i(36, 40), 0, true)
	ev.cells_changed.emit([Vector2i(36, 40)] as Array[Vector2i])
	check.call("land on pause: right after a change", park != -1 and gs.land != land_paused)

	# --- Счастье: пустой список служб — «служб нет», null — посчитать ---
	var school: int = g.place_building(&"school_01", Vector2i(3, 6), 0, true)
	ev.cells_changed.emit([Vector2i(3, 6)] as Array[Vector2i])
	var near: BuildingInstance = null
	for b: BuildingInstance in homes.call():
		if b.cell.x <= 8 and b.cell.y <= 8 and not b.abandoned: near = b
	if near != null:
		var data: BuildingData = BuildingCatalog.get_type(near.type_id)
		var auto: Array[Array] = HP.factors(g, near, data, gs.land, gs.traffic, tax)
		var none: Array[Array] = HP.factors(g, near, data, gs.land, gs.traffic, tax, [])
		check.call("happiness: services found when not passed (%s), none for []" % auto[0][1],
				school != -1 and auto[0][1] > 0.0 and none[0][1] == 0.0)
	else:
		check.call("happiness: a house near the school", false)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
