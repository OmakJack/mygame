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


static func _load_or_new(id: String) -> BuildingData:
	var path: String = OUT + id + ".tres"
	var data: BuildingData = load(path) if ResourceLoader.exists(path) else BuildingData.new()
	data.id = StringName(id)
	return data


static func _save(data: BuildingData) -> void:
	var error: Error = ResourceSaver.save(data, OUT + String(data.id) + ".tres")
	if error != OK:
		push_error("не сохранить %s: %s" % [data.id, error_string(error)])
