extends SceneTree
## Создаёт типы зданий (data/buildings/*.tres) из моделей Kenney и даёт модели службам и паркам.
## Запуск: godot --headless --path . --script res://tools/generate_building_types.gd
## Масштабы наборов сближены (ревью Argon 011): окна и двери одного размера во всём городе.
## Фаза 10: у каждой зоны — уровни 1..3, цифры — LevelStats (общие с ProceduralBuildings).
## Старые id (res_house_*, com_shop_*, ind_factory_*, *_small_01, службы) сохраняются:
## на них держатся сохранения. Новые наборы — новые id.

const KENNEY := "res://assets/models/kenney/"
## Свои модели из Blender (tools/blender) — в models/blender, путь в наборах начинается с «blender/».
const MODELS := "res://assets/models/"
const OUT := "res://data/buildings/"

## Наборы: зона, модели (id → модель), название, масштаб, уровни.
## levels: id → уровень; «rank» — по объёму модели (меньшие — ниже), поровну на три уровня.
const SETS: Array[Dictionary] = [
	{"zone": CityGrid.Zone.RESIDENTIAL, "name": "Дом", "scale": 1.1, "levels": "rank",
		"models": {"res_small_01": "suburban/building-type-a"}, "kit": "suburban/building-type-",
		"letters": "bcdefghijklmnopqrstu", "prefix": "res_house_"},
	{"zone": CityGrid.Zone.COMMERCIAL, "name": "Магазин", "scale": 1.4,
		"levels": {"com_small_01": 1, "com_shop_e": 1, "com_shop_d": 2, "com_shop_b": 2,
			"com_shop_i": 3, "com_shop_j": 3, "com_shop_k": 3},
		"models": {"com_small_01": "commercial/building-a"}, "kit": "commercial/building-",
		"letters": "bdeijk", "prefix": "com_shop_"},
	{"zone": CityGrid.Zone.INDUSTRIAL, "name": "Цех", "scale": 1.0, "levels": "rank",
		"models": {"ind_small_01": "industrial/building-a"}, "kit": "industrial/building-",
		"letters": "bcdefghijkmnopqrst", "prefix": "ind_factory_"},
	{"zone": CityGrid.Zone.RESIDENTIAL_HIGH, "name": "Многоэтажка", "scale": 1.4,
		"levels": {"res_block_f": 1, "res_block_g": 1, "res_block_l": 2, "res_block_m": 2, "res_block_n": 3},
		"models": {}, "kit": "commercial/building-", "letters": "fglmn", "prefix": "res_block_"},
	# Панельные дома из Blender (tools/blender/make_panel_houses.py), палитра Kenney.
	{"zone": CityGrid.Zone.RESIDENTIAL_HIGH, "name": "Панельный дом", "scale": 1.4,
		"levels": {"res_panel_a": 1, "res_panel_b": 2, "res_panel_c": 3},
		"models": {}, "kit": "blender/panel-", "letters": "abc", "prefix": "res_panel_"},
	{"zone": CityGrid.Zone.COMMERCIAL_HIGH, "name": "Торговый дом", "scale": 1.4,
		"levels": {"com_tower_i": 1, "com_tower_k": 2, "com_tower_j": 3},
		"models": {}, "kit": "commercial/building-", "letters": "ikj", "prefix": "com_tower_"},
	{"zone": CityGrid.Zone.OFFICE, "name": "Офис", "scale": 1.4,
		"levels": {"off_tower_a": 1, "off_tower_c": 1, "off_tower_e": 2, "off_tower_b": 2, "off_tower_d": 3},
		"models": {}, "kit": "commercial/building-skyscraper-", "letters": "acebd", "prefix": "off_tower_"},
]

