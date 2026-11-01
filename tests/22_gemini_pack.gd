extends SceneTree
## Архитектурный пак Gemini: 48 моделей подключены, на всех уровнях, выбираются чаще прежних,
## участок 4 клетки у многоэтажек — одно здание 4×1.

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.get_node("SimClock").set_speed(0)
	var f := FileAccess.open("res://assets/models/blender/pack/manifest.json", FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(f.get_as_text())
	var missing: Array = []
	for model in manifest.models:
		for suffix in ["", "_l1", "_l2", "_l3"]:
			var d: BuildingData = BuildingCatalog.get_type(StringName(model.id + suffix))
			if suffix == "" and (d == null or not d.preferred or d.model == null or d.size != Vector2i(int(model.cells[0]), int(model.cells[1]))):
				missing.append(model.id)
	check.call("all 48 models in catalog (%d missing)" % missing.size(), missing.is_empty())
	var levels_ok := true
	for model in manifest.models:
		var zone: int = {"RESIDENTIAL": 1, "RESIDENTIAL_HIGH": 4, "INDUSTRIAL": 3, "OFFICE": 6}[model.suggested_zone]
		var size := Vector2i(int(model.cells[0]), int(model.cells[1]))
		for lvl in [1, 2, 3]:
			var found := false
			for d in BuildingCatalog.level_types(zone, lvl, size):
				if d.model != null and d.model.resource_path.contains(model.id): found = true
			if not found: levels_ok = false
	check.call("each pack model on all 3 levels", levels_ok)
	# Доля выбора пака ~75 %.
	var options: Array = BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL, 1, Vector2i.ONE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hits := 0
	for i in 2000:
		if BuildingCatalog.pick_weighted(options, rng).preferred: hits += 1
	check.call("pack chosen ~75%% (%.0f%%)" % (hits / 20.0), absf(hits / 2000.0 - 0.75) < 0.04)
	# 4 клетки многоэтажек — один участок 4×1.
	var g := CityGrid.new(32)
	for x in range(2, 30): g.set_road(Vector2i(x, 10))
	var cells: Array[Vector2i] = []
	for x in range(5, 9):
		g.set_zone(Vector2i(x, 9), CityGrid.Zone.RESIDENTIAL_HIGH)
		cells.append(Vector2i(x, 9))
	var plans: Array = LotPlanner.plan(g, cells, CityGrid.Zone.RESIDENTIAL_HIGH)
	check.call("4 cells of apartments → one 4x1 lot", plans.size() == 1 and (plans[0][0] as Rect2i).size == Vector2i(4, 1))
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
