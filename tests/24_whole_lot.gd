extends SceneTree
## Участок застраивается одним домом во весь участок (спрос размер не режет, свет не нужен).
## Только жильё, участок которого частью в дыму, встаёт поменьше на чистой части; остаток делится заново.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	await process_frame

	check.call("no demand size cap", not GR.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "max_cells"))

	# Улица по y = 10, жилой участок к северу (фасад — юг, dir 2).
	var make := func(lot_rect: Rect2i, power: int) -> Array:
		var g := CityGrid.new(32)
		for x in range(2, 30): g.set_road(Vector2i(x, 10))
		for y in range(lot_rect.position.y, lot_rect.end.y):
			for x in range(lot_rect.position.x, lot_rect.end.x):
				g.set_zone(Vector2i(x, y), CityGrid.Zone.RESIDENTIAL)
		g.add_lot(lot_rect, 2)
		var net := RoadNetwork.new()
		net.update(g)
		var util := Utilities.new()
		util.spare_power[net.component_of[Vector2i(5, 10)]] = power
		util.spare_water[net.component_of[Vector2i(5, 10)]] = 100000
		return [g, net, util]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3

	# Участки 5×1 и 3×2 — один дом во весь участок, участок не делится (раньше слабый спрос дробил его).
	for lot_rect: Rect2i in [Rect2i(5, 9, 5, 1), Rect2i(5, 8, 3, 2)]:
		for k in 5:
			var s: Array = make.call(lot_rect, 100000)
			var c: Vector2i = GR.grow_one(s[0], CityGrid.Zone.RESIDENTIAL, rng, s[1], s[2], null)
			var b: BuildingInstance = s[0].get_building_at(c) if c != CityGrid.NO_CELL else null
			var ok: bool = b != null and Rect2i(b.cell, b.size) == lot_rect and s[0].lots.size() == 1
			if not ok or k == 4:
				check.call("one house on the whole %dx%d lot" % [lot_rect.size.x, lot_rect.size.y], ok)
				break

	# Света не хватает — дом всё равно во весь участок, но без света (значок над крышей).
	var s3: Array = make.call(Rect2i(5, 9, 5, 1), 1)
	var c3: Vector2i = GR.grow_one(s3[0], CityGrid.Zone.RESIDENTIAL, rng, s3[1], s3[2], null)
	var b3: BuildingInstance = s3[0].get_building_at(c3) if c3 != CityGrid.NO_CELL else null
	check.call("full house without power", b3 != null and b3.size == Vector2i(5, 1) and not b3.powered
			and b3.has_water and s3[2].spare_power[s3[1].component_of[Vector2i(5, 10)]] == 1)

	# Участок 3×2: у фасада (y = 9) грязно — дом встаёт глубже (y = 8), остаток — снова участки.
	var s4: Array = make.call(Rect2i(5, 8, 3, 2), 100000)
	var g4: CityGrid = s4[0]
	var land = LV.new()
	land.pollution.resize(g4.size * g4.size)
	land.pollution.fill(0)
	for x in range(5, 8):
		land.pollution[g4.index_of(Vector2i(x, 9))] = 70
	var c4: Vector2i = GR.grow_one(g4, CityGrid.Zone.RESIDENTIAL, rng, s4[1], s4[2], land)
	var b4: BuildingInstance = g4.get_building_at(c4) if c4 != CityGrid.NO_CELL else null
	var clean := b4 != null
	if b4 != null:
		for cell in b4.cells():
			if cell.y == 9: clean = false
	check.call("house on the clean part of a dirty lot", clean)
	var covered := 0
	for lot: CityGrid.Lot in g4.lots.values():
		covered += lot.rect.size.x * lot.rect.size.y
	check.call("rest of dirty lot re-planned (%d cells)" % covered, covered == 6)
	# Всё в грязи — не растёт ничего.
	for x in range(5, 8):
		land.pollution[g4.index_of(Vector2i(x, 8))] = 70
	var c5: Vector2i = GR.grow_one(g4, CityGrid.Zone.RESIDENTIAL, rng, s4[1], s4[2], land)
	check.call("no house where all is dirty", c5 == CityGrid.NO_CELL)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
