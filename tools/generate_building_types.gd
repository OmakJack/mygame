extends SceneTree
## Создаёт типы зданий (data/buildings/*.tres) из моделей Kenney и даёт модели старым типам и службам.
## Запуск: godot --headless --path . --script res://tools/generate_building_types.gd
## Цифры внутри зоны одинаковые (как у старых маленьких домов) — баланс фаз 4–8 не меняется.
## Старые id (res_small_01, com_small_01, ind_small_01, службы) сохраняются: на них держатся сохранения.

const KENNEY := "res://assets/models/kenney/"
const OUT := "res://data/buildings/"

## Набор → зона, префикс id, название, масштаб, цифры.
const KITS: Array[Dictionary] = [
	{"kit": "suburban", "prefix": "building-type-", "letters": "bcdefghijklmnopqrstu", "id": "res_house_",
		"name": "Дом", "zone": CityGrid.Zone.RESIDENTIAL, "scale": 1.35,
		"population": 10, "jobs": 0, "power": 1, "water": 1},
	{"kit": "commercial", "prefix": "building-", "letters": "bcdefghijklmn", "id": "com_shop_",
		"name": "Магазин", "zone": CityGrid.Zone.COMMERCIAL, "scale": 1.9,
		"population": 0, "jobs": 5, "power": 2, "water": 1},
	{"kit": "industrial", "prefix": "building-", "letters": "bcdefghijklmnopqrst", "id": "ind_factory_",
		"name": "Цех", "zone": CityGrid.Zone.INDUSTRIAL, "scale": 0.95,
		"population": 0, "jobs": 8, "power": 3, "water": 2},
]

## Старые типы и службы: id → [модель, масштаб, цвет вывески].
const EXISTING: Dictionary = {
	"res_small_01": ["suburban/building-type-a", 1.35, Color(0, 0, 0, 0)],
	"com_small_01": ["commercial/building-a", 1.9, Color(0, 0, 0, 0)],
	"ind_small_01": ["industrial/building-a", 0.95, Color(0, 0, 0, 0)],
	"power_plant_01": ["industrial/chimney-large", 1.2, Color(0, 0, 0, 0)],
	"water_tower_01": ["industrial/water-tower", 1.0, Color(0, 0, 0, 0)],
	"school_01": ["commercial/building-c", 1.9, Color(0.98, 0.8, 0.2)],
	"health_01": ["commercial/building-m", 1.9, Color(0.95, 0.25, 0.25)],
	"fire_01": ["industrial/building-t", 0.95, Color(0.9, 0.3, 0.1)],
	"police_01": ["commercial/building-h", 1.9, Color(0.2, 0.4, 0.9)],
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
		ResourceSaver.save(data, path)
	print("создано типов: %d, обновлено: %d" % [created, EXISTING.size()])
	quit()
