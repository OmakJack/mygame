class_name Decay
extends RefCounted
## Упадок зданий, как в SimCity и Cities: Skylines: дом без дороги, без света или воды, или где жителям
## долго плохо (Levels.decline), не исчезает, а пустеет — «заброшено». Брошенное здание темнеет, над ним
## значок, жителей и работы в нём нет, налогов и света с водой оно не берёт, а цену земли вокруг тянет
## вниз (LandValue.ABANDONED_PENALTY). Снести — бульдозером; исправили причину и есть спрос — через RECOVER_TICKS в него въезжают
## снова (короткая стройка-ремонт). Служебные здания не пустеют.

## Через сколько тиков без дороги здание пустеет: 2 игровых часа (4 минуты при ×1) — время провести
## дорогу заново; до того над крышей значок «нет дороги». Стройплощадка без дороги за этот срок исчезает.
const NO_ROAD_TICKS: int = 2 * GameTime.TICKS_PER_HOUR
## Без света или воды — 6 игровых часов (12 минут при ×1): дома растут и без них, есть время
## поставить станцию.
const NO_UTILITY_TICKS: int = 6 * GameTime.TICKS_PER_HOUR
## Сколько тиков подряд причина должна быть исправлена, чтобы в дом въехали снова: 1 игровой час.
const RECOVER_TICKS: int = GameTime.TICKS_PER_HOUR
## Счастье, при котором в брошенный дом въезжают снова. Выше порога упадка (Levels.DECLINE_HAPPINESS),
## чтобы дом не пустел и не заселялся по кругу.
const RECOVER_HAPPINESS: int = 35


## Счётчики дороги, света и воды; у кого срок вышел — пустеет (стройплощадка — исчезает). Брошенные
## здания при исправленной причине и спросе заселяются снова. Возвращает изменённые клетки.
static func step(grid: CityGrid, network: RoadNetwork, land: LandValue, traffic: Traffic, tax_rate: int,
		demands: Dictionary[CityGrid.Zone, float]) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var gone: Array[int] = []
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or data.zone == CityGrid.Zone.NONE:
			continue
		if building.abandoned:
			if recover_blockers(grid, building, data, network, land, traffic, tax_rate, demands).is_empty():
				building.recover_ticks += 1
				if building.recover_ticks >= RECOVER_TICKS:
					recover(grid, building, data)
					changed.append_array(building.cells())
			else:
				building.recover_ticks = 0
			continue
		building.no_road_ticks = 0 if grid.has_building_road_access(building) else building.no_road_ticks + 1
		var building_site: bool = building.construction_ticks > 0
		building.no_power_ticks = 0 if building.powered or building_site else building.no_power_ticks + 1
		building.no_water_ticks = 0 if building.has_water or building_site else building.no_water_ticks + 1
		if ticks_left(building) != 0:
			continue
		if building_site:
			gone.append(building.id)
		else:
			abandon(grid, building)
			changed.append_array(building.cells())
	# Удаляем после обхода, чтобы не менять словарь во время итерации.
	for id: int in gone:
		changed.append_array(grid.buildings[id].cells())
		grid.remove_building(id)
	return changed


## Сколько тиков зданию осталось до упадка из-за дороги, света или воды; −1 — ничего не грозит.
static func ticks_left(building: BuildingInstance) -> int:
	var left: int = -1
	if building.no_road_ticks > 0:
		left = NO_ROAD_TICKS - building.no_road_ticks
	for missing: int in [building.no_power_ticks, building.no_water_ticks]:
		if missing > 0:
			left = NO_UTILITY_TICKS - missing if left < 0 else mini(left, NO_UTILITY_TICKS - missing)
	return maxi(left, 0) if left >= 0 else -1


## Здание пустеет: жители и работники уходят, счётчики — с нуля.
static func abandon(grid: CityGrid, building: BuildingInstance) -> void:
	building.abandoned = true
	building.recover_ticks = 0
	building.no_road_ticks = 0
	building.no_power_ticks = 0
	building.no_water_ticks = 0
	building.unhappy_ticks = 0
	building.construction_ticks = 0
	grid.buildings_version += 1


## В брошенное здание въезжают снова — после короткой стройки-ремонта.
static func recover(grid: CityGrid, building: BuildingInstance, data: BuildingData) -> void:
	building.abandoned = false
	building.recover_ticks = 0
	Levels.start_construction(building, data)
	grid.buildings_version += 1


## Что мешает въехать в брошенное здание; пусто — въедут через RECOVER_TICKS (для тика и карточки «Инфо»).
## Свет и воду для брошенного здания Utilities.distribute считает «хватило бы запаса».
static func recover_blockers(grid: CityGrid, building: BuildingInstance, data: BuildingData, network: RoadNetwork,
		land: LandValue, traffic: Traffic, tax_rate: int, demands: Dictionary[CityGrid.Zone, float]) -> PackedStringArray:
	var result: PackedStringArray = []
	if not grid.has_building_road_access(building):
		result.append("нет дороги")
	elif grid.has_entry() and network.component_for_building(grid, building) != network.component_of.get(grid.entry, -2):
		result.append("нет пути до трассы")
	if data.power_use > 0 and not building.powered:
		result.append("нет света")
	if data.water_use > 0 and not building.has_water:
		result.append("нет воды")
	if data.population > 0:
		var mood: int = Happiness.score_of(Happiness.factors(grid, building, data, land, traffic, tax_rate))
		if mood < RECOVER_HAPPINESS:
			result.append("счастье %d из %d" % [mood, RECOVER_HAPPINESS])
	if demands.get(CityGrid.zone_category(data.zone), 0.0) <= 0.0:
		result.append("нет спроса")
	return result
