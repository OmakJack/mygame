class_name LevelStats
extends RefCounted
## Цифры зданий по зонам и уровням 1..3 (фаза 10) — общие для генератора типов из моделей Kenney
## (tools/generate_building_types.gd) и для зданий, которые строит код (ProceduralBuildings).
## Жителей — по семьям, как в Cities: Skylines: частный дом ≈ одна семья (3 человека) на клетку,
## многоэтажка — десятки квартир; места работы — в том же масштабе (2026-11-01, было в 3–6 раз больше).
## Свет и вода — на клетку здания, как раньше: ТЭЦ и водокачки хватает на то же число домов.

## Зона → по уровням: [жители, места, свет, вода, дым, шум].
const STATS: Dictionary = {
	CityGrid.Zone.RESIDENTIAL: [[3, 0, 1, 1, 0, 0], [4, 0, 2, 2, 0, 0], [5, 0, 3, 3, 0, 0]],
	CityGrid.Zone.RESIDENTIAL_HIGH: [[20, 0, 6, 6, 0, 4], [35, 0, 9, 9, 0, 5], [50, 0, 12, 12, 0, 6]],
	CityGrid.Zone.COMMERCIAL: [[0, 2, 2, 1, 0, 12], [0, 3, 4, 2, 0, 14], [0, 5, 6, 3, 0, 16]],
	CityGrid.Zone.COMMERCIAL_HIGH: [[0, 10, 8, 4, 0, 18], [0, 15, 12, 6, 0, 20], [0, 20, 16, 8, 0, 22]],
	CityGrid.Zone.INDUSTRIAL: [[0, 3, 3, 2, 30, 15], [0, 5, 6, 4, 35, 16], [0, 8, 9, 6, 40, 18]],
	CityGrid.Zone.OFFICE: [[0, 13, 6, 3, 0, 8], [0, 20, 9, 4, 0, 9], [0, 27, 12, 6, 0, 10]],
}
## Людей в средней семье — для карточки «Инфо» («9 жителей, 3 семьи»).
const FAMILY_SIZE: float = 3.0


## Сколько семей живёт в доме с population жителями (не меньше одной).
static func families(population: int) -> int:
	return maxi(1, roundi(population / FAMILY_SIZE))


## Записывает цифры зоны и уровня в тип с учётом размера участка (площади в клетках).
static func apply(data: BuildingData, zone_type: CityGrid.Zone, level: int,
		plot_size: Vector2i = Vector2i.ONE) -> void:
	var stats: Array = STATS[zone_type][level - 1]
	var cells: int = maxi(1, plot_size.x * plot_size.y)
	data.zone = zone_type
	data.level = level
	data.size = plot_size
	data.population = stats[0] * cells
	data.jobs = stats[1] * cells
	data.power_use = stats[2] * cells
	data.water_use = stats[3] * cells
	data.pollution = stats[4]
	data.noise = stats[5]
