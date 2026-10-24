extends Node
## Состояние города: деньги, население, рабочие места, спрос, день и сетка.
## Значения статистики пишет simulation.gd на каждом тике.

var grid: CityGrid
## Деньги — фаза 5.
var money: int = 0
var population: int = 0
var jobs_commercial: int = 0
var jobs_industrial: int = 0
## Спрос R/C/I в [−1, 1]. Здания растут при спросе > 0.
var demand_r: float = 0.0
var demand_c: float = 0.0
var demand_i: float = 0.0
## Номер дня с начала игры (1 тик = 1 день, считает SimClock).
var day: int = 0


func _init() -> void:
	# Создаём сетку в _init, чтобы она была готова до _ready любых узлов сцены.
	grid = CityGrid.new(CityGrid.GRID_SIZE)
