extends SceneTree
## Желанность места (застройщик по месту, Р3): жильё не встаёт там, где «счастье места» ниже
## Growth.MIN_HOME_MOOD (шум, дешёвая земля) или в дыму, и выбирает тихие места; промзона уходит от жилья;
## магазины тянутся к покупателям; «Почему здесь не строят» объясняет пустую клетку (карточка «Инфо»).

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
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	var HP: GDScript = load("res://scripts/simulation/happiness.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Улица по y = 20, жильё к северу. Слои земли — вручную: цена 25, без дыма и шума.
	var make := func(zone: CityGrid.Zone) -> Array:
		var g := CityGrid.new(48)
		for x in range(2, 46): g.set_road(Vector2i(x, 20))
		for y in range(16, 20):
			for x in range(3, 45):
				g.set_zone(Vector2i(x, y), zone)
		var land = LV.new()
		land.size = g.size
		land.pollution.resize(g.size * g.size)
		land.noise.resize(g.size * g.size)
		land.land_value.resize(g.size * g.size)
		land.pollution.fill(0)
		land.noise.fill(0)
		land.land_value.fill(25)
		var net := RoadNetwork.new()
		net.update(g)
		return [g, land, net]
	var grow := func(s: Array, zone: CityGrid.Zone, times: int, seed: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for i in times:
			GR.grow_one(s[0], zone, rng, s[2], Utilities.new(), s[1], 0.6)
	var demand_all: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 0.5,
			CityGrid.Zone.COMMERCIAL: 0.5, CityGrid.Zone.INDUSTRIAL: 0.5}

	# Шумная половина улицы (x < 24): шум 80 — «место» ниже 30, жильё там не строят.
	var s1: Array = make.call(CityGrid.Zone.RESIDENTIAL)
	var g1: CityGrid = s1[0]
	for y in range(14, 21):
		for x in range(0, 24):
			s1[1].noise[g1.index_of(Vector2i(x, y))] = 80
	var noisy_cells: Array[Vector2i] = [Vector2i(10, 19)]
	var quiet_cells: Array[Vector2i] = [Vector2i(30, 19)]
	var ctx: Dictionary = GR.place_context(g1, null)
	var noisy_mood: int = HP.score_of(GR.home_factors(g1, noisy_cells, s1[1], ctx))
	var quiet_mood: int = HP.score_of(GR.home_factors(g1, quiet_cells, s1[1], ctx))
	check.call("noisy spot below the bar (%d < %d ≤ %d)" % [noisy_mood, GR.MIN_HOME_MOOD, quiet_mood],
			noisy_mood < GR.MIN_HOME_MOOD and quiet_mood >= GR.MIN_HOME_MOOD)
	grow.call(s1, CityGrid.Zone.RESIDENTIAL, 60, 3)
	var on_noisy: int = 0
	for b: BuildingInstance in g1.buildings.values():
		if b.cell.x < 24: on_noisy += 1
	print("homes %d, on the noisy part %d" % [g1.buildings.size(), on_noisy])
	check.call("homes grow only on the quiet part", g1.buildings.size() >= 5 and on_noisy == 0)
	var why: PackedStringArray = GR.why_not(g1, Vector2i(10, 19), s1[2], s1[1], null, demand_all)
	check.call("why: noisy place (%s)" % ", ".join(why), why.size() == 1 and why[0].begins_with("место на")
			and why[0].contains("шум"))
	var no_demand: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: -0.1,
			CityGrid.Zone.COMMERCIAL: 0.5, CityGrid.Zone.INDUSTRIAL: 0.5}
	check.call("why: no demand", GR.why_not(g1, Vector2i(10, 19), s1[2], s1[1], null, no_demand).has("нет спроса"))
	# Дым: отдельная причина.
	for x in range(0, 8):
		s1[1].pollution[g1.index_of(Vector2i(x, 19))] = 70
	why = GR.why_not(g1, Vector2i(5, 19), s1[2], s1[1], null, demand_all)
	check.call("why: pollution (%s)" % ", ".join(why), why.size() == 1 and why[0].begins_with("загрязнение 70"))
	# Клетка в глубине: ждёт фасад; фасад занят — «нет выхода на улицу».
	check.call("why: deep cell waits for its front", GR.why_not(g1, Vector2i(10, 16), s1[2], s1[1], null, demand_all).size() == 1)
	var built: BuildingInstance = g1.buildings.values()[0]
	var lot: CityGrid.Lot = g1.get_lot(built.cell)
	var behind: Vector2i = Vector2i(-1, -1)
	for y in range(16, 20):
		var c := Vector2i(built.cell.x, y)
		if g1.get_lot(c) != lot and g1.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].has(c): behind = c
	if behind.x < 0:
		# Участок во всю глубину — за ним клеток нет; делаем мелкий участок вручную.
		g1.dissolve_lot(lot.id)
		g1.add_lot(Rect2i(built.cell, built.size), built.orientation)
		behind = Vector2i(built.cell.x, built.cell.y - 1)
	check.call("why: blocked from the street", GR.why_not(g1, behind, s1[2], s1[1], null, demand_all)
			== PackedStringArray(["нет выхода на улицу: между клеткой и дорогой занято"]))
	check.call("why: far from road", GR.why_not(g1, Vector2i(10, 30), s1[2], s1[1], null, demand_all).is_empty()
			and not g1.in_strip(Vector2i(10, 30)))
	g1.set_zone(Vector2i(10, 30), CityGrid.Zone.RESIDENTIAL)
	check.call("off-strip zone can't be painted", g1.get_zone(Vector2i(10, 30)) == CityGrid.Zone.NONE)

	# Промзона уходит от жилья: дома у x < 20 — заводы ставятся дальше.
	var s2: Array = make.call(CityGrid.Zone.INDUSTRIAL)
	var g2: CityGrid = s2[0]
	var home_type: BuildingData = BuildingCatalog.growable_types(CityGrid.Zone.RESIDENTIAL).filter(
			func(d: BuildingData) -> bool: return d.size == Vector2i.ONE)[0]
	for x in range(3, 20):
		if g2.get_building_at(Vector2i(x, 21)) == null:
			g2.set_zone(Vector2i(x, 21), CityGrid.Zone.RESIDENTIAL)
			g2.place_building(home_type.id, Vector2i(x, 21), 0)
	s2[2].update(g2)
	var ctx2: Dictionary = GR.place_context(g2, null)
	var near_cells: Array[Vector2i] = [Vector2i(10, 19), Vector2i(11, 19)]
	var far_cells: Array[Vector2i] = [Vector2i(35, 19), Vector2i(36, 19)]
	var near_score: float = GR.place_score(g2, CityGrid.Zone.INDUSTRIAL, near_cells, 2, s2[1], ctx2)[0]
	var far_score: float = GR.place_score(g2, CityGrid.Zone.INDUSTRIAL, far_cells, 2, s2[1], ctx2)[0]
	check.call("industry: homes nearby lower the score (%.1f < %.1f)" % [near_score, far_score], near_score + 5.0 < far_score)
	grow.call(s2, CityGrid.Zone.INDUSTRIAL, 4, 9)
	var near_homes: int = 0
	var factories: int = 0
	for b: BuildingInstance in g2.buildings.values():
		if BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.INDUSTRIAL: continue
		factories += 1
		if b.cell.x + b.size.x / 2 < 18: near_homes += 1
	check.call("industry grows away from homes (%d of %d near)" % [near_homes, factories], factories >= 3 and near_homes == 0)

	# Магазины тянутся к покупателям: дома у x > 30.
	var s3: Array = make.call(CityGrid.Zone.COMMERCIAL)
	var g3: CityGrid = s3[0]
	for x in range(30, 45):
		g3.set_zone(Vector2i(x, 21), CityGrid.Zone.RESIDENTIAL)
		g3.place_building(home_type.id, Vector2i(x, 21), 0)
	var ctx3: Dictionary = GR.place_context(g3, null)
	var shop_near: float = GR.place_score(g3, CityGrid.Zone.COMMERCIAL, far_cells, 2, s3[1], ctx3)[0]
	var shop_far: float = GR.place_score(g3, CityGrid.Zone.COMMERCIAL, near_cells, 2, s3[1], ctx3)[0]
	check.call("shops: customers raise the score (%.1f > %.1f)" % [shop_near, shop_far], shop_near > shop_far + 5.0)
	grow.call(s3, CityGrid.Zone.COMMERCIAL, 4, 5)
	var near_people: int = 0
	var shops: int = 0
	for b: BuildingInstance in g3.buildings.values():
		if BuildingCatalog.get_type(b.type_id).zone != CityGrid.Zone.COMMERCIAL: continue
		shops += 1
		if b.cell.x + b.size.x / 2 >= 25: near_people += 1
	check.call("shops grow near customers (%d of %d)" % [near_people, shops], shops >= 3 and near_people >= shops - 1)

	# «Инфо» пустой клетки жилья: место для жилья и почему не строят.
	var city: CityGrid = gs.grid
	gs.money = 100000
	for x in range(10, 40): city.set_road(Vector2i(x, 30))
	for x in range(12, 20): city.set_zone(Vector2i(x, 29), CityGrid.Zone.RESIDENTIAL)
	ev.grid_reset.emit()
	await process_frame
	ev.cell_inspected.emit(Vector2i(14, 29))
	await process_frame
	var text := ""
	for label in main.get_node("HUD").find_children("*", "Label", true, false):
		text += label.text + "|"
	check.call("info: place for homes", text.contains("Место для жилья") and text.contains("строят от 30"))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
