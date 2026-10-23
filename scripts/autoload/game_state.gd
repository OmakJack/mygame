extends Node
## Состояние города: деньги, население, дата и сетка.
## Заготовка фазы 1 — экономика и население заполняются в фазах 4–5.

var grid: CityGrid
var money: int = 0
var population: int = 0
## Номер дня с начала игры (считает SimClock в фазе 4).
var day: int = 0


func _init() -> void:
	# Создаём сетку в _init, чтобы она была готова до _ready любых узлов сцены.
	grid = CityGrid.new(CityGrid.GRID_SIZE)
