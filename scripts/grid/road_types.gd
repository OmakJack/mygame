class_name RoadTypes
extends RefCounted
## Типы дорог (фаза 11): улица, проспект, шоссе. Всё, чем они различаются, — здесь.
## Значения Type хранятся в слое CityGrid.road_type и в сохранении (поле roads): 1 — улица
## (так в старых сохранениях все дороги), новые типы — только в конец.

enum Type { NONE, STREET, AVENUE, HIGHWAY }

const NAMES: Dictionary[Type, String] = {
	Type.STREET: "Улица",
	Type.AVENUE: "Проспект",
	Type.HIGHWAY: "Шоссе",
}
## Ёмкость клетки: столько поездок за пересчёт проходит без пробки (Traffic). С 2026-11-01 жителей
## в доме втрое меньше (LevelStats) — и ёмкость втрое меньше, пробки на тех же улицах.
const CAPACITY: Dictionary[Type, float] = {Type.STREET: 27.0, Type.AVENUE: 67.0, Type.HIGHWAY: 107.0}
## Время проезда клетки без пробки: меньше — быстрее (Traffic, базовая цена клетки).
const TRAVEL_COST: Dictionary[Type, float] = {Type.STREET: 1.0, Type.AVENUE: 0.8, Type.HIGHWAY: 0.5}
## Цена клетки и содержание за тик, $ (в интерфейсе — за час).
const BUILD_COST: Dictionary[Type, int] = {Type.STREET: 10, Type.AVENUE: 30, Type.HIGHWAY: 50}
## Цена клетки моста (дорога по воде) за улицу; другие типы — дороже на свою разницу (Economy.BRIDGE_COST).
const BRIDGE_COST: int = 40
const UPKEEP: Dictionary[Type, float] = {Type.STREET: 0.2, Type.AVENUE: 0.5, Type.HIGHWAY: 0.8}
## Во сколько раз громче улицы (LandValue).
const NOISE_FACTOR: Dictionary[Type, float] = {Type.STREET: 1.0, Type.AVENUE: 1.6, Type.HIGHWAY: 2.4}
## Полуширина асфальта и всей дороги с тротуарами, м (клетка — 2 м). По ним рисуется полотно
## (RoadGeometry) и считается, какие клетки дорога занимает (RoadGraph.rasterize). У шоссе тротуаров нет.
const ASPHALT_HALF: Dictionary[Type, float] = {Type.STREET: 0.72, Type.AVENUE: 0.95, Type.HIGHWAY: 1.05}
const HALF_WIDTH: Dictionary[Type, float] = {Type.STREET: 1.0, Type.AVENUE: 1.2, Type.HIGHWAY: 1.05}
## С какого звания города открывается (Ranks): проспект — посёлок, шоссе — городок.
const UNLOCK_RANK: Dictionary[Type, int] = {Type.STREET: 0, Type.AVENUE: 1, Type.HIGHWAY: 2}


## Дают ли дома доступ к дороге: к шоссе дома не подключаются (как в Cities: Skylines).
static func gives_access(road_type: int) -> bool:
	return road_type == Type.STREET or road_type == Type.AVENUE


static func is_unlocked(road_type: int, rank: int) -> bool:
	return rank >= UNLOCK_RANK.get(road_type, 0)
