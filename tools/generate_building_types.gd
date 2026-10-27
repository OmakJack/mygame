extends SceneTree
## Создаёт типы зданий (data/buildings/*.tres) из моделей Kenney и даёт модели старым типам и службам.
## Запуск: godot --headless --path . --script res://tools/generate_building_types.gd
## Цифры внутри зоны одинаковые (как у старых маленьких домов) — баланс фаз 4–8 не меняется.
## Масштабы наборов сближены (ревью Argon 011): окна и двери одного размера во всём городе.
## Модели служб и многоэтажки не растут сами (grows = false), но остаются в каталоге.
## Старые id (res_small_01, com_small_01, ind_small_01, службы) сохраняются: на них держатся сохранения.

const KENNEY := "res://assets/models/kenney/"
const OUT := "res://data/buildings/"

## Набор → зона, префикс id, название, масштаб, цифры.
const KITS: Array[Dictionary] = [
	{"kit": "suburban", "prefix": "building-type-", "letters": "bcdefghijklmnopqrstu", "id": "res_house_",
		"name": "Дом", "zone": CityGrid.Zone.RESIDENTIAL, "scale": 1.1,
		"population": 10, "jobs": 0, "power": 1, "water": 1, "pollution": 0, "noise": 0},
	{"kit": "commercial", "prefix": "building-", "letters": "bcdefghijklmn", "id": "com_shop_",
		"name": "Магазин", "zone": CityGrid.Zone.COMMERCIAL, "scale": 1.4,
		"population": 0, "jobs": 5, "power": 2, "water": 1, "pollution": 0, "noise": 12},
	{"kit": "industrial", "prefix": "building-", "letters": "bcdefghijklmnopqrst", "id": "ind_factory_",
		"name": "Цех", "zone": CityGrid.Zone.INDUSTRIAL, "scale": 1.0,
		"population": 0, "jobs": 8, "power": 3, "water": 2, "pollution": 30, "noise": 15},
]

## Типы, которые сами не растут: модели служб и многоэтажки (задел под уровни зданий).
const NOT_GROWING: Array[String] = [
	"com_shop_c", "com_shop_h", "com_shop_n",
	"com_shop_f", "com_shop_g", "com_shop_l", "com_shop_m",
	"ind_factory_l",
]

## Старые типы и службы: id → [модель, масштаб, цвет вывески, вывеска-крест, загрязнение, шум, бонус к цене земли].
const EXISTING: Dictionary = {
	"res_small_01": ["suburban/building-type-a", 1.1, Color(0, 0, 0, 0), false, 0, 0, 0],
	"com_small_01": ["commercial/building-a", 1.4, Color(0, 0, 0, 0), false, 0, 12, 0],
	"ind_small_01": ["industrial/building-a", 1.0, Color(0, 0, 0, 0), false, 30, 15, 0],
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
	"park_plaza": ["Площадь", BuildingData.Park.PLAZA, 200, 3, 60],
}


func _initialize() -> void:
	var created: int = 0
	for kit: Dictionary in KITS:
		for letter: String in kit.letters:
			var data := BuildingData.new()
			data.id = StringName(kit.id + letter)
			data.display_name = "%s %s" % [kit.name, letter.to_upper()]
			data.zone = kit.zone
			data.population = kit.population
			data.jobs = kit.jobs
			data.power_use = kit.power
			data.water_use = kit.water
			data.model = load(KENNEY + kit.kit + "/" + kit.prefix + letter + ".glb")
			data.model_scale = kit.scale
			data.pollution = kit.pollution
			data.noise = kit.noise
			data.grows = String(data.id) not in NOT_GROWING
			var error: Error = ResourceSaver.save(data, OUT + String(data.id) + ".tres")
			if error != OK:
				push_error("не сохранить %s: %s" % [data.id, error_string(error)])
			created += 1
	for id: String in EXISTING:
		var path: String = OUT + id + ".tres"
		var data: BuildingData = load(path)
		var entry: Array = EXISTING[id]
		data.model = load(KENNEY + entry[0] + ".glb")
		data.model_scale = entry[1]
		data.sign_color = entry[2]
		data.sign_cross = entry[3]
		data.pollution = entry[4]
		data.noise = entry[5]
		data.land_value = entry[6]
		ResourceSaver.save(data, path)
	for id: String in PARKS:
		var entry: Array = PARKS[id]
		var data := BuildingData.new()
		data.id = StringName(id)
		data.display_name = entry[0]
		data.zone = CityGrid.Zone.NONE
		data.grows = false
		data.park = entry[1]
		data.cost = entry[2]
		data.upkeep = entry[3]
		data.land_value = entry[4]
		ResourceSaver.save(data, OUT + id + ".tres")
	print("создано типов: %d, обновлено: %d, парков: %d" % [created, EXISTING.size(), PARKS.size()])
	quit()
