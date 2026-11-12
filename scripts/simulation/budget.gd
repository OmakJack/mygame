class_name Budget
extends RefCounted
## Бюджет по статьям, как в Cities: Skylines: доходы — налоги по зонам, расходы — содержание дорог
## по типам, станций света и воды, служб и парков. Считается вместе со статистикой (Simulation)
## и только для показа (вкладка «Бюджет», BudgetPanel): деньги по-прежнему двигают GameState.income
## и expenses. Статьи подогнаны так, чтобы их сумма совпадала с итогом (иначе расходилось бы
## на округлении). History — суммы по игровым часам для графиков, хранится в сохранении.

## Статья бюджета.
class Item extends RefCounted:
	var id: StringName
	var name: String
	var icon: String
	var color: Color
	## $ за тик.
	var per_tick: float = 0.0
	## Сколько зданий или клеток дороги платят или стоят.
	var count: int = 0
	## «зд.» или «кл.»
	var unit: String = "зд."

	func _init(item_id: StringName, item_name: String, item_icon: String, item_color: Color, item_unit: String = "зд.") -> void:
		id = item_id
		name = item_name
		icon = item_icon
		color = item_color
		unit = item_unit

	## $ за игровой час.
	func per_hour() -> float:
		return GameTime.per_hour(per_tick)


## Суммы по игровым часам: доход, расход и казна в конце часа. Не больше MAX_HOURS последних часов.
class History extends RefCounted:
	const MAX_HOURS: int = 168
	## Номер часа от начала игры (minutes / 60) — для подписей на графике.
	var hours := PackedInt32Array()
	var income := PackedInt64Array()
	var expenses := PackedInt64Array()
	var money := PackedInt64Array()
	## Текущий, ещё не закончившийся час.
	var hour_income: int = 0
	var hour_expenses: int = 0

	## После тика: деньги тика копятся в текущий час; на круглом часе час закрывается.
	func record(minutes: int, tick_income: int, tick_expenses: int, money_now: int) -> void:
		hour_income += tick_income
		hour_expenses += tick_expenses
		if minutes % GameTime.MINUTES_PER_HOUR != 0:
			return
		hours.append(minutes / GameTime.MINUTES_PER_HOUR - 1)
		income.append(hour_income)
		expenses.append(hour_expenses)
		money.append(money_now)
		hour_income = 0
		hour_expenses = 0
		if hours.size() > MAX_HOURS:
			var drop: int = hours.size() - MAX_HOURS
			hours = hours.slice(drop)
			income = income.slice(drop)
			expenses = expenses.slice(drop)
			money = money.slice(drop)

	func size() -> int:
		return hours.size()

	func to_dict() -> Dictionary:
		return {"h": Array(hours), "i": Array(income), "e": Array(expenses), "m": Array(money),
				"hi": hour_income, "he": hour_expenses}

	## Из сохранения; битые или разной длины списки — пустая история.
	static func from_dict(data: Variant) -> History:
		var result := History.new()
		if not data is Dictionary:
			return result
		var lists: Array = [data.get("h"), data.get("i"), data.get("e"), data.get("m")]
		for list: Variant in lists:
			if not list is Array or (list as Array).size() != (lists[0] as Array).size():
				return result
		var count: int = (lists[0] as Array).size()
		for at: int in range(maxi(0, count - MAX_HOURS), count):
			result.hours.append(int(lists[0][at]))
			result.income.append(int(lists[1][at]))
			result.expenses.append(int(lists[2][at]))
			result.money.append(int(lists[3][at]))
		result.hour_income = int(data.get("hi", 0))
		result.hour_expenses = int(data.get("he", 0))
		return result