## Архитектурный пак Gemini (assets/models/blender/pack, tools/blender/make_building_pack.py):
## 48 зданий 1×1…7×1, 2×2, 3×2 — зона и уровень из manifest.json, в игровом масштабе (model_scale 1),
## фасад −Y в Blender → model_turns 2. Каждая модель — на всех трёх уровнях: на своём (из manifest)
## с весом PACK_WEIGHT, на остальных — PACK_OTHER_WEIGHT; все — «предпочтительные» (preferred):
## выбираются в 75 % случаев (BuildingCatalog.PREFERRED_SHARE), так новые дома видно сразу,
## а повышение внутри пака чаще берёт здание «своего» уровня.
const PACK_MANIFEST := "res://assets/models/blender/pack/manifest.json"
const PACK_WEIGHT: float = 4.0
const PACK_OTHER_WEIGHT: float = 1.5
const PACK_ZONES: Dictionary = {
	"RESIDENTIAL": CityGrid.Zone.RESIDENTIAL, "RESIDENTIAL_HIGH": CityGrid.Zone.RESIDENTIAL_HIGH,
	"COMMERCIAL": CityGrid.Zone.COMMERCIAL, "COMMERCIAL_HIGH": CityGrid.Zone.COMMERCIAL_HIGH,
	"INDUSTRIAL": CityGrid.Zone.INDUSTRIAL, "OFFICE": CityGrid.Zone.OFFICE,
}

## Многоклеточные модели из Blender (tools/blender/make_large_buildings.py), уровни 1..3.
const LARGE_SETS: Array[Dictionary] = [
	{"zone": CityGrid.Zone.RESIDENTIAL_HIGH, "size": Vector2i(3, 1), "name": "Панельный корпус",
		"prefix": "res_panel_3x1_", "kit": "blender/panel-3x1-l"},
	{"zone": CityGrid.Zone.RESIDENTIAL_HIGH, "size": Vector2i(5, 1), "name": "Дом с аркой",
		"prefix": "res_panel_5x1_", "kit": "blender/panel-5x1-l"},
	{"zone": CityGrid.Zone.RESIDENTIAL_HIGH, "size": Vector2i(3, 2), "name": "Жилой квартал",
		"prefix": "res_panel_3x2_", "kit": "blender/panel-3x2-l"},
	{"zone": CityGrid.Zone.RESIDENTIAL_HIGH, "size": Vector2i(7, 1), "name": "Проспектный дом",
		"prefix": "res_panel_7x1_", "kit": "blender/panel-7x1-l"},
	{"zone": CityGrid.Zone.COMMERCIAL, "size": Vector2i(3, 1), "name": "Торговый ряд",
		"prefix": "com_strip_3x1_", "kit": "blender/com-3x1-l"},
	{"zone": CityGrid.Zone.COMMERCIAL, "size": Vector2i(5, 1), "name": "Торговая галерея",
		"prefix": "com_gal_5x1_", "kit": "blender/com-5x1-l"},
	{"zone": CityGrid.Zone.COMMERCIAL, "size": Vector2i(2, 2), "name": "Универмаг",
		"prefix": "com_mall_2x2_", "kit": "blender/mall-2x2-l"},
	{"zone": CityGrid.Zone.COMMERCIAL_HIGH, "size": Vector2i(2, 2), "name": "Торговый центр",
		"prefix": "com_center_2x2_", "kit": "blender/mall-2x2-l"},
	{"zone": CityGrid.Zone.COMMERCIAL_HIGH, "size": Vector2i(5, 1), "name": "Большой пассаж",
		"prefix": "com_center_5x1_", "kit": "blender/com-5x1-l"},
	{"zone": CityGrid.Zone.COMMERCIAL_HIGH, "size": Vector2i(3, 2), "name": "Молл",
		"prefix": "com_mall_3x2_", "kit": "blender/mall-3x2-l"},
	{"zone": CityGrid.Zone.INDUSTRIAL, "size": Vector2i(2, 1), "name": "Ангар",
		"prefix": "ind_hall_2x1_", "kit": "blender/ind-2x1-l"},
	{"zone": CityGrid.Zone.INDUSTRIAL, "size": Vector2i(2, 2), "name": "Завод",
		"prefix": "ind_plant_2x2_", "kit": "blender/ind-2x2-l"},
	{"zone": CityGrid.Zone.INDUSTRIAL, "size": Vector2i(5, 1), "name": "Складской ряд",
		"prefix": "ind_line_5x1_", "kit": "blender/ind-5x1-l"},
	{"zone": CityGrid.Zone.INDUSTRIAL, "size": Vector2i(3, 2), "name": "Комбинат",
		"prefix": "ind_comb_3x2_", "kit": "blender/ind-3x2-l"},
]

