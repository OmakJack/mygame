extends Node
## Состояние города: деньги, налог, население, рабочие места, спрос, свет и вода, службы,
## игровое время и сетка. Статистику пишет simulation.gd, деньги меняет только Economy.

var grid: CityGrid
## Имя города (хранится в сохранении).
var city_name: String = "Новый город"
var money: int = Economy.START_MONEY
## Налог, %. Меняется через Events.tax_rate_requested.
var tax_rate: int = Economy.DEFAULT_TAX_RATE
## Доход и расходы за тик — прогноз на следующий тик (UI показывает их за игровой час).
var income: int = 0
var expenses: int = 0
var population: int = 0
var jobs_commercial: int = 0
var jobs_industrial: int = 0
## Спрос R/C/I в [−1, 1]. Здания растут при спросе > 0.
var demand_r: float = 0.0
var demand_c: float = 0.0
var demand_i: float = 0.0
## Игровое время в минутах с полуночи первых суток (1 тик = GameTime.TICK_MINUTES, считает SimClock).
var minutes: int = GameTime.START_MINUTES
## Номер суток (с 1) — из minutes.
var day: int:
	get:
		return GameTime.day_of(minutes)
## Связные компоненты дорог (пересчитывает simulation.gd).
var network := RoadNetwork.new()
## Последнее распределение света и воды: итоги по городу и запас по компонентам.
var utilities := Utilities.new()
## Покрытие служб в [0, 1].
var service_coverage: Dictionary[BuildingData.Service, float] = {}
## Последний расчёт трафика: нагрузка дорог, время до работы, пути для машинок.
var traffic := Traffic.new()
## Загрязнение, шум и стоимость земли (фаза 9).
var land := LandValue.new()
## Счастье домов (фаза 10).
var happiness := Happiness.new()
## Звание города (Ranks): не падает; −1 — ещё не выставлено (старое сохранение).
var rank: int = 0
## Случайность симуляции (рост, выбор домов, повышения). Зерно и положение — в сохранении:
## тот же город и те же действия на тех же тиках дают тот же город (баг роста можно повторить).
var rng := RandomNumberGenerator.new()


## Спрос по категориям зон (R, C, I) — для роста, повышений и возвращения жильцов.
func demand_by_zone() -> Dictionary[CityGrid.Zone, float]:
	return {
		CityGrid.Zone.RESIDENTIAL: demand_r,
		CityGrid.Zone.COMMERCIAL: demand_c,
		CityGrid.Zone.INDUSTRIAL: demand_i,
	}


func _init() -> void:
	# Создаём сетку в _init, чтобы она была готова до _ready любых узлов сцены.
	grid = CityGrid.new(CityGrid.GRID_SIZE)
	rng.randomize()
