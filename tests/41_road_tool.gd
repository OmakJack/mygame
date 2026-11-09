extends SceneTree
## Инструмент дорог как в Cities: Skylines (RoadTool): щелчок — начало, щелчок — конец, цепочка
## тянется дальше; ПКМ — оборвать; примыкание к середине дороги — Т-перекрёсток; дуга (начало, изгиб,
## конец); плавная — продолжает прошлый кусок по касательной; замена типа щелчком; привязка к сетке
## и без неё (углы по 15°); подпись длины и цены, причина отказа; полотно нарисовано; машинки едут
## по кривой; светофоры только на перекрёстках; граф переживает сохранение.

const STREET: int = 1
const AVENUE: int = 2


func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	root.get_node("SaveManager").save_dir = "res://tests/out/test_saves/" # не трогать сохранения Андрея
	var gs: Node = root.get_node("GameState")
	var ev: Node = root.get_node("Events")
	root.get_node("SimClock").set_speed(0)
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.get_node("MainMenu").close()
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
		print(("ok   " if ok else "FAIL ") + name)
	var tool: Node = main.get_node("BuildTool")
	var roads: Node = main.get_node("RoadTool")
	var g: CityGrid = gs.grid
	var graph: RoadGraph = g.roads
	gs.money = 100000
	gs.rank = 3
	var c := func(x: float, y: float) -> Vector2: return Vector2((x + 0.5) * 2.0, (y + 0.5) * 2.0)
	var click_at := func(p: Vector2) -> void:
		roads.update_at(p)
		roads.click()

	ev.tool_requested.emit(tool.Mode.ROAD)
	check.call("road mode turns the road tool on", roads.road_type == STREET)
	# Прямая: два щелчка — дорога, цена списана, цепочка продолжается от конца.
	click_at.call(c.call(5, 10))
	roads.update_at(c.call(20, 10))
	check.call("label shows length and cost (%s)" % roads.label_text(), roads.label_text() == "30 м · $160")
	var money: int = gs.money
	roads.click()
	check.call("straight road built and paid", g.is_road(Vector2i(5, 10)) and g.is_road(Vector2i(20, 10))
			and money - gs.money == 160)
	click_at.call(c.call(20, 22))
	var corner: int = graph.node_near(c.call(20, 10), 0.1)
	check.call("chain goes on from the end (corner node)", corner != -1 and graph.nodes[corner].segments.size() == 2
			and g.is_road(Vector2i(20, 22)))
	# ПКМ обрывает цепочку.
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	roads._unhandled_input(rmb)
	check.call("right click ends the chain", roads._start == null)

	# Примыкание к середине дороги (мышь чуть мимо центра) — Т-перекрёсток.
	click_at.call(c.call(12, 10) + Vector2(0.4, 0.6))
	click_at.call(c.call(12, 18))
	var tee: int = graph.node_near(c.call(12, 10), 0.1)
	check.call("joining the middle of a road makes a T", tee != -1 and graph.nodes[tee].segments.size() == 3)
	check.call("T is a junction with lights", TrafficLights.is_junction(g, Vector2i(12, 10)))
	roads.reset_chain()

	# Отказ: вплотную к дороге — красная подпись с причиной.
	click_at.call(c.call(5, 11))
	roads.update_at(c.call(10, 11))
	check.call("too close is refused (%s)" % roads.label_text(), not roads.current_plan().ok
			and roads.label_text().contains("близко"))
	money = gs.money
	roads.click()
	check.call("refused click builds nothing", gs.money == money and not g.is_road(Vector2i(8, 11)))
	roads.reset_chain()

	# Дуга: начало, изгиб, конец — одна кривая.
	roads.set_shape(1)
	click_at.call(c.call(30, 5))
	click_at.call(c.call(40, 5))
	roads.update_at(c.call(40, 15))
	check.call("curve preview ok (%s)" % roads.label_text(), roads.current_plan().ok)
	roads.click()
	var arc: int = graph.segment_near(RoadGraph.bezier(c.call(30, 5), c.call(40, 5), c.call(40, 15), 0.5), 0.2)
	check.call("curve built as one bent segment", arc != -1 and graph.segments[arc].ctrl.distance_to(c.call(40, 5)) < 0.01)
	# Светофоры не встают вдоль дуги (раньше — на клетках с тремя соседями).
	var lights_ok: bool = true
	for cell: Vector2i in graph.segments[arc].cells:
		if TrafficLights.is_junction(g, cell): lights_ok = false
	check.call("no traffic lights along the curve", lights_ok)
	roads.reset_chain()

	# Плавная: от тупика дуга продолжает дорогу по касательной.
	roads.set_shape(2)
	click_at.call(c.call(40, 15))
	roads.update_at(c.call(46, 24))
	var smooth: RoadGraph.Plan = roads.current_plan()
	var tangent: Vector2 = RoadGraph.bezier_tangent(smooth.p0, smooth.c, smooth.p2, 0.0).normalized()
	check.call("smooth piece starts along the old road (%s)" % roads.label_text(), smooth.ok and tangent.dot(Vector2(0, 1)) > 0.99)
	roads.click()
	check.call("smooth piece built", g.is_road(Vector2i(46, 24)))
	roads.reset_chain()

	# Без сетки: точка — где мышь, направление липнет к 45°.
	roads.set_shape(0)
	roads.set_grid_snap(false)
	click_at.call(Vector2(11.3, 61.7))
	check.call("free start point off the grid", roads._start.pos.is_equal_approx(Vector2(11.3, 61.7)))
	roads.update_at(Vector2(11.3, 61.7) + Vector2.from_angle(deg_to_rad(47.0)) * 16.0)
	var free_plan: RoadGraph.Plan = roads.current_plan()
	check.call("angle snaps to 45°", absf(rad_to_deg((free_plan.p2 - free_plan.p0).angle()) - 45.0) < 0.01)
	roads.click()
	roads.reset_chain()
	roads.set_grid_snap(true)

	# Замена типа: щелчок по дороге — проспект, доплата за клетки.
	ev.tool_requested.emit(tool.Mode.ROAD_AVENUE)
	roads.set_shape(3)
	roads.update_at(c.call(7, 10))
	check.call("upgrade label (%s)" % roads.label_text(), roads.label_text().begins_with("Улица → Проспект"))
	var street_id: int = graph.segment_near(c.call(7, 10), 0.2)
	var price: int = graph.retype_cost(street_id, AVENUE)
	money = gs.money
	roads.click()
	check.call("upgraded to avenue and paid %d" % price, g.get_road_type(Vector2i(7, 10)) == AVENUE and money - gs.money == price and price > 0)
	roads.set_shape(0)

	# Полотно: у каждого отрезка свой меш; машинки — по кривой.
	for i in 3: await process_frame
	var rv: Node = main.get_node("RoadVisualizer")
	check.call("every segment drawn (%d of %d)" % [rv.segment_mesh_count(), graph.segments.size()],
			rv.segment_mesh_count() == graph.segments.size())
	var on_road: bool = true
	for cell: Vector2i in graph.segments[arc].cells:
		if graph.nearest_on(graph.segments[arc], graph.anchor(cell)).y > 0.05: on_road = false
	check.call("cars follow the curve (cell points on the road)", on_road)

	# Протягивание по клеткам (тесты, сценарии) — граф подхватывает.
	var before: int = graph.segments.size()
	tool._set_mode(tool.Mode.ROAD); tool._dragging = true; tool._drag_start = Vector2i(5, 40)
	tool._update_drag(Vector2i(15, 40)); tool._apply(); tool._end_drag()
	graph.sync(g)
	check.call("cell drag still builds roads, graph adopts them", g.is_road(Vector2i(10, 40)) and graph.segments.size() == before + 1)

	# Сохранение: граф с дугой — тот же после загрузки.
	var data: Dictionary = CS.to_dict(g, "x", 100, 9, 5, 0, 1)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(data)))
	var arc_back: RoadGraph.Segment = back.grid.roads.segments.get(arc) if back.ok else null
	check.call("save keeps the road graph (%d segments)" % (back.grid.roads.segments.size() if back.ok else -1),
			back.ok and back.grid.roads.segments.size() == graph.segments.size() and arc_back != null
			and arc_back.ctrl.is_equal_approx(graph.segments[arc].ctrl))
	var old_save: Dictionary = data.duplicate(true)
	old_save.grid.erase("road_graph")
	var old_back = CS.from_dict(JSON.parse_string(JSON.stringify(old_save)))
	check.call("old save without a graph: roads become segments", old_back.ok and old_back.grid.roads.segments.size() > 0
			and old_back.grid.road_cells.size() == g.road_cells.size())
	ev.tool_requested.emit(tool.Mode.NONE)
	check.call("other tool turns the road tool off", roads.road_type == 0)
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
