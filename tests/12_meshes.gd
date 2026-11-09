extends SceneTree
## Меши: склейка машин, доли типов, кто растёт, вывеска на крыше.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var fails: Array[String] = []
	var check := func(name: String, cond: bool) -> void:
		if not cond: fails.append(name)
	var BM: GDScript = load("res://scripts/grid/building_meshes.gd")

	# 1. Склейка по материалу: у машины — одна поверхность.
	var cars: Node = main.get_node("TrafficVisualizer")
	var surfaces_ok := true
	for layer in cars._layers:
		if layer.multimesh.mesh.get_surface_count() != 1: surfaces_ok = false
	check.call("car one surface", surfaces_ok and cars._layers.size() == 10)
	check.call("car no shadow", cars._layers[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# Доля полиции ≈ 0.25 / 9.25.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var police := 0
	for i in 20000:
		if rng.rand_weighted(cars._weights) == cars._layers.size() - 1: police += 1
	check.call("police share %.3f" % (police / 20000.0), absf(police / 20000.0 - 0.027) < 0.006)

	# 3. Рост: службы и многоэтажки не растут.
	var growable: Array = BuildingCatalog.growable_types(CityGrid.Zone.COMMERCIAL).map(func(d): return String(d.id))
	check.call("services not growing", not ("com_shop_c" in growable or "com_shop_h" in growable or "com_shop_n" in growable or "com_shop_f" in growable))
	check.call("small shops grow", "com_shop_e" in growable and "com_small_01" in growable)
	check.call("factory l not growing", not BuildingCatalog.get_type(&"ind_factory_l").grows)

	# 4. Вывеска на крыше: столбик школы (модель Kenney) начинается не выше крыши в точке крепления.
	var school: BuildingData = BuildingCatalog.get_type(&"school_01")
	var plain := ModelLoader.fitted(school.model, school.model_scale, school.model_turns, BM.FOOTPRINT)
	var signed: ArrayMesh = BM.mesh_for(school)
	var roof: float = BM._roof_height(plain, Vector2(0.0, -BM.FOOTPRINT * 0.25))
	var lowest_sign := INF
	for s in range(plain.get_surface_count(), signed.get_surface_count()):
		for v in signed.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			lowest_sign = minf(lowest_sign, v.y)
	check.call("sign on roof (%.2f vs roof %.2f)" % [lowest_sign, roof], absf(lowest_sign - roof) < 0.02)
	# Крест на вывеске добавляет поверхности (модели служб Argon — с эмблемами, без вывесок).
	var crossed: BuildingData = school.duplicate()
	crossed.sign_cross = true
	check.call("sign cross", BM._from_model(crossed).get_surface_count() > signed.get_surface_count())
	check.call("argon services without signs", BuildingCatalog.get_type(&"health_01").sign_color.a == 0.0
			and BuildingCatalog.get_type(&"fire_01").sign_color.a == 0.0)

	# 5. Дороги рисуются из кода по графу (RoadGeometry, с 2026-11-09; раньше — куски Kenney по маске).
	check.call("road piece from code", RoadGeometry.straight_piece(1, CityGrid.CELL_SIZE).get_surface_count() == 1)

	# 7. Деревья: есть; исчезают при зонировании и возвращаются при снятии зоны.
	var trees: Node = main.get_node("TreeVisualizer")
	var g: CityGrid = gs.grid
	var start: int = trees.tree_count()
	check.call("trees exist (%d)" % start, start > 500)
	# Найти свободную клетку с деревом: та, где шум выше порога.
	var target := Vector2i(-1, -1)
	for y in g.size:
		for x in g.size:
			if target.x < 0 and trees._noise.get_noise_2d(x, y) > trees.INSIDE_THRESHOLD + 0.2: target = Vector2i(x, y)
	g.set_road(Vector2i(target.x, clampi(target.y + 1, 0, 63)))
	g.set_zone(target, CityGrid.Zone.RESIDENTIAL)
	var changed: Array[Vector2i] = [target, Vector2i(target.x, clampi(target.y + 1, 0, 63))]
	ev.cells_changed.emit(changed)
	var after_zone: int = trees.tree_count()
	check.call("trees removed on zoning (%d -> %d)" % [start, after_zone], after_zone < start)
	g.set_zone(target, CityGrid.Zone.NONE)
	g.remove_road(Vector2i(target.x, clampi(target.y + 1, 0, 63)))
	ev.cells_changed.emit(changed)
	check.call("trees back", trees.tree_count() == start)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
