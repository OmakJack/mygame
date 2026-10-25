class_name Utilities
extends RefCounted
## Распределение света и воды по компонентам дорожной сети.
## В каждом компоненте: сначала служебные здания по id, потом дома R/C/I по id;
## кому не хватило запаса — без ресурса. Вода идёт только от водокачек со светом.

## Свободный запас по компонентам — рост проверяет его перед постройкой дома.
var spare_power: Dictionary[int, int] = {}
var spare_water: Dictionary[int, int] = {}
## Компоненты, где есть станции со светом / водой (для слоя карты).
var powered_components: Dictionary[int, bool] = {}
var watered_components: Dictionary[int, bool] = {}
## Итоги по городу (для HUD и подсказок).
var power_supply: int = 0
var power_use: int = 0
var water_supply: int = 0
var water_use: int = 0
var unpowered_count: int = 0
var no_water_count: int = 0


## Раздаёт свет и воду, выставляет BuildingInstance.powered / has_water.
static func distribute(grid: CityGrid, network: RoadNetwork) -> Utilities:
	var result := Utilities.new()
	# Очередь каждого компонента. buildings идут по возрастанию id (новые id всегда больше).
	var service_queue: Dictionary[int, Array] = {}
	var home_queue: Dictionary[int, Array] = {}
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		var component: int = network.component_for(grid, building.cell)
		if data == null or component == -1:
			# Без дороги — без света и воды.
			building.powered = false
			building.has_water = false
			if data != null:
				result._count_unserved(data, building)
			continue
		var queues: Dictionary[int, Array] = service_queue if data.zone == CityGrid.Zone.NONE else home_queue
		if not queues.has(component):
			queues[component] = []
		queues[component].append(building)

	for component: int in network.component_count:
		var order: Array = service_queue.get(component, []) + home_queue.get(component, [])
		result._distribute_power(component, order)
		result._distribute_water(component, order)
	return result


func _distribute_power(component: int, order: Array) -> void:
	var available: int = 0
	for building: BuildingInstance in order:
		available += BuildingCatalog.get_type(building.type_id).power_supply
	power_supply += available
	if available > 0:
		powered_components[component] = true
	for building: BuildingInstance in order:
		var use: int = BuildingCatalog.get_type(building.type_id).power_use
		power_use += use
		building.powered = use <= available
		if building.powered:
			available -= use
		else:
			unpowered_count += 1
	spare_power[component] = available


func _distribute_water(component: int, order: Array) -> void:
	var available: int = 0
	for building: BuildingInstance in order:
		# Водокачка без света воду не даёт.
		if building.powered:
			available += BuildingCatalog.get_type(building.type_id).water_supply
	water_supply += available
	if available > 0:
		watered_components[component] = true
	for building: BuildingInstance in order:
		var use: int = BuildingCatalog.get_type(building.type_id).water_use
		water_use += use
		building.has_water = use <= available
		if building.has_water:
			available -= use
		else:
			no_water_count += 1
	spare_water[component] = available


## Здание без дороги: учитываем его потребление как необеспеченное.
func _count_unserved(data: BuildingData, building: BuildingInstance) -> void:
	power_use += data.power_use
	water_use += data.water_use
	if data.power_use > 0:
		unpowered_count += 1
	else:
		building.powered = true
	if data.water_use > 0:
		no_water_count += 1
	else:
		building.has_water = true
