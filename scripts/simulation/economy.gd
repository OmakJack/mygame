class_name Economy
extends RefCounted
## Деньги: цены, налоги, содержание. Единственное место изменения GameState.money —
## spend() при строительстве и apply_day() в тике. Прогноз income/expenses на день
## считает simulation.gd вместе со статистикой.

const START_MONEY: int = 2000
## Цены за реально изменённую клетку. Снос и снятие зоны — бесплатно.
const ROAD_COST: int = 10
const ZONE_COST: int = 5
## Содержание дорог за день, $ за клетку. Служебные здания платят свой BuildingData.upkeep.
const ROAD_UPKEEP: float = 0.2
## Налог, %.
const DEFAULT_TAX_RATE: int = 9
const MIN_TAX_RATE: int = 0
const MAX_TAX_RATE: int = 20
## Доход за день = налоговая база · налог(%) · TAX_FACTOR. База — жители и рабочие места,
## каждое здание с поправкой land_factor на стоимость земли под ним (фаза 9).
const TAX_FACTOR: float = 0.015
## Мост через воду, $ за клетку (обычная дорога — ROAD_COST).
const BRIDGE_COST: int = 40


static func can_afford(amount: int) -> bool:
	return amount <= 0 or GameState.money >= amount


## Списывает деньги за строительство. Возвращает false, если не хватает.
static func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	GameState.money -= amount
	return true


static func daily_income(tax_base: float, tax_rate: int) -> int:
	return roundi(tax_base * tax_rate * TAX_FACTOR)


## Поправка налога на стоимость земли 0..100: обычная земля (LandValue.BASE_VALUE = 25) — ×1,
## пустырь — ×0.8, дорогая — до ×1.6 (ревью Argon 014: средний город платит как до фазы 9).
static func land_factor(land_value: int) -> float:
	return 0.8 + 0.8 * clampi(land_value, 0, 100) / 100.0


## road_upkeep — сумма содержания дорог по типам (RoadTypes.UPKEEP), считает Simulation.
static func daily_expenses(road_upkeep: float, service_upkeep: int = 0) -> int:
	return roundi(road_upkeep) + service_upkeep


## Начисляет доход и списывает расходы за день по прогнозу в GameState.
static func apply_day() -> void:
	GameState.money += GameState.income - GameState.expenses
