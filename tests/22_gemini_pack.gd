extends SceneTree
## Архитектурный пак Gemini (48 моделей) и пак Argon «Магазины, кафе и торговые центры» (20):
## подключены, на всех уровнях, выбираются чаще прежних; участок 4 клетки у многоэтажек — одно здание 4×1.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.get_node("SimClock").set_speed(0)
	# Паки: Gemini (48 зданий) и Argon «Магазины, кафе и торговые центры» (20) — одна схема manifest.json.
	var models: Array = []
	var counts: Array[int] = []
	for path: String in ["res://assets/models/blender/pack/manifest.json", "res://assets/models/blender/commercial/manifest.json"]:
		var f := FileAccess.open(path, FileAccess.READ)
		var manifest: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {"models": []}
		models.append_array(manifest.models)
		counts.append(manifest.models.size())
	check.call("packs: 48 Gemini + 20 commercial models (%s)" % str(counts), counts == [48, 20])
	var missing: Array = []
	for model in models:
		for suffix in ["", "_l1", "_l2", "_l3"]:
			var d: BuildingData = BuildingCatalog.get_type(StringName(model.id + suffix))
			if suffix == "" and (d == null or not d.preferred or d.model == null or d.size != Vector2i(int(model.cells[0]), int(model.cells[1]))):
				missing.append(model.id)
	check.call("all 68 models in catalog (%d missing: %s)" % [missing.size(), str(missing)], missing.is_empty())
	var zones: Dictionary = {"RESIDENTIAL": CityGrid.Zone.RESIDENTIAL, "RESIDENTIAL_HIGH": CityGrid.Zone.RESIDENTIAL_HIGH,
			"COMMERCIAL": CityGrid.Zone.COMMERCIAL, "COMMERCIAL_HIGH": CityGrid.Zone.COMMERCIAL_HIGH,
			"INDUSTRIAL": CityGrid.Zone.INDUSTRIAL, "OFFICE": CityGrid.Zone.OFFICE}
	var levels_ok := true
	for model in models:
		var zone: int = zones[model.suggested_zone]
		var size := Vector2i(int(model.cells[0]), int(model.cells[1]))
		for lvl in [1, 2, 3]:
			var found := false
			for d in BuildingCatalog.level_types(zone, lvl, size):
				if d.model != null and d.model.resource_path.contains(model.id): found = true
			if not found: levels_ok = false
	check.call("each pack model on all 3 levels", levels_ok)
	# Магазины Argon: модель вписана в участок и не плоская (меш собирается, как у остальных домов).
	var fits := true
	for model in models:
		if not String(model.id).begins_with("com_"): continue
		var d: BuildingData = BuildingCatalog.get_type(StringName(model.id))
		var box: AABB = BuildingMeshes.mesh_for(d).get_aabb()
		if box.size.x > d.size.x * 2.0 or box.size.z > d.size.y * 2.0 or box.size.y < 1.0: fits = false
	check.call("commercial models fit their lots", fits)
	var shops := 0
	for d in BuildingCatalog.level_types(CityGrid.Zone.COMMERCIAL, 1, Vector2i.ONE):
		if d.model != null and d.model.resource_path.contains("/commercial/com_"): shops += 1
	check.call("small shops grow in commercial zones (%d types 1x1 L1)" % shops, shops >= 3)
	# Доля выбора пака ~75 %.
	var options: Array = BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL, 1, Vector2i.ONE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hits := 0
	for i in 2000:
		if BuildingCatalog.pick_weighted(options, rng).preferred: hits += 1
	check.call("pack chosen ~75%% (%.0f%%)" % (hits / 20.0), absf(hits / 2000.0 - 0.75) < 0.04)
	# 4 клетки многоэтажек у улицы: застройщик может поставить один дом 4×1 (тип ширины 4 есть).
	var g := CityGrid.new(32)
	for x in range(2, 30): g.set_road(Vector2i(x, 10))
	for x in range(5, 9):
		g.set_zone(Vector2i(x, 9), CityGrid.Zone.RESIDENTIAL_HIGH)
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var by_width: Dictionary[int, Array] = {}
	for data: BuildingData in BuildingCatalog.growable_types(CityGrid.Zone.RESIDENTIAL_HIGH):
		if not by_width.has(data.size.x): by_width[data.size.x] = []
		by_width[data.size.x].append(data)
	var plan: Dictionary = GR.plan_at(g, null, CityGrid.Zone.RESIDENTIAL_HIGH, Vector2i(6, 9), by_width, 4.0)
	check.call("4 cells of apartments → one 4x1 plan", not plan.is_empty() and plan.front.size() == 4 and plan.depth == 1)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
