extends SceneTree
## Фаза 11: типы дорог — ёмкость и скорость в трафике, замена типа поверх, цены и содержание,
## шоссе без подключения домов, замки по званию, сохранение, вид кусков.
const OUT := "res://tests/out/"

func _initialize() -> void:
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var TR: GDScript = load("res://scripts/simulation/traffic.gd")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Данные: замена типа и защита.
	var g := CityGrid.new(32)
	check.call("new street", g.set_road(Vector2i(5, 5)) and g.get_road_type(Vector2i(5, 5)) == RoadTypes.Type.STREET)
	check.call("upgrade to avenue", g.can_build_road(Vector2i(5, 5), 2) and g.set_road(Vector2i(5, 5), 2) and g.get_road_type(Vector2i(5, 5)) == 2)
	check.call("same type no change", not g.can_build_road(Vector2i(5, 5), 2))
	g.remove_road(Vector2i(5, 5))
	check.call("removed clears type", g.get_road_type(Vector2i(5, 5)) == 0)
	# Шоссе не даёт домам доступа.
	for x in range(0, 10): g.set_road(Vector2i(x, 10), 3)
	check.call("highway gives no access", not g.has_road_access(Vector2i(4, 11)))
	g.set_road(Vector2i(4, 10), 1)
	check.call("street on highway gives access", g.has_road_access(Vector2i(4, 11)))

	# Трафик: тот же поток на улице и на проспекте — пробки только на улице.
	var jams := {}
	for type in [1, 2]:
		var tg := CityGrid.new(32)
		for x in range(2, 30): tg.set_road(Vector2i(x, 10), type)
		for x in [2, 3]:
			tg.place_building(&"res_block_n", Vector2i(x, 9), 0)
		for x in range(18, 30):
			for z in [9, 11]:
				var id: int = tg.place_building(&"off_tower_d", Vector2i(x, z), 0)
				tg.buildings[id].powered = true; tg.buildings[id].has_water = true
		var t = TR.compute(tg)
		jams[type] = t.jammed_cells
	check.call("avenue carries more (jams street %d → avenue %d)" % [jams[1], jams[2]], jams[1] > 0 and jams[2] < jams[1])

	# Инструмент: цена, замена поверх, замок.
	var tool: Node = main.get_node("BuildTool")
	gs.rank = 0
	ev.tool_requested.emit(11)
	check.call("avenue locked at village", tool.mode != 11)
	gs.rank = 1
	ev.tool_requested.emit(11)
	check.call("avenue open at settlement", tool.mode == 11)
	var city: CityGrid = gs.grid
	for x in range(10, 20): city.set_road(Vector2i(x, 20))
	tool._drag_start = Vector2i(10, 20)
	tool._update_drag(Vector2i(19, 20))
	var m0: int = gs.money
	tool._apply()
	tool._end_drag()
	check.call("drag avenue over street upgrades (paid %d)" % (m0 - gs.money), city.get_road_type(Vector2i(15, 20)) == 2 and m0 - gs.money == 10 * 30)
	ev.tool_requested.emit(12)
	check.call("highway locked at settlement", tool.mode == 11)
	ev.tool_requested.emit(0)
	# Содержание по типам.
	ev.cells_changed.emit([Vector2i(10, 20)] as Array[Vector2i])
	check.call("upkeep by type", gs.expenses >= roundi(10 * 0.5))

	# Сохранение: типы и старый формат (1 = улица).
	var d: Dictionary = CS.to_dict(city, "x", 100, 9, 5, 0, 1)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("road types saved", back.ok and back.grid.get_road_type(Vector2i(15, 20)) == 2)

	# Вид: полотно по графу дорог — клетки проспекта стали отрезком-проспектом, он нарисован.
	var rv: Node = main.get_node("RoadVisualizer")
	await process_frame
	var graph: RoadGraph = city.roads
	var owners: Array[int] = graph.owners_of(Vector2i(15, 20))
	check.call("avenue segment drawn", not owners.is_empty() and graph.segments[owners[0]].type == 2
			and rv.segment_mesh_count() > 0)
	check.call("highway piece exists", RoadGeometry.straight_piece(3, CityGrid.CELL_SIZE).get_surface_count() == 1)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
