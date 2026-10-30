class_name LevelStats
extends RefCounted
## Цифры зданий по зонам и уровням 1..3 (фаза 10) — общие для генератора типов из моделей Kenney
## (tools/generate_building_types.gd) и для зданий, которые строит код (ProceduralBuildings).
## Свет и вода пропорциональны жителям / местам — баланс фаз 4–8 не плывёт.

## Зона → по уровням: [жители, места, свет, вода, дым, шум].
const STATS: Dictionary = {
	CityGrid.Zone.RESIDENTIAL: [[10, 0, 1, 1, 0, 0], [20, 0, 2, 2, 0, 0], [30, 0, 3, 3, 0, 0]],
	CityGrid.Zone.RESIDENTIAL_HIGH: [[60, 0, 6, 6, 0, 4], [90, 0, 9, 9, 0, 5], [120, 0, 12, 12, 0, 6]],
	CityGrid.Zone.COMMERCIAL: [[0, 5, 2, 1, 0, 12], [0, 10, 4, 2, 0, 14], [0, 15, 6, 3, 0, 16]],
	CityGrid.Zone.COMMERCIAL_HIGH: [[0, 30, 8, 4, 0, 18], [0, 45, 12, 6, 0, 20], [0, 60, 16, 8, 0, 22]],
	CityGrid.Zone.INDUSTRIAL: [[0, 8, 3, 2, 30, 15], [0, 16, 6, 4, 35, 16], [0, 24, 9, 6, 40, 18]],
	CityGrid.Zone.OFFICE: [[0, 40, 6, 3, 0, 8], [0, 60, 9, 4, 0, 9], [0, 80, 12, 6, 0, 10]],
}


## Записывает цифры зоны и уровня в тип.
static func apply(data: BuildingData, zone_type: CityGrid.Zone, level: int) -> void:
	var stats: Array = STATS[zone_type][level - 1]
	data.zone = zone_type
	data.level = level
	data.population = stats[0]
	data.jobs = stats[1]
	data.power_use = stats[2]
	data.water_use = stats[3]
	data.pollution = stats[4]
	data.noise = stats[5]
