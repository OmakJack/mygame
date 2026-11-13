extends SceneTree
## Эффекты пака Argon (ParticleVisualizer): дым из труб по таблице манифеста и по мешу, печной дымок
## у части домов, пар кофейни, фонтан, листва и птицы в парках, пыль и сварка на стройке; без света
## и у брошенных — нет; на паузе время эффектов стоит; снос — облако пыли, повышение — салют.
## Снимки — tests/out/fx_industry.png, fx_town.png, fx_bursts.png.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.size = Vector2i(1600, 900)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	var sm: Node = root.get_node("SaveManager")
	var clock: Node = root.get_node("SimClock")
	clock.set_speed(0)
	var PV: GDScript = load("res://scripts/grid/particle_visualizer.gd")
	var BM: GDScript = load("res://scripts/grid/building_meshes.gd")
	var CAT: GDScript = load("res://scripts/data/building_catalog.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	sm.with_river = false
	sm.with_highway = false
	sm.new_city()
	await process_frame
	var fx: Node = main.get_node("ParticleVisualizer")
	check.call("all effect layers loaded (%d)" % fx._layers.size(), fx._layers.size() == PV.EFFECTS.size())
	var arrays: Array = fx._layers[&"fx_smoke_factory_heavy"].multimesh.mesh.surface_get_arrays(0)
	check.call("baked phase and seed kept", arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV2] != null)

	# Промзона к северу от улицы (фасадом на юг), городок — к югу.
	var g: CityGrid = gs.grid
	for x in range(4, 44): g.set_road(Vector2i(x, 30))
	var brick: int = g.place_building(&"ind_brick_workshop_1x1", Vector2i(5, 29), 2)
	var foundry: int = g.place_building(&"ind_red_foundry_3x1", Vector2i(7, 29), 2)
	var refinery: int = g.place_building(&"ind_refinery_complex_3x2", Vector2i(11, 28), 2)
	var dark: int = g.place_building(&"ind_brick_workshop_1x1", Vector2i(15, 29), 2)
	var ruin: int = g.place_building(&"ind_brick_workshop_1x1", Vector2i(16, 29), 2)
	var upgrade: int = g.place_building(&"ind_brick_workshop_1x1_l2", Vector2i(17, 29), 2)
	var bakery: int = g.place_building(&"com_corner_bakery_1x1", Vector2i(20, 31), 0)
	var cafe: int = g.place_building(&"com_street_cafe_1x1", Vector2i(21, 31), 0)
	var houses: Array[int] = []
	for x in range(22, 32):
		houses.append(g.place_building(&"res_small_01", Vector2i(x, 31), 0))
	var plaza: int = g.place_building(&"park_plaza", Vector2i(32, 31), 0, true)
	var square: int = g.place_building(&"park_square", Vector2i(33, 31), 0, true)
	var tower: int = g.place_building(&"off_tower_d", Vector2i(35, 31), 0)
	ev.grid_reset.emit()
	await process_frame
	for b: BuildingInstance in g.buildings.values():
		b.powered = b.id != dark
		b.has_water = true
	g.buildings[ruin].abandoned = true
	var site: BuildingInstance = g.buildings[tower]
	site.construction_total = 100
	site.construction_ticks = 60
	fx.refresh()

	var xf_of := func(id: int) -> Transform3D: return g.building_transform(g.buildings[id])
	var heavy: Array = fx.positions(&"fx_smoke_factory_heavy")
	var brick_top: Vector3 = xf_of.call(brick) * Vector3(-0.58, 1.85, 0.48)
	check.call("workshop smoke at its chimney (manifest)", heavy.any(func(p: Vector3) -> bool: return p.distance_to(brick_top) < 0.01))
	var foundry_xf: Transform3D = xf_of.call(foundry)
	check.call("foundry has two stacks", heavy.filter(func(p: Vector3) -> bool:
			var local: Vector3 = foundry_xf.affine_inverse() * p
			return Vector2(local.x, local.z).length() < 3.0).size() == 2)
	var flare: Array = fx.positions(&"fx_fire_refinery_flare")
	var refinery_mesh: Mesh = BM.mesh_for(CAT.get_type(&"ind_refinery_complex_3x2"))
	check.call("refinery flare snapped to the top of its stack", flare.size() == 1
			and flare[0].distance_to(xf_of.call(refinery) * PV.chimney_top(refinery_mesh)) < 0.01)
	var dark_xf: Transform3D = xf_of.call(dark)
	var ruin_xf: Transform3D = xf_of.call(ruin)
	check.call("no smoke without power or when abandoned", not heavy.any(func(p: Vector3) -> bool:
			var a: Vector3 = dark_xf.affine_inverse() * p
			var b: Vector3 = ruin_xf.affine_inverse() * p
			return Vector2(a.x, a.z).length() < 1.0 or Vector2(b.x, b.z).length() < 1.0))
	check.call("level variant uses the manifest chimney", heavy.any(func(p: Vector3) -> bool:
			return p.distance_to(xf_of.call(upgrade) * Vector3(-0.58, 1.85, 0.48)) < 0.01))
	check.call("smoke starts at the top of the building", heavy.all(func(p: Vector3) -> bool: return p.y > 1.5))
	check.call("bakery chimney and cafe aroma", fx.positions(&"fx_smoke_chimney_light").any(func(p: Vector3) -> bool:
			return p.distance_to(xf_of.call(bakery) * Vector3(-0.42, 1.88, 0.38)) < 0.01)
			and fx.count(&"fx_cafe_aroma_swirl") == 1)
	var expected_houses: int = houses.filter(func(id: int) -> bool:
			return fposmod(id * 0.754877 + 0.31, 1.0) < PV.HOUSE_SMOKE_SHARE).size()
	print("   house smoke %d of %d, heavy %d, chimney light %d" % [expected_houses, houses.size(), heavy.size(),
			fx.count(&"fx_smoke_chimney_light")])
	check.call("only some houses smoke", fx.count(&"fx_smoke_chimney_light") == expected_houses + 1
			and expected_houses > 0 and expected_houses < houses.size())
	check.call("plaza fountain on its planter", fx.count(&"fx_fountain_park_jets") == 1
			and fx.positions(&"fx_fountain_park_jets")[0].y > 0.05)
	check.call("leaves in the square, birds over a park", fx.count(&"fx_nature_falling_leaves") == 1
			and fx.count(&"fx_nature_flock_birds") == 1)
	check.call("construction dust and welding", fx.count(&"fx_dust_construction_site") == 1
			and fx.count(&"fx_sparks_welding_burst") == 1)
	site.construction_ticks = 95
	fx.refresh()
	check.call("early site — dust only", fx.count(&"fx_dust_construction_site") == 1
			and fx.count(&"fx_sparks_welding_burst") == 0)
	site.construction_ticks = 25
	fx.refresh()
	check.call("late site — welding only", fx.count(&"fx_dust_construction_site") == 0
			and fx.count(&"fx_sparks_welding_burst") == 1)
	site.construction_ticks = 60
	fx.refresh()
	var spark_before: Vector3 = fx.positions(&"fx_sparks_welding_burst")[0]
	site.construction_ticks = 40
	fx._move_sparks()
	check.call("sparks climb with the walls", fx.positions(&"fx_sparks_welding_burst")[0].y > spark_before.y + 0.1)
	site.construction_ticks = 60
	fx.refresh()

	# Время: на паузе стоит, вспышки идут.
	clock.set_speed(0)
	var t0: float = fx._fx_time
	var c0: float = fx._fx_clock
	fx._process(0.5)
	check.call("paused — effects stand still", fx._fx_time == t0 and fx._fx_clock > c0)
	clock.set_speed(1)
	fx._process(0.5)
	clock.set_speed(0)
	check.call("running — effects move", fx._fx_time > t0)

	# Снимки: промзона и городок.
	main.get_node("BadgeVisualizer").hide()
	main.get_node("HUD").hide()
	var cam: Node3D = main.get_node("RTSCamera")
	var shoot := func(file: String, at: Vector3, distance: float, pitch: float) -> void:
		cam.min_distance = 1.0
		cam.pitch_degrees = pitch
		cam.position = at
		cam._target_distance = distance
		cam._distance = distance
		cam._apply_distance()
		for i in 20: await process_frame
		root.get_texture().get_image().save_png("res://tests/out/" + file)
	clock.set_speed(1)
	await shoot.call("fx_industry.png", Vector3(11 * 2.0, 0, 29.5 * 2.0), 16.0, 28.0)
	await shoot.call("fx_town.png", Vector3(28 * 2.0, 0, 31 * 2.0), 15.0, 32.0)
	clock.set_speed(0)

	# Снос: пыль с обломками, потом пропадает. Повышение: салют, когда достроили.
	g.remove_building(houses[0])
	var removed: Array[Vector2i] = [Vector2i(22, 31)]
	ev.cells_changed.emit(removed)
	await process_frame
	# Пересчёт снял свет (станций нет) — возвращаем, как было.
	for b: BuildingInstance in g.buildings.values():
		b.powered = b.id != dark
	fx.refresh()
	check.call("bulldozed — dust burst", fx.count(&"fx_dust_bulldoze_burst") == 1)
	var upgraded: BuildingInstance = g.buildings[upgrade]
	upgraded.type_id = &"ind_brick_workshop_1x1_l3"
	upgraded.construction_total = 10
	upgraded.construction_ticks = 10
	fx.refresh()
	check.call("no confetti while rebuilding", fx.count(&"fx_celebrate_levelup_confetti") == 0)
	upgraded.construction_ticks = 0
	fx.refresh()
	check.call("level up — confetti over the roof", fx.count(&"fx_celebrate_levelup_confetti") == 1
			and fx.positions(&"fx_celebrate_levelup_confetti")[0].y > 1.5)
	# Снимок вспышек на середине.
	fx._fx_clock += 0.5
	await shoot.call("fx_bursts.png", Vector3(19 * 2.0, 0, 30 * 2.0), 9.0, 30.0)
	fx._process(3.0)
	check.call("bursts fade away", fx.count(&"fx_dust_bulldoze_burst") == 0 and fx.count(&"fx_celebrate_levelup_confetti") == 0)
	sm.new_city()
	await process_frame
	await process_frame
	check.call("new city — no effects, no burst for removed town", fx.count(&"fx_smoke_factory_heavy") == 0
			and fx.count(&"fx_dust_bulldoze_burst") == 0)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
