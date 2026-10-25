extends Node
## Состояние города: деньги, налог, население, рабочие места, спрос, свет и вода, службы,
## день и сетка. Статистику пишет simulation.gd, деньги меняет только Economy.

var grid: CityGrid
## Имя города (хранится в сохранении).
var city_name: String = "Новый город"
var money: int = Economy.START_MONEY
## Налог, %. Меняется через Events.tax_rate_requested.
var tax_rate: int = Economy.DEFAULT_TAX_RATE
## Доход и расходы за последний день (для UI).
var income: int = 0
var expenses: int = 0
var population: int = 0
var jobs_commercial: int = 0
var jobs_industrial: int = 0
## Спрос R/C/I в [−1, 1]. Здания растут при спросе > 0.
var demand_r: float = 0.0
var demand_c: float = 0.0
var demand_i: float = 0.0
## Номер дня с начала игры (1 тик = 1 день, считает SimClock).
var day: int = 0
## Связные компоненты дорог (пересчитывает simulation.gd).
var network := RoadNetwork.new()
## Последнее распределение света и воды: итоги по городу и запас по компонентам.
var utilities := Utilities.new()
## Покрытие служб в [0, 1].
var service_coverage: Dictionary[BuildingData.Service, float] = {}
## Последний расчёт трафика: нагрузка дорог, время до работы, пути для машинок.
var traffic := Traffic.new()


func _init() -> void:
	# Создаём сетку в _init, чтобы она была готова до _ready любых узлов сцены.
	grid = CityGrid.new(CityGrid.GRID_SIZE)
