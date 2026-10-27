class_name Ranks
extends RefCounted
## Звания города по населению (фаза 10, как в CityRT): открывают зоны и дают награду.
## Звание не падает, если жителей стало меньше (GameState.rank).

const NAMES: Array[String] = ["Деревня", "Посёлок", "Городок", "Город", "Большой город", "Мегаполис"]
const THRESHOLDS: Array[int] = [0, 200, 600, 1500, 4000, 10000]
## Награда за новое звание, $.
const REWARDS: Array[int] = [0, 500, 1500, 3000, 6000, 12000]
## С какого звания открывается зона.
const UNLOCKS: Dictionary[CityGrid.Zone, int] = {
	CityGrid.Zone.RESIDENTIAL_HIGH: 2,
	CityGrid.Zone.COMMERCIAL_HIGH: 2,
	CityGrid.Zone.OFFICE: 3,
}


static func for_population(population: int) -> int:
	var rank: int = 0
	for i: int in THRESHOLDS.size():
		if population >= THRESHOLDS[i]:
			rank = i
	return rank


static func is_unlocked(zone_type: CityGrid.Zone, rank: int) -> bool:
	return rank >= UNLOCKS.get(zone_type, 0)


## Что открывает звание — для сообщения.
static func unlocks_of(rank: int) -> PackedStringArray:
	var names: PackedStringArray = []
	for zone_type: CityGrid.Zone in UNLOCKS:
		if UNLOCKS[zone_type] == rank:
			names.append(ZONE_NAMES[zone_type])
	return names


const ZONE_NAMES: Dictionary[CityGrid.Zone, String] = {
	CityGrid.Zone.RESIDENTIAL_HIGH: "многоэтажки",
	CityGrid.Zone.COMMERCIAL_HIGH: "торговые дома",
	CityGrid.Zone.OFFICE: "офисы",
}
