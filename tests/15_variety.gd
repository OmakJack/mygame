extends SceneTree
## Разнообразие зданий: перекраска (BuildingPalette) и здания из кода (ProceduralBuildings).
func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	root.get_node("SimClock").set_speed(0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gen: Array = ProceduralBuildings.types()
	check.call("procedural types (%d)" % gen.size(), gen.size() == 84)
	check.call("in catalog", BuildingCatalog.get_type(&"res_gen_2_3") != null and BuildingCatalog.get_type(&"off_gen_3_4") != null)
	check.call("grow at level 1", BuildingCatalog.growable_types(CityGrid.Zone.RESIDENTIAL_HIGH).any(func(d): return String(d.id).begins_with("res_gen_1")))
	var a: ArrayMesh = ProceduralBuildings.build("res_gen_2_3", false, 2)
	var b: ArrayMesh = ProceduralBuildings.build("res_gen_2_3", false, 2)
	var c: ArrayMesh = ProceduralBuildings.build("res_gen_2_4", false, 2)
	check.call("same id same look", a.get_aabb() == b.get_aabb())
	check.call("different ids differ", a.get_aabb() != c.get_aabb())
	check.call("fits in cell", a.get_aabb().size.x <= 1.85 and a.get_aabb().size.z <= 1.85)
	var tall: float = ProceduralBuildings.build("off_gen_3_0", true, 3).get_aabb().size.y
	var low: float = ProceduralBuildings.build("off_gen_1_0", true, 1).get_aabb().size.y
	check.call("level 3 taller than level 1", tall > low)
	var house := BuildingInstance.new(5, &"res_small_01", Vector2i(3, 4), 0)
	var data: BuildingData = BuildingCatalog.get_type(&"res_small_01")
	check.call("color stable", BuildingPalette.custom_for(house, data) == BuildingPalette.custom_for(house, data) and BuildingPalette.custom_for(house, data).a == 1.0)
	var colors := {}
	for id in 40:
		colors[BuildingPalette.custom_for(BuildingInstance.new(id, &"res_small_01", Vector2i(id % 64, id), 0), data)] = true
	check.call("many colors (%d)" % colors.size(), colors.size() >= 6)
	check.call("services keep look", BuildingPalette.custom_for(house, BuildingCatalog.get_type(&"school_01")).a == 0.0)
	var converted: Mesh = BuildingPalette.convert(BuildingMeshes.mesh_for(data))
	check.call("palette shader on Kenney model", converted.surface_get_material(0) is ShaderMaterial)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