## Старые типы, которые больше не растут (модели служб — школа c, полиция h — и прежние «многоэтажки»):
## остаются ради сохранений (решение 011: дом не должен выглядеть как служба).
const RETIRED: Dictionary = {
	"com_shop_c": "commercial/building-c", "com_shop_h": "commercial/building-h",
	"com_shop_f": "commercial/building-f", "com_shop_g": "commercial/building-g",
	"com_shop_l": "commercial/building-l", "com_shop_m": "commercial/building-m",
	"com_shop_n": "commercial/building-n", "ind_factory_l": "industrial/building-l",
}

## Службы и станции: id → [модель, масштаб, цвет вывески, вывеска-крест, загрязнение, шум, бонус к цене земли].
const EXISTING: Dictionary = {
	"power_plant_01": ["industrial/chimney-large", 1.2, Color(0, 0, 0, 0), false, 70, 20, 0],
	"water_tower_01": ["industrial/water-tower", 1.0, Color(0, 0, 0, 0), false, 0, 0, 0],
	"school_01": ["commercial/building-c", 1.4, Color(0.98, 0.8, 0.2), false, 0, 5, 15],
	"health_01": ["commercial/building-n", 1.4, Color(0.9, 0.15, 0.15), true, 0, 0, 15],
	"fire_01": ["industrial/building-l", 1.0, Color(0.9, 0.3, 0.1), false, 0, 5, 10],
	"police_01": ["commercial/building-h", 1.4, Color(0.2, 0.4, 0.9), false, 0, 0, 10],
}

## Ветряки (Argon, tools/blender/make_services_and_wind.py → assets/models/blender/services/parts):
## основание — модель здания, ротор крутит RotorVisualizer. Обычный (трёхлопастной) даёт мало,
## вертикальный — больше; дыма нет, но дороже ТЭЦ за киловатт.
## id → [название, основание, ротор, ось ротора в координатах модели, ось вращения, оборотов в секунду,
## цена, содержание, свет (единицы по 10 кВт), шум].
const WIND: Dictionary = {
	"wind_turbine_01": ["Ветряк", "blender/services/parts/wind_hawt_base", "blender/services/parts/wind_hawt_rotor",
		Vector3(0.0, 3.38, 0.44), Vector3(0.0, 0.0, -1.0), 0.25, 100, 2, 20, 8],
	"wind_turbine_02": ["Вертикальный ветряк", "blender/services/parts/wind_vawt_base",
		"blender/services/parts/wind_vawt_rotor", Vector3(0.0, 1.04, 0.0), Vector3(0.0, -1.0, 0.0), 0.33, 220, 4, 45, 4],
}

## Парки (фаза 9): id → [название, вид, цена, содержание, бонус к цене земли].
const PARKS: Dictionary = {
	"park_square": ["Сквер", BuildingData.Park.SQUARE, 60, 1, 35],
	"park_garden": ["Сад", BuildingData.Park.GARDEN, 120, 2, 50],
	"park_plaza": ["Площадь", BuildingData.Park.PLAZA, 200, 3, 70],
}


