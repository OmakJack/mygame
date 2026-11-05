extends SceneTree
## Многоклеточные здания (Argon): участок занимает все клетки, снос целиком, поворот,
## сохранение, рост крупных участков фасадом к улице, повышение с тем же размером, вид.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Размеры есть у всех зон и уровней.
	var sizes := {}
	for d: BuildingData in BuildingCatalog.all_types():
		if d.grows: sizes[d.area()] = true
	check.call("areas 1..7 exist %s" % str(sizes.keys()), sizes.has(1) and sizes.has(5) and sizes.has(6) and sizes.has(7))

	# Постановка, занятость, поворот.
	var g := CityGrid.new(32)
	var data: BuildingData = BuildingCatalog.get_type(&"res_panel_7x1_1")
	check.call("7x1 type", data != null and data.size == Vector2i(7, 1) and data.population == 20 * 7)
	var id: int = g.place_building(&"res_panel_7x1_1", Vector2i(5, 5), 0)
	var b: BuildingInstance = g.buildings[id]
	check.call("occupies 7 cells", b.cells().size() == 7 and g.get_building_at(Vector2i(11, 5)) == b and g.get_building_at(Vector2i(12, 5)) == null)
	check.call("no overlap", g.place_building(&"res_small_01", Vector2i(8, 5), 0) == -1)
	var id_e: int = g.place_building(&"res_panel_7x1_1", Vector2i(20, 10), 1)
	check.call("rotated E is 1x7", g.buildings[id_e].size == Vector2i(1, 7) and g.get_building_at(Vector2i(20, 16)) != null)
	check.call("bulldoze one cell removes all", g.bulldoze(Vector2i(9, 5)) and g.get_building_at(Vector2i(5, 5)) == null and g.can_place_building(Vector2i(5, 5), Vector2i(7, 1)))

	# Сохранение.
	var d2: Dictionary = CS.to_dict(g, "x", 100, 9, 5, 0, 0)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d2)))
	check.call("saved with rotation", back.ok and back.grid.get_building_at(Vector2i(20, 16)) != null and back.grid.get_building_at(Vector2i(20, 16)).size == Vector2i(1, 7))

	# Рост (застройщик): длинная полоса многоэтажек вдоль улицы при сильном спросе — бывают дома
	# в 4–7 клеток, все фасадом к дороге.
	var big := 0
	var total := 0
	var facing_road := true
	for run in 12:
		var gg := CityGrid.new(32)
		for x in range(2, 30): gg.set_road(Vector2i(x, 10))
		for x in range(3, 29):
			gg.set_zone(Vector2i(x, 9), CityGrid.Zone.RESIDENTIAL_HIGH)
		var net := RoadNetwork.new()
		net.update(gg)
		var util := Utilities.new()
		util.spare_power[net.component_of[Vector2i(5, 10)]] = 100000
		util.spare_water[net.component_of[Vector2i(5, 10)]] = 100000
		var rng := RandomNumberGenerator.new()
		rng.seed = run
		for k in 6:
			var cell: Vector2i = GR.grow_one(gg, CityGrid.Zone.RESIDENTIAL_HIGH, rng, net, util, null, 1.0)
			if cell == CityGrid.NO_CELL: continue
			var bb: BuildingInstance = gg.get_building_at(cell)
			total += 1
			if bb.size.x * bb.size.y >= 4: big += 1
			for fc in bb.front_cells():
				if not gg.is_road(fc + CityGrid.NEIGHBORS[bb.orientation]): facing_road = false
	check.call("big lots grow (%d of %d)" % [big, total], big > 0)
	check.call("lots face the road", facing_road)

	# Повышение уровня — тот же размер участка.
	var up: Array[BuildingData] = BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL_HIGH, 2, Vector2i(7, 1))
	check.call("level 2 of same size", not up.is_empty() and up[0].size == Vector2i(7, 1))

	# Вид: здание нарисовано один раз, клетки — все.
	var city: CityGrid = gs.grid
	for x in range(10, 25): city.set_road(Vector2i(x, 20))
	var vid: int = city.place_building(&"com_mall_3x2_1", Vector2i(12, 18), 2)
	ev.cells_changed.emit(city.buildings[vid].cells())
	var bv: Node = main.get_node("BuildingVisualizer")
	check.call("drawn on all cells", bv.get_cell_item(Vector3i(14, 0, 19)) != -1 and bv.get_used_cells().size() == 6)
	# Семьи в карточке «Инфо» (2026-11-01): семья — 3 человека, не меньше одной.
	var IP: GDScript = load("res://scripts/ui/info_panel.gd")
	check.call("families", LevelStats.families(3) == 1 and LevelStats.families(9) == 3 and LevelStats.families(1) == 1
			and IP._families_text(1) == "1 семья" and IP._families_text(3) == "3 семьи" and IP._families_text(5) == "5 семей"
			and IP._families_text(12) == "12 семей" and IP._families_text(22) == "22 семьи")
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
