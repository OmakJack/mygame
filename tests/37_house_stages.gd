extends SceneTree
## Дом растёт по стадиям (ProceduralHouses, семейства): большой жилой участок — одно здание, у семейства
## три уровня одного вида, выше и больше; повышение берёт следующую стадию того же семейства, а модели без
## стадий (Kenney, Gemini) перестраиваются в дом с семейством; старые id составных участков остались.

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.get_node("SimClock").set_speed(0)
	var GR: GDScript = load("res://scripts/simulation/growth.gd")
	var LE: GDScript = load("res://scripts/simulation/levels.gd")
	var HP: GDScript = load("res://scripts/simulation/happiness.gd")
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# --- Каталог: семейства по всем размерам, три стадии, растут в высоту ---
	var families: int = 0
	var staged: bool = true
	var grows_up: bool = true
	var fits: bool = true
	var bad: PackedStringArray = []
	for size: Vector2i in ProceduralHouses.SIZES:
		for v in ProceduralHouses.VARIANTS:
			var family: String = ProceduralHouses.family_id(size, v)
			var heights: Array[float] = []
			for level in [1, 2, 3]:
				var data: BuildingData = BuildingCatalog.get_type(StringName("%s_l%d" % [family, level]))
				if data == null or data.family != StringName(family) or data.level != level or data.size != size \
						or not data.grows or data.zone != CityGrid.Zone.RESIDENTIAL or data.mesh == null:
					staged = false
					bad.append("%s_l%d" % [family, level])
					continue
				var box: AABB = data.mesh.get_aabb()
				heights.append(box.end.y)
				# В своих клетках (дорожка к двери может выйти на тротуар перед домом).
				if box.position.x < -size.x + 0.01 or box.end.x > size.x - 0.01 or box.end.z > size.y - 0.01 \
						or box.position.z < -size.y - 0.3:
					fits = false
					bad.append("%s_l%d %s" % [family, level, box])
			if heights.size() == 3 and not (heights[0] < heights[1] and heights[1] < heights[2]):
				grows_up = false
				bad.append("%s heights %s" % [family, heights])
			families += 1
	check.call("families: %d sizes × %d, all with 3 stages" % [ProceduralHouses.SIZES.size(), ProceduralHouses.VARIANTS],
			staged and families == ProceduralHouses.SIZES.size() * ProceduralHouses.VARIANTS)
	check.call("every family grows taller: L1 < L2 < L3", grows_up)
	check.call("a house stays inside its cells", fits)
	if not bad.is_empty(): print("   ", ", ".join(bad.slice(0, 6)))
	var one: BuildingData = BuildingCatalog.get_type(&"res_home_3x2_1_l2")
	check.call("one building: walls, roof and details surfaces", one != null and one.mesh.get_surface_count() == 3)
	check.call("population from LevelStats (3×2 L2 — 24)", one != null and one.population == 24 and one.power_use == 12)

	# --- Составные участки из домиков ушли из роста; их id — для сохранений ---
	var legacy: BuildingData = BuildingCatalog.get_type(&"res_lot_3x2_2")
	var legacy_family: BuildingData = BuildingCatalog.get_type(&"res_home_3x2_0_l2")
	check.call("legacy id kept: same size, level, people; family look; does not grow",
			legacy != null and not legacy.grows and legacy.size == Vector2i(3, 2) and legacy.level == 2
			and legacy.population == 24 and legacy.family == &"res_home_3x2_0" and legacy.mesh == legacy_family.mesh)
	var compound_left: bool = false
	for data: BuildingData in BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL, 1):
		if String(data.id).begins_with("res_lot_"): compound_left = true
	check.call("growth never picks a house made of several houses", not compound_left)
	var all_legacy: bool = true
	for fmt in ["res_lot_2x1_%d_a", "res_lot_2x1_%d_b", "res_lot_3x1_%d_a", "res_lot_3x1_%d_b", "res_lot_2x2_%d",
			"res_lot_5x1_%d", "res_lot_3x2_%d"]:
		for level in [1, 2, 3]:
			if BuildingCatalog.get_type(StringName(fmt % level)) == null: all_legacy = false
	check.call("all 21 old compound ids load", all_legacy)

	# --- Следующий уровень: то же семейство; модели без стадий — в дом с семейством ---
	var next_of := func(id: StringName) -> Array[BuildingData]:
		return BuildingCatalog.next_level_types(BuildingCatalog.get_type(id))
	var own: Array[BuildingData] = next_of.call(&"res_home_2x1_3_l1")
	check.call("procedural L1 → only its own L2", own.size() == 1 and own[0].id == &"res_home_2x1_3_l2")
	var kenney: Array[BuildingData] = next_of.call(&"res_house_h")
	check.call("Kenney cottage → a staged house of L2 (%d options)" % kenney.size(), not kenney.is_empty()
			and kenney.all(func(d: BuildingData) -> bool: return d.family != &"" and d.level == 2 and d.size == Vector2i.ONE))
	var gemini: Array[BuildingData] = next_of.call(&"res_garden_estate_2x2_l1")
	check.call("Gemini estate → a staged 2×2 house", not gemini.is_empty()
			and gemini.all(func(d: BuildingData) -> bool: return d.family != &"" and d.size == Vector2i(2, 2)))
	var legacy_next: Array[BuildingData] = next_of.call(&"res_lot_5x1_1")
	check.call("old compound lot → its family's next stage", legacy_next.size() == 1 and legacy_next[0].id == &"res_home_5x1_0_l2")
	var tower: Array[BuildingData] = next_of.call(&"res_gen_1_2")
	check.call("tower keeps its family too", tower.size() == 1 and tower[0].id == &"res_gen_2_2")
	var shop: BuildingData = BuildingCatalog.get_type(&"com_lot_2x1_1")
	check.call("no staged types — any next level as before",
			BuildingCatalog.next_level_types(shop) == BuildingCatalog.level_types(shop.zone, 2, shop.size))
	var low: float = ProceduralBuildings.build("res_gen_2", false, 1).get_aabb().end.y
	var high: float = ProceduralBuildings.build("res_gen_2", false, 3).get_aabb().end.y
	check.call("tower family: same seed, taller on L3 (%.1f → %.1f)" % [low, high], high > low + 1.0)

	# --- Повышение в игре (Levels.step): дом растёт своим семейством до ур. 3 ---
	var g := CityGrid.new(32)
	for x in range(2, 30): g.set_road(Vector2i(x, 20))
	for y in range(16, 20):
		for x in range(3, 29): g.set_zone(Vector2i(x, y), CityGrid.Zone.RESIDENTIAL)
	var land = LV.new()
	land.size = g.size
	for layer in ["pollution", "noise", "land_value"]:
		var bytes := PackedByteArray()
		bytes.resize(g.size * g.size)
		bytes.fill(60 if layer == "land_value" else 0)
		land.set(layer, bytes)
	var net := RoadNetwork.new()
	net.update(g)
	var ut := Utilities.new()
	ut.spare_power[net.component_of[Vector2i(10, 20)]] = 100000
	ut.spare_water[net.component_of[Vector2i(10, 20)]] = 100000
	var place := func(id: StringName, x: int) -> BuildingInstance:
		var data: BuildingData = BuildingCatalog.get_type(id)
		var front: Array[Vector2i] = []
		for i in data.size.x: front.append(Vector2i(x + i, 19))
		var b: BuildingInstance = g.buildings[GR.build_lot(g, data, front, 2, 4)]
		b.powered = true
		b.has_water = true
		return b
	var row: BuildingInstance = place.call(&"res_home_3x1_2_l1", 4)
	var cottage: BuildingInstance = place.call(&"res_house_h", 10)
	var mood = HP.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var demands: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 0.5,
			CityGrid.Zone.COMMERCIAL: 0.5, CityGrid.Zone.INDUSTRIAL: 0.5}
	var history: Dictionary = {row.id: [row.type_id], cottage.id: [cottage.type_id]}
	for t in 60:
		for b: BuildingInstance in [row, cottage]:
			mood.by_building[b.id] = 90
			b.construction_ticks = 0
		LE.step(g, rng, net, ut, land, mood, demands)
		for b: BuildingInstance in [row, cottage]:
			if history[b.id][-1] != b.type_id: history[b.id].append(b.type_id)
	check.call("row house grows L1 → L2 → L3 in its family %s" % [history[row.id]],
			history[row.id] == [&"res_home_3x1_2_l1", &"res_home_3x1_2_l2", &"res_home_3x1_2_l3"])
	var cottage_path: Array = history[cottage.id]
	var cottage_family: StringName = BuildingCatalog.get_type(cottage_path[-1]).family if cottage_path.size() == 3 else &""
	check.call("Kenney cottage → staged house → its L3 %s" % [cottage_path], cottage_path.size() == 3
			and cottage_family != &"" and BuildingCatalog.get_type(cottage_path[1]).family == cottage_family)

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
