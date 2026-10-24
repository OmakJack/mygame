class_name Economy
extends RefCounted
## Деньги: цены, налоги, содержание. Единственное место изменения GameState.money —
## spend() при строительстве и apply_day() в тике.

const START_MONEY: int = 2000
## Цены за реально изменённую клетку. Снос и снятие зоны — бесплатно.
const ROAD_COST: int = 10
const ZONE_COST: int = 5
## Содержание дорог за день, $ за клетку.
const ROAD_UPKEEP: float = 0.2
## Налог, %.
const DEFAULT_TAX_RATE: int = 9
const MIN_TAX_RATE: int = 0
const MAX_TAX_RATE: int = 20
## Доход за день = (жители + рабочие места) · налог(%) · TAX_FACTOR.
const TAX_FACTOR: float = 0.01


static func can_afford(amount: int) -> bool:
	return amount <= 0 or GameState.money >= amount


## Списывает деньги за строительство. Возвращает false, если не хватает.
static func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	GameState.money -= amount
	return true


static func daily_income(population: int, jobs: int, tax_rate: int) -> int:
	return roundi((population + jobs) * tax_rate * TAX_FACTOR)


static func daily_expenses(road_cells: int) -> int:
	return roundi(road_cells * ROAD_UPKEEP)


## Начисляет доход и списывает расходы за день; записывает их в GameState для UI.
static func apply_day() -> void:
	var jobs: int = GameState.jobs_commercial + GameState.jobs_industrial
	GameState.income = daily_income(GameState.population, jobs, GameState.tax_rate)
	GameState.expenses = daily_expenses(GameState.grid.road_cells.size())
	GameState.money += GameState.income - GameState.expenses