const ZONE_ITEMS: Array[Array] = [
	[CityGrid.Zone.RESIDENTIAL, &"res", "Частные дома", "tool_zone_r", Color(0.36, 0.74, 0.36)],
	[CityGrid.Zone.RESIDENTIAL_HIGH, &"res_high", "Многоэтажки", "tool_zone_r_high", Color(0.16, 0.52, 0.30)],
	[CityGrid.Zone.COMMERCIAL, &"com", "Магазины", "tool_zone_c", Color(0.33, 0.58, 0.93)],
	[CityGrid.Zone.COMMERCIAL_HIGH, &"com_high", "Торговые дома", "tool_zone_c_high", Color(0.20, 0.34, 0.74)],
	[CityGrid.Zone.INDUSTRIAL, &"ind", "Промзона", "tool_zone_i", Color(0.93, 0.72, 0.20)],
	[CityGrid.Zone.OFFICE, &"office", "Офисы", "tool_zone_o", Color(0.56, 0.42, 0.80)],
]
const ROAD_ITEMS: Array[Array] = [
	[RoadTypes.Type.STREET, &"street", "Улицы", "tool_road", Color(0.52, 0.56, 0.62)],
	[RoadTypes.Type.AVENUE, &"avenue", "Проспекты", "tool_avenue", Color(0.36, 0.40, 0.48)],
	[RoadTypes.Type.HIGHWAY, &"highway", "Шоссе", "tool_highway", Color(0.22, 0.24, 0.30)],
]
const SERVICE_ITEMS: Array[Array] = [
	[&"power", "Свет", "stat_power", Color(0.96, 0.62, 0.18)],
	[&"water", "Вода", "stat_water", Color(0.25, 0.66, 0.86)],
	[&"school", "Школы", "school_01", Color(0.62, 0.46, 0.30)],
	[&"health", "Больницы", "health_01", Color(0.86, 0.32, 0.34)],
	[&"fire", "Пожарные", "fire_01", Color(0.92, 0.42, 0.18)],
	[&"police", "Полиция", "police_01", Color(0.24, 0.36, 0.62)],
	[&"parks", "Парки", "park_square", Color(0.20, 0.62, 0.52)],
	[&"other", "Прочее", "tool_overlay", Color(0.60, 0.56, 0.50)],
]

var income: Array[Item] = []
var expenses: Array[Item] = []
## Итоги за тик — те же, что GameState.income и expenses.
var income_total: int = 0
var expenses_total: int = 0


func income_per_hour() -> float:
	return GameTime.per_hour(income_total)


func expenses_per_hour() -> float:
	return GameTime.per_hour(expenses_total)


## Статья по id (для проверок); null — нет такой.
func item(id: StringName) -> Item:
	for entry: Item in income + expenses:
		if entry.id == id:
			return entry
	return null


## Разбивка города: налоги — как Simulation._tax_base (жители и места с поправкой на землю),
## содержание — как в Simulation._update_stats. Итоги — готовые income и expenses за тик.
static func compute(grid: CityGrid, land: LandValue, tax_rate: int, income_tick: int, expenses_tick: int) -> Budget:
	var budget := Budget.new()
	budget.income_total = income_tick
	budget.expenses_total = expenses_tick
	var by_zone: Dictionary[CityGrid.Zone, Item] = {}
	for row: Array in ZONE_ITEMS:
		var entry := Item.new(row[1], row[2], row[3], row[4])
		budget.income.append(entry)
		by_zone[row[0]] = entry
	var by_road: Dictionary[int, Item] = {}
	for row: Array in ROAD_ITEMS:
		var entry := Item.new(row[1], row[2], row[3], row[4], "кл.")
		budget.expenses.append(entry)
		by_road[row[0]] = entry
	var by_service: Dictionary[StringName, Item] = {}
	for row: Array in SERVICE_ITEMS:
		var entry := Item.new(row[0], row[1], row[2], row[3])
		budget.expenses.append(entry)
		by_service[row[0]] = entry

	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or building.abandoned:
			continue
		if data.population + data.jobs > 0 and by_zone.has(data.zone):
			var value: int = land.building_value(land.land_value, grid, building)
			var tax: Item = by_zone[data.zone]
			tax.per_tick += (data.population + data.jobs) * Economy.land_factor(value) * tax_rate * Economy.TAX_FACTOR
			tax.count += 1
		if data.zone == CityGrid.Zone.NONE:
			var upkeep: int = StationModules.upkeep(building, data)
			if upkeep <= 0:
				continue
			var cost: Item = by_service[_service_kind(data)]
			cost.per_tick += upkeep
			cost.count += 1
	for road: Vector2i in grid.road_cells:
		var type: int = grid.road_type[grid.index_of(road)]
		var cost: Item = by_road.get(type, by_road[RoadTypes.Type.STREET])
		cost.per_tick += RoadTypes.UPKEEP.get(type, Economy.ROAD_UPKEEP)
		cost.count += 1
	_fit(budget.income, income_tick)
	_fit(budget.expenses, expenses_tick)
	return budget


static func _service_kind(data: BuildingData) -> StringName:
	if data.power_supply > 0:
		return &"power"
	if data.water_supply > 0:
		return &"water"
	if data.park != BuildingData.Park.NONE:
		return &"parks"
	match data.service:
		BuildingData.Service.SCHOOL:
			return &"school"
		BuildingData.Service.HEALTH:
			return &"health"
		BuildingData.Service.FIRE:
			return &"fire"
		BuildingData.Service.POLICE:
			return &"police"
	return &"other"


## Статьи — в долях от точного итога: сумма статей = итог за тик (тот округлён).
static func _fit(items: Array[Item], total: int) -> void:
	var raw: float = 0.0
	for entry: Item in items:
		raw += entry.per_tick
	if raw <= 0.0:
		return
	var scale: float = total / raw
	for entry: Item in items:
		entry.per_tick *= scale
