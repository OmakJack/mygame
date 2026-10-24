class_name BuildingData
extends Resource
## Описание типа здания (файл .tres в data/buildings/). В MVP все здания 1×1.

## Уникальный строковый id. НИКОГДА не меняется после создания — на нём держатся сохранения.
@export var id: StringName
@export var display_name: String
## На какой зоне растёт.
@export var zone: CityGrid.Zone = CityGrid.Zone.RESIDENTIAL
## Жители (для зданий R).
@export var population: int = 0
## Рабочие места (для зданий C и I).
@export var jobs: int = 0
## Стоимость и содержание — используются в фазе 5.
@export var cost: int = 0
@export var upkeep: int = 0

@export_group("Вид")
## Модель здания. Фасад смотрит на −Z. Пусто — коробка-заглушка.
@export var mesh: Mesh
@export var placeholder_color: Color = Color.WHITE
## Высота заглушки, метры.
@export var placeholder_height: float = 1.5
