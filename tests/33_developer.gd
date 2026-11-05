extends SceneTree
## Застройщик по месту (переделка роста, Р1–Р2): полосы зон глубиной 4 у каждой улицы, красить можно
## только полосу; застройщик ставит дом у улицы фасадом к ней на участок во всю глубину полосы, позади —
## двор. Все дома смотрят на свою улицу, ширина — по спросу, кварталы заполняются; двор живёт с домом
## (снос по двору, перекраска, дорога, служба); жильё не встаёт в грязи; участки сохраняются, пустые
## старые — отбрасываются; дворы видны (заборы, парковки, контейнеры). Снимок — tests/out/developer.png.

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
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var grow := func(gg: CityGrid, zone: CityGrid.Zone, times: int, demand: float, seed: int, land = null) -> void:
		var net := RoadNetwork.new()
		net.update(gg)
		var util := Utilities.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for i in times:
			GR.grow_one(gg, zone, rng, net, util, land, demand)
	var zone_rect := func(gg: CityGrid, rect: Rect2i, zone: CityGrid.Zone) -> void:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				gg.set_zone(Vector2i(x, y), zone)
	# Каждый дом зоны смотрит на улицу всем фасадом; участок — дом у фасада и двор за ним.
	var faces_street := func(gg: CityGrid) -> bool:
		for b: BuildingInstance in gg.buildings.values():
			if BuildingCatalog.get_type(b.type_id).zone == CityGrid.Zone.NONE: continue
			for c in b.front_cells():
				if not gg.is_access_road(c + CityGrid.NEIGHBORS[b.orientation]): return false
		return true
	var lots_ok := func(gg: CityGrid) -> bool:
		for lot: CityGrid.Lot in gg.lots.values():
			var b: BuildingInstance = gg.building_on_lot(lot)
			if b == null or lot.dir != b.orientation or not lot.rect.encloses(Rect2i(b.cell, b.size)): return false
			if BuildingInstance.edge_cells(lot.rect.position, lot.rect.size, lot.dir) != b.front_cells(): return false
		return true

	# --- Р1: полосы ---
	var g := CityGrid.new(48)
	for x in range(2, 41): g.set_road(Vector2i(x, 20))
	check.call("strip at the road", g.get_strip_dir(Vector2i(10, 19)) == 2 and g.get_strip_depth(Vector2i(10, 19)) == 1
			and g.get_strip_dir(Vector2i(10, 21)) == 0)
	check.call("strip depth 4", g.get_strip_depth(Vector2i(10, 16)) == 4 and not g.in_strip(Vector2i(10, 15)))
	check.call("zone only on the strip", g.can_zone(Vector2i(10, 16), CityGrid.Zone.RESIDENTIAL)
			and not g.can_zone(Vector2i(10, 15), CityGrid.Zone.RESIDENTIAL))
	g.set_zone(Vector2i(10, 16), CityGrid.Zone.RESIDENTIAL)
	g.remove_road(Vector2i(10, 20))
	check.call("strip gone with the road", not g.in_strip(Vector2i(10, 19)) and not g.in_strip(Vector2i(10, 16))
			and g.in_strip(Vector2i(11, 19)))
	check.call("dezone anywhere, zone stays without strip", g.get_zone(Vector2i(10, 16)) == CityGrid.Zone.RESIDENTIAL
			and g.can_zone(Vector2i(10, 16), CityGrid.Zone.NONE))
	g.set_road(Vector2i(10, 20))
	# Шоссе не даёт полосы и загораживает; вода обрывает луч.
	for x in range(2, 41): g.set_road(Vector2i(x, 30), RoadTypes.Type.HIGHWAY)
	check.call("no strip from highway", not g.in_strip(Vector2i(10, 29)) and not g.in_strip(Vector2i(10, 31)))
	g.water[g.index_of(Vector2i(10, 18))] = 1
	g.rebuild_caches()
	check.call("water stops strip", g.in_strip(Vector2i(10, 19)) and not g.in_strip(Vector2i(10, 17)))
	var dirs_before: PackedByteArray = g.strip_dir.duplicate()
	g.rebuild_strips()
	check.call("incremental strips = full rebuild", dirs_before == g.strip_dir)

	# --- Р2: застройщик вдоль длинной улицы ---
	var gg := CityGrid.new(48)
	for x in range(2, 41): gg.set_road(Vector2i(x, 20))
	zone_rect.call(gg, Rect2i(3, 16, 34, 4), CityGrid.Zone.RESIDENTIAL)
	grow.call(gg, CityGrid.Zone.RESIDENTIAL, 120, 1.0, 7)
	var widths: Dictionary = {}
	var full_depth: bool = true
	for lot: CityGrid.Lot in gg.lots.values():
		widths[lot.building_size().x] = true
		if lot.building_size().y != 4: full_depth = false
	print("street: %d houses, widths %s" % [gg.buildings.size(), str(widths.keys())])
	check.call("every house faces its street", gg.buildings.size() >= 12 and faces_street.call(gg))
	check.call("lot = house at the front + yard behind, full depth", lots_ok.call(gg) and full_depth)
	check.call("several widths (%d)" % widths.size(), widths.size() >= 3)
	check.call("street filled, no free land left", gg.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].is_empty())
	var yard_cells: int = 0
	for y in range(16, 20):
		for x in range(3, 37):
			if gg.is_yard(Vector2i(x, y)): yard_cells += 1
	check.call("yards behind houses (%d cells)" % yard_cells, yard_cells > 34)
	# Спрос шире — дома шире.
	var avg_width := func(demand: float) -> float:
		var g2 := CityGrid.new(48)
		for x in range(2, 41): g2.set_road(Vector2i(x, 20))
		zone_rect.call(g2, Rect2i(3, 16, 34, 4), CityGrid.Zone.COMMERCIAL)
		grow.call(g2, CityGrid.Zone.COMMERCIAL, 120, demand, 3)
		var sum: float = 0.0
		for lot: CityGrid.Lot in g2.lots.values(): sum += lot.building_size().x
		return sum / maxf(1.0, g2.lots.size())
	var w_low: float = avg_width.call(0.0)
	var w_high: float = avg_width.call(1.0)
	check.call("higher demand → wider (%.2f < %.2f)" % [w_low, w_high], w_low < w_high)

	# Квартал 9×9 между четырьмя улицами: середина не размечается, квартал заполняется, все лицом к улице.
	var gb := CityGrid.new(48)
	for i in range(10, 41):
		gb.set_road(Vector2i(20, i)); gb.set_road(Vector2i(30, i))
		gb.set_road(Vector2i(i, 20)); gb.set_road(Vector2i(i, 30))
	zone_rect.call(gb, Rect2i(21, 21, 9, 9), CityGrid.Zone.RESIDENTIAL)
	var zoned: int = 0
	for y in range(21, 30):
		for x in range(21, 30):
			if gb.get_zone(Vector2i(x, y)) != CityGrid.Zone.NONE: zoned += 1
	check.call("block: centre not zoned (%d of 81)" % zoned, zoned == 80 and gb.get_zone(Vector2i(25, 25)) == CityGrid.Zone.NONE)
	grow.call(gb, CityGrid.Zone.RESIDENTIAL, 200, 0.6, 11)
	var orphans: int = gb.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].size()
	print("block: %d houses, %d free cells left" % [gb.buildings.size(), orphans])
	check.call("block: all face a street", faces_street.call(gb) and lots_ok.call(gb))
	check.call("block: filled (free %d)" % orphans, orphans <= 10)

	# --- Жизнь участка ---
	var lot0: CityGrid.Lot = gg.get_lot(Vector2i(10, 19))
	var house: BuildingInstance = gg.building_on_lot(lot0)
	var yard: Vector2i = lot0.rect.position
	for c in lot0.cells():
		if gg.is_yard(c): yard = c
	check.call("yard belongs to its house", gg.get_building_or_yard(yard) == house and gg.get_building_at(yard) == null)
	gg.bulldoze(yard)
	check.call("bulldoze yard removes house and lot", not gg.buildings.has(house.id) and gg.get_lot(yard) == null
			and gg.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].has(yard))
	grow.call(gg, CityGrid.Zone.RESIDENTIAL, 30, 1.0, 8)
	var lot1: CityGrid.Lot = gg.get_lot(Vector2i(20, 19))
	var house1: BuildingInstance = gg.building_on_lot(lot1)
	for c in lot1.cells():
		if gg.is_yard(c): yard = c
	gg.set_zone(yard, CityGrid.Zone.NONE)
	check.call("dezone yard: lot gone, house stays", gg.get_lot(house1.cell) == null and gg.buildings.has(house1.id))
	var lot2: CityGrid.Lot = gg.get_lot(Vector2i(30, 19))
	var house2: BuildingInstance = gg.building_on_lot(lot2)
	for c in lot2.cells():
		gg.set_zone(c, CityGrid.Zone.RESIDENTIAL_HIGH)
	check.call("density change keeps the lot", gg.get_lot(house2.cell) == lot2)
	var lot3: CityGrid.Lot = gg.get_lot(Vector2i(4, 19))
	var house3: BuildingInstance = gg.building_on_lot(lot3)
	for c in lot3.cells():
		if gg.is_yard(c): yard = c
	gg.set_road(yard)
	check.call("road on yard: lot gone, house stays", gg.get_lot(house3.cell) == null and gg.buildings.has(house3.id))

	# --- Жильё не встаёт в грязи ---
	var gp := CityGrid.new(48)
	for x in range(2, 41): gp.set_road(Vector2i(x, 20))
	zone_rect.call(gp, Rect2i(3, 16, 34, 4), CityGrid.Zone.RESIDENTIAL)
	var land = LV.new()
	# PackedByteArray копируется при передаче — заполняем каждое поле напрямую.
	land.pollution.resize(gp.size * gp.size)
	land.land_value.resize(gp.size * gp.size)
	land.land_value.fill(0)
	land.pollution.fill(0)
	for x in range(3, 15):
		land.pollution[gp.index_of(Vector2i(x, 19))] = 70
	grow.call(gp, CityGrid.Zone.RESIDENTIAL, 80, 1.0, 5, land)
	var dirty_house: bool = false
	for b: BuildingInstance in gp.buildings.values():
		for c in b.front_cells():
			if c.x < 15: dirty_house = true
	check.call("no homes in smog, clean part built (%d)" % gp.buildings.size(), not dirty_house and gp.buildings.size() >= 4)

	# --- Сохранение ---
	var d: Dictionary = CS.to_dict(gg, "x", 100, 9, 5, 0, 0)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	var same_yards: bool = back.ok
	for y in range(16, 20):
		for x in range(3, 37):
			if back.ok and back.grid.is_yard(Vector2i(x, y)) != gg.is_yard(Vector2i(x, y)): same_yards = false
	check.call("lots and yards saved", back.ok and back.grid.lots.size() == gg.lots.size() and same_yards
			and back.grid.in_strip(Vector2i(10, 19)))
	# Старое сохранение: участок без дома (нарезала разметка) отбрасывается.
	var free_cell: Vector2i = Vector2i(-1, -1)
	for c: Vector2i in gg.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL]:
		free_cell = c
	if free_cell.x < 0:
		gg.remove_building(gg.buildings.values()[0].id)
		for c: Vector2i in gg.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL]: free_cell = c
		d = CS.to_dict(gg, "x", 100, 9, 5, 0, 0)
	d.grid.lots.append([free_cell.x, free_cell.y, 1, 1, 2])
	back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("empty old lot dropped", back.ok and back.grid.get_lot(free_cell) == null
			and back.grid.zoned_empty_cells[CityGrid.Zone.RESIDENTIAL].has(free_cell))

	# --- Вид: сетка полосы с инструментом зоны, дворы ---
	var tool: Node = main.get_node("BuildTool")
	var zones: Node = main.get_node("ZoneVisualizer")
	var yards: Node = main.get_node("YardVisualizer")
	var drag := func(m: int, a: Vector2i, b: Vector2i) -> void:
		tool._set_mode(m); tool._dragging = true; tool._drag_start = a
		tool._update_drag(b); tool._apply(); tool._end_drag()
	var city: CityGrid = gs.grid
	gs.money = 1000000
	gs.rank = 3
	drag.call(tool.Mode.ROAD, Vector2i(10, 30), Vector2i(50, 30))
	drag.call(tool.Mode.ROAD, Vector2i(30, 20), Vector2i(30, 40))
	tool._set_mode(tool.Mode.ZONE_R)
	var strip_shown: bool = zones.multimesh.get_instance_color(city.index_of(Vector2i(14, 29))).a > 0.0
	tool._set_mode(tool.Mode.NONE)
	var strip_hidden: bool = zones.multimesh.get_instance_color(city.index_of(Vector2i(14, 29))).a == 0.0
	check.call("strip grid shown only with zone tool", strip_shown and strip_hidden)
	drag.call(tool.Mode.ZONE_R, Vector2i(11, 26), Vector2i(29, 29))
	check.call("zone tool paints only the strip", city.get_zone(Vector2i(14, 26)) == CityGrid.Zone.RESIDENTIAL
			and city.get_zone(Vector2i(14, 25)) == CityGrid.Zone.NONE)
	drag.call(tool.Mode.ZONE_C, Vector2i(11, 31), Vector2i(29, 34))
	drag.call(tool.Mode.ZONE_I, Vector2i(31, 31), Vector2i(49, 34))
	drag.call(tool.Mode.ZONE_R_HIGH, Vector2i(31, 26), Vector2i(49, 29))
	var net: RoadNetwork = gs.network
	net.update(city)
	var util := Utilities.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 60:
		for z in [CityGrid.Zone.RESIDENTIAL, CityGrid.Zone.COMMERCIAL, CityGrid.Zone.INDUSTRIAL, CityGrid.Zone.RESIDENTIAL_HIGH]:
			GR.grow_one(city, z, rng, net, util, null, 0.7)
	var all_cells: Array[Vector2i] = []
	for lot: CityGrid.Lot in city.lots.values(): all_cells.append_array(lot.cells())
	ev.cells_changed.emit(all_cells)
	var counts: Dictionary = yards.counts()
	print("yards: ", counts)
	check.call("yards drawn: fences, trees, parking, containers", counts.fence > 0 and counts.trees > 0
			and counts.stripes > 0 and counts.containers > 0)
	var yard_cell: Vector2i = Vector2i(-1, -1)
	for lot: CityGrid.Lot in city.lots.values():
		for c in lot.cells():
			if city.is_yard(c) and city.get_zone(c) == CityGrid.Zone.COMMERCIAL: yard_cell = c
	check.call("parking tint under shop yards", yard_cell.x >= 0
			and zones.multimesh.get_instance_color(city.index_of(yard_cell))
					== zones.get_script().get_script_constant_map()["YARD_PARKING"])
	# «Инфо» по двору — карточка дома.
	ev.cell_inspected.emit(yard_cell)
	await process_frame
	var text := ""
	for label in main.get_node("HUD").find_children("*", "Label", true, false):
		text += label.text + "|"
	check.call("info on yard shows the house", text.contains("двор"))

	tool._set_mode(tool.Mode.NONE)
	main.get_node("HUD").hide()
	for i in 10: await process_frame
	var cam: Node3D = main.get_node("RTSCamera")
	cam.position = Vector3(60, 0, 60)
	cam.rotation.y = deg_to_rad(20.0)
	cam._target_distance = 20.0
	cam._distance = 20.0
	cam._apply_distance()
	for i in 30: await process_frame
	root.get_texture().get_image().save_png("res://tests/out/developer.png")

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
