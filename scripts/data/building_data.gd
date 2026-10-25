class_name BuildingData
extends Resource
## Описание типа здания (файл .tres в data/buildings/). Пока все здания 1×1.
## zone = NONE — служебное здание: ставит игрок за cost, каждый день списывается upkeep.

enum Service { NONE, SCHOOL, HEALTH, FIRE, POLICE }

## Уникальный строковый id. НИКОГДА не меняется после создания — на нём держатся сохранения.
@export var id: StringName
@export var display_name: String
## На какой зоне растёт. NONE — служебное здание.
@export var zone: CityGrid.Zone = CityGrid.Zone.RESIDENTIAL
## Жители (для зданий R).
@export var population: int = 0
## Рабочие места (для зданий C и I).
@export var jobs: int = 0
## Цена постройки и содержание за день — только для служебных зданий.
@export var cost: int = 0
@export var upkeep: int = 0

@export_group("Свет и вода")
## Сколько даёт (ТЭЦ, водокачка).
@export var power_supply: int = 0
@export var water_supply: int = 0
## Сколько потребляет.
@export var power_use: int = 0
@export var water_use: int = 0

@export_group("Служба")
@export var service: Service = Service.NONE
## Радиус покрытия в клетках (по Манхэттену).
@export var service_radius: int = 0

@export_group("Вид")
## 3D-модель (GLB). Пусто — mesh, а если и его нет — коробка-заглушка.
@export var model: PackedScene
## Масштаб модели; итог всё равно ужимается, чтобы основание влезло в клетку (BuildingMeshes.FOOTPRINT).
@export var model_scale: float = 1.0
## Поворот модели в шагах по 90° по часовой, чтобы фасад смотрел на −Z (у Kenney фасад на +Z → 2).
@export var model_turns: int = 2
## Цвет вывески над служебным зданием; прозрачный — без вывески.
@export var sign_color: Color = Color(0, 0, 0, 0)
## Готовый меш вместо модели. Фасад смотрит на −Z.
@export var mesh: Mesh
@export var placeholder_color: Color = Color.WHITE
## Высота заглушки, метры.
@export var placeholder_height: float = 1.5
