extends SceneTree
## Укрупнение (застройщик по месту, Р4): на дорогой земле дом растёт вглубь двора, 2–3 соседних участка
## одной улицы сливаются в один дом побольше, ряд 5×1 уступает домам 3×2 и 2×2; не сливаются чужие зоны,
## участки разной глубины и без выигрыша; что мешает — в «Инфо»; возраст дома сохраняется.

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
	var CO: GDScript = load("res://scripts/simulation/consolidation.gd")
	var LV: GDScript = load("res://scripts/simulation/land_value.gd")
	var LE: GDScript = load("res://scripts/simulation/levels.gd")
	var CS: GDScript = load("res://scripts/save/city_serializer.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Улица по y = 20, участки к северу (y 16..19). Цена земли — вручную.
	var make := func(zone: CityGrid.Zone, value: int) -> Array:
		var g := CityGrid.new(48)
		for x in range(2, 46): g.set_road(Vector2i(x, 20))
		for y in range(16, 20):
			for x in range(3, 45):
				g.set_zone(Vector2i(x, y), zone)
		var land = LV.new()
		land.size = g.size
		for layer in ["pollution", "noise", "land_value"]:
			var bytes := PackedByteArray()
			bytes.resize(g.size * g.size)
			bytes.fill(value if layer == "land_value" else 0)
			land.set(layer, bytes)
		var net := RoadNetwork.new()
		net.update(g)
		var ut := Utilities.new()
		ut.spare_power[net.component_of[Vector2i(10, 20)]] = 100000
		ut.spare_water[net.component_of[Vector2i(10, 20)]] = 100000
		return [g, land, net, ut]
	# Готовый обжитой дом шириной w на участке глубиной depth у фасада x.
	var house := func(g: CityGrid, zone: CityGrid.Zone, w: int, x: int, depth: int) -> BuildingInstance:
		var data: BuildingData = BuildingCatalog.level_types(zone, 1, Vector2i(w, 1))[0]
		var front: Array[Vector2i] = []
		for i in w: front.append(Vector2i(x + i, 19))
		var id: int = GR.build_lot(g, data, front, 2, depth)
		var b: BuildingInstance = g.buildings[id]
		b.powered = true
		b.has_water = true
		b.age_ticks = CO.MIN_AGE_TICKS + 10
		return b
	var people := func(b: BuildingInstance) -> int:
		var data: BuildingData = BuildingCatalog.get_type(b.type_id)
		return data.population + data.jobs
	var demands: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 0.5,
			CityGrid.Zone.COMMERCIAL: 0.5, CityGrid.Zone.INDUSTRIAL: 0.5}
	var plans_with := func(plans: Array[Dictionary], b: BuildingInstance) -> Array:
		return plans.filter(func(p: Dictionary) -> bool: return p.buildings.has(b))

	# --- Дом растёт вглубь двора ---
	var s: Array = make.call(CityGrid.Zone.RESIDENTIAL, 45)
	var g: CityGrid = s[0]
	var wide: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 2, 5, 4)
	var old_people: int = people.call(wide)
	var plans: Array[Dictionary] = CO.find_plans(g, s[1], demands)
	var own: Array = plans_with.call(plans, wide)
	check.call("deepen: one plan 2x2 (%d)" % own.size(), own.size() == 1 and own[0].buildings.size() == 1
			and own[0].pieces.size() == 1 and own[0].pieces[0][0].size == Vector2i(2, 2))
	check.call("status: soon deeper", CO.status(g, wide, s[1], demands, s[2], s[3]).begins_with("скоро: дом вглубь двора, 2×2"))
	var changed: Array[Vector2i] = CO.apply(g, own[0], RandomNumberGenerator.new(), s[2], s[3])
	var deep: BuildingInstance = g.get_building_at(Vector2i(5, 19))
	var lot: CityGrid.Lot = g.get_lot(Vector2i(5, 19))
	check.call("deepen: house 2x2 at the street, same lot, building site",
			deep != null and deep != wide and deep.size == Vector2i(2, 2) and deep.cell == Vector2i(5, 18)
			and deep.orientation == 2 and lot != null and lot.rect == Rect2i(5, 16, 2, 4)
			and deep.construction_ticks > 0 and changed.size() == 8 and not g.buildings.has(wide.id))
	check.call("deepen: twice the people (%d → %d)" % [old_people, people.call(deep)],
			people.call(deep) >= old_people * CO.MIN_GAIN)
	check.call("deepen: powered from spare", deep.powered and deep.has_water)

	# --- Три домика 1×1 сливаются в один 3×2 ---
	var a: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 1, 10, 4)
	var b: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 1, 11, 4)
	var c: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 1, 12, 4)
	plans = CO.find_plans(g, s[1], demands)
	var three: Array = plans.filter(func(p: Dictionary) -> bool: return p.buildings.size() == 3)
	var two: Array = plans.filter(func(p: Dictionary) -> bool: return p.buildings.size() == 2)
	check.call("merge: 3 lots → 3x2, 2 lots → 2x2 (%d, %d)" % [three.size(), two.size()],
			three.size() == 1 and three[0].pieces.size() == 1 and three[0].pieces[0][0].size == Vector2i(3, 2)
			and two.size() == 2 and two.all(func(p: Dictionary) -> bool:
				return p.pieces.size() == 1 and p.pieces[0][0].size == Vector2i(2, 2)))
	check.call("status: soon with neighbours", CO.status(g, b, s[1], demands, s[2], s[3]).begins_with("скоро: с соседями"))
	var count: int = g.buildings.size()
	CO.apply(g, three[0], RandomNumberGenerator.new(), s[2], s[3])
	var merged: BuildingInstance = g.get_building_at(Vector2i(11, 19))
	check.call("merge: one house over three lots", merged != null and merged.size == Vector2i(3, 2)
			and merged.cell == Vector2i(10, 18) and g.buildings.size() == count - 2
			and g.get_lot(Vector2i(12, 16)) == g.get_lot(Vector2i(10, 19)) and g.is_yard(Vector2i(12, 16))
			and not g.buildings.has(a.id) and not g.buildings.has(c.id))

	# --- Ряд 5×1 без глубокого варианта: вместо него дома 3×2 и 2×2 ---
	var row: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 5, 38, 4)
	plans = CO.find_plans(g, s[1], demands)
	var split: Array = plans_with.call(plans, row)
	check.call("row 5x1: plan 3x2 + 2x2 (%d)" % split.size(), split.size() == 1 and split[0].pieces.size() == 2
			and split[0].pieces[0][0].size == Vector2i(3, 2) and split[0].pieces[1][0].size == Vector2i(2, 2))
	check.call("status: two deeper houses", CO.status(g, row, s[1], demands, s[2], s[3]) == "скоро: вместо него дома 3×2 и 2×2 — глубже")
	var row_people: int = people.call(row)
	CO.apply(g, split[0], RandomNumberGenerator.new(), s[2], s[3])
	var left: BuildingInstance = g.get_building_at(Vector2i(38, 19))
	var right: BuildingInstance = g.get_building_at(Vector2i(42, 19))
	var lot_left: CityGrid.Lot = g.get_lot(Vector2i(38, 16))
	var lot_right: CityGrid.Lot = g.get_lot(Vector2i(42, 16))
	# Дома по порядку от меньшего x: 3×2 у x 38..40, 2×2 у x 41..42.
	check.call("row 5x1: two houses with own lots, twice the people",
			left != null and right != null and left != right and left.size == Vector2i(3, 2)
			and right.size == Vector2i(2, 2) and lot_left != lot_right and lot_left.rect == Rect2i(38, 16, 3, 4)
			and lot_right.rect == Rect2i(41, 16, 2, 4) and people.call(left) + people.call(right) >= row_people * 2)

	# --- Что не сливается ---
	for y in range(16, 20): g.set_zone(Vector2i(20, y), CityGrid.Zone.COMMERCIAL)
	var shop: BuildingInstance = house.call(g, CityGrid.Zone.COMMERCIAL, 1, 20, 4)
	var home: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 1, 21, 4)
	var shallow: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 1, 22, 2)
	var two_wide: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 2, 30, 4)
	var three_wide: BuildingInstance = house.call(g, CityGrid.Zone.RESIDENTIAL, 3, 32, 4)
	plans = CO.find_plans(g, s[1], demands)
	check.call("no merge: other zone, other depth", plans_with.call(plans, shop).is_empty()
			and plans_with.call(plans, home).is_empty() and plans_with.call(plans, shallow).is_empty())
	check.call("no merge without gain (2x1 + 3x1 = 5x1), each deepens alone",
			plans_with.call(plans, two_wide).size() == 1 and plans_with.call(plans, three_wide).size() == 1
			and plans_with.call(plans, two_wide)[0].buildings.size() == 1)

	# --- Что мешает ---
	var cheap: Array = make.call(CityGrid.Zone.RESIDENTIAL, 30)
	var lone: BuildingInstance = house.call(cheap[0], CityGrid.Zone.RESIDENTIAL, 2, 5, 4)
	var why: PackedStringArray = CO.blockers(cheap[0], lone, cheap[1], demands)
	check.call("blocked: cheap land (%s)" % ", ".join(why), why == PackedStringArray(["цена земли 30 из 40"]))
	check.call("cheap land: no plans", CO.find_plans(cheap[0], cheap[1], demands).is_empty())
	lone.age_ticks = 30
	lone.powered = false
	why = CO.blockers(cheap[0], lone, cheap[1], demands)
	check.call("blocked: new, no power (%s)" % ", ".join(why), why.size() == 3 and why[1] == "нет света"
			and why[2] == "дом новый — ещё 1 ч 30 мин")
	var no_demand: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.RESIDENTIAL: 0.0}
	check.call("blocked: no demand", CO.blockers(cheap[0], lone, cheap[1], no_demand)[0] == "нет спроса")
	var ind: Array = make.call(CityGrid.Zone.INDUSTRIAL, 10)
	var plant: BuildingInstance = house.call(ind[0], CityGrid.Zone.INDUSTRIAL, 2, 5, 4)
	var weak: Dictionary[CityGrid.Zone, float] = {CityGrid.Zone.INDUSTRIAL: 0.3}
	check.call("industry: demand, not land value", CO.blockers(ind[0], plant, ind[1], weak)
			== PackedStringArray(["спрос промзоны 30% из 50%"]) and CO.blockers(ind[0], plant, ind[1], demands).is_empty())
	# Нет запаса света: ничего не сносится.
	var poor: Array = make.call(CityGrid.Zone.RESIDENTIAL, 45)
	var keep: BuildingInstance = house.call(poor[0], CityGrid.Zone.RESIDENTIAL, 2, 5, 4)
	poor[3].spare_power.clear()
	var poor_plans: Array[Dictionary] = CO.find_plans(poor[0], poor[1], demands)
	check.call("status: not enough power", CO.status(poor[0], keep, poor[1], demands, poor[2], poor[3])
			== "не хватает света на дом 2×2")
	check.call("no spare power: nothing torn down", poor_plans.size() == 1
			and CO.apply(poor[0], poor_plans[0], RandomNumberGenerator.new(), poor[2], poor[3]).is_empty()
			and poor[0].buildings.has(keep.id))

	# --- Тик: шанс, по одному ---
	var t: Array = make.call(CityGrid.Zone.RESIDENTIAL, 45)
	for x in range(5, 20): house.call(t[0], CityGrid.Zone.RESIDENTIAL, 1, x, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var steps: int = 0
	var done: int = 0
	var before: int = t[0].buildings.size()
	while done < 3 and steps < 200:
		steps += 1
		if not CO.step(t[0], rng, t[2], t[3], t[1], demands).is_empty():
			done += 1
	check.call("step: one at a time with chance (%d in %d ticks)" % [done, steps], done == 3 and steps >= 4
			and t[0].buildings.size() < before)

	# --- Возраст: растёт после стройки, сохраняется ---
	var site: BuildingInstance = t[0].buildings.values().filter(
			func(x: BuildingInstance) -> bool: return x.construction_ticks > 0)[0]
	var ready: BuildingInstance = t[0].buildings.values().filter(
			func(x: BuildingInstance) -> bool: return x.construction_ticks == 0)[0]
	var site_age: int = site.age_ticks
	var ready_age: int = ready.age_ticks
	LE.tick_construction(t[0])
	check.call("age: ticks after construction only", site.age_ticks == site_age and ready.age_ticks == ready_age + 1)
	var d: Dictionary = CS.to_dict(t[0], "x", 100, 9, 5, 0, 0)
	var back = CS.from_dict(JSON.parse_string(JSON.stringify(d)))
	check.call("age saved", back.ok and back.grid.buildings[ready.id].age_ticks == ready.age_ticks)

	# --- «Инфо» дома: строка «Укрупнение» ---
	var city: CityGrid = gs.grid
	gs.money = 100000
	for x in range(10, 40): city.set_road(Vector2i(x, 30))
	for y in range(26, 30):
		for x in range(12, 20): city.set_zone(Vector2i(x, y), CityGrid.Zone.RESIDENTIAL)
	var front: Array[Vector2i] = [Vector2i(14, 29), Vector2i(15, 29)]
	GR.build_lot(city, BuildingCatalog.level_types(CityGrid.Zone.RESIDENTIAL, 1, Vector2i(2, 1))[0], front, 2, 4)
	ev.grid_reset.emit()
	await process_frame
	ev.cell_inspected.emit(Vector2i(14, 29))
	await process_frame
	var text := ""
	for label in main.get_node("HUD").find_children("*", "Label", true, false):
		text += label.text + "|"
	check.call("info: consolidation row", text.contains("Укрупнение|") and text.contains("дом новый"))

	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