func _initialize() -> void:
	var created: int = 0
	for set: Dictionary in SETS:
		var models: Dictionary = set.models.duplicate()
		for letter: String in set.letters:
			models[set.prefix + letter] = set.kit + letter
		var levels: Dictionary = _rank(models) if set.levels is String else set.levels
		for id: String in models:
			var level: int = levels[id]
			var data := _load_or_new(id)
			data.display_name = "%s %s · ур. %d" % [set.name, _letter(id), level]
			data.grows = true
			LevelStats.apply(data, set.zone, level)
			data.model = load(_model_path(models[id]))
			data.model_scale = set.scale
			_save(data)
			created += 1
	for large: Dictionary in LARGE_SETS:
		var plot_size: Vector2i = large.size
		for level: int in [1, 2, 3]:
			var id: String = "%s%d" % [large.prefix, level]
			var data := _load_or_new(id)
			data.display_name = "%s · ур. %d" % [large.name, level]
			data.grows = true
			LevelStats.apply(data, large.zone, level, plot_size)
			data.model = load(_model_path("%s%d" % [large.kit, level]))
			data.model_scale = 1.0
			_save(data)
			created += 1
	created += _make_pack_types()
	for id: String in RETIRED:
		var data := _load_or_new(id)
		data.grows = false
		data.model = load(KENNEY + RETIRED[id] + ".glb")
		_save(data)
	for id: String in EXISTING:
		var data := _load_or_new(id)
		var entry: Array = EXISTING[id]
		data.model = load(KENNEY + entry[0] + ".glb")
		data.model_scale = entry[1]
		data.sign_color = entry[2]
		data.sign_cross = entry[3]
		data.pollution = entry[4]
		data.noise = entry[5]
		data.land_value = entry[6]
		_save(data)
	for id: String in WIND:
		var entry: Array = WIND[id]
		var data := _load_or_new(id)
		data.display_name = entry[0]
		data.zone = CityGrid.Zone.NONE
		data.grows = false
		data.size = Vector2i.ONE
		data.model = load(_model_path(entry[1]))
		data.model_scale = 1.0
		data.model_turns = 2
		data.sign_color = Color(0, 0, 0, 0)
		data.rotor = load(_model_path(entry[2]))
		data.rotor_pivot = entry[3]
		data.rotor_axis = entry[4]
		data.rotor_speed = entry[5]
		data.cost = entry[6]
		data.upkeep = entry[7]
		data.power_supply = entry[8]
		data.noise = entry[9]
		data.placeholder_color = Color(0.92, 0.94, 0.96)
		data.placeholder_height = 3.0
		_save(data)
	for id: String in PARKS:
		var entry: Array = PARKS[id]
		var data := _load_or_new(id)
		data.display_name = entry[0]
		data.zone = CityGrid.Zone.NONE
		data.grows = false
		data.park = entry[1]
		data.cost = entry[2]
		data.upkeep = entry[3]
		data.land_value = entry[4]
		_save(data)
	print("растущих типов: %d, на покое: %d, служб: %d, парков: %d" % [created, RETIRED.size(), EXISTING.size(), PARKS.size()])
	quit()


## Уровни по объёму модели: меньшие — ур.1, поровну на три уровня.
static func _rank(models: Dictionary) -> Dictionary:
	var ids: Array = models.keys()
	var volume: Dictionary = {}
	for id: String in ids:
		var box: AABB = ModelLoader.bounds(load(_model_path(models[id])))
		volume[id] = box.size.x * box.size.y * box.size.z
	ids.sort_custom(func(a: String, b: String) -> bool: return volume[a] < volume[b])
	var levels: Dictionary = {}
	for i: int in ids.size():
		levels[ids[i]] = 1 + mini(2, i * 3 / ids.size())
	return levels


static func _model_path(relative: String) -> String:
	return (MODELS if relative.begins_with("blender/") else KENNEY) + relative + ".glb"


static func _letter(id: String) -> String:
	return "A" if id.ends_with("_01") else id.get_slice("_", id.get_slice_count("_") - 1).to_upper()


## Типы из пака Gemini: id модели — на её уровне, «id_l1 / _l2 / _l3» — на остальных.
static func _make_pack_types() -> int:
	var file := FileAccess.open(PACK_MANIFEST, FileAccess.READ)
	if file == null:
		push_error("нет %s" % PACK_MANIFEST)
		return 0
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	var count: int = 0
	for model: Dictionary in manifest.models:
		var zone_type: CityGrid.Zone = PACK_ZONES[model.suggested_zone]
		var plot := Vector2i(int(model.cells[0]), int(model.cells[1]))
		var level: int = int(model.suggested_level)
		for lvl: int in [1, 2, 3]:
			var id: String = model.id if lvl == level else "%s_l%d" % [model.id, lvl]
			var data := _load_or_new(id)
			data.display_name = "%s · ур. %d" % [model.display_name, lvl]
			data.grows = true
			data.weight = PACK_WEIGHT if lvl == level else PACK_OTHER_WEIGHT
			data.preferred = true
			LevelStats.apply(data, zone_type, lvl, plot)
			data.model = load(_model_path(model.godot_kit_path))
			data.model_scale = 1.0
			data.model_turns = 2
			_save(data)
			count += 1
	return count


static func _load_or_new(id: String) -> BuildingData:
	var path: String = OUT + id + ".tres"
	var data: BuildingData = load(path) if ResourceLoader.exists(path) else BuildingData.new()
	data.id = StringName(id)
	return data


static func _save(data: BuildingData) -> void:
	var error: Error = ResourceSaver.save(data, OUT + String(data.id) + ".tres")
	if error != OK:
		push_error("не сохранить %s: %s" % [data.id, error_string(error)])
