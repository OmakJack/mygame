class_name BuildingData
extends Resource
## Описание типа здания (файл .tres в data/buildings/ или генератор кода).
## Размер участка в клетках — size (ширина вдоль фасада −Z × глубина от дороги +Z).
## zone = NONE — служебное здание: ставит игрок за cost, каждый тик списывается upkeep.

enum Service { NONE, SCHOOL, HEALTH, FIRE, POLICE }
## Вид парка (фаза 9): модель собирается из деревьев, клумб и дорожек Kenney.
enum Park { NONE, SQUARE, GARDEN, PLAZA }

## Уникальный строковый id. НИКОГДА не меняется после создания — на нём держатся сохранения.
@export var id: StringName
@export var display_name: String
## На какой зоне растёт. NONE — служебное здание.
@export var zone: CityGrid.Zone = CityGrid.Zone.RESIDENTIAL
## Размер участка в клетках при повороте 0 (N): x — вдоль улицы, y — вглубь квартала.
@export var size: Vector2i = Vector2i.ONE
## Жители (для зданий R).
@export var population: int = 0
## Рабочие места (для зданий C и I).
@export var jobs: int = 0
## Уровень 1..3 (фаза 10): рост ставит ур.1, повышение меняет тип на тип той же зоны следующего уровня.
@export var level: int = 1
## Вес среди типов того же размера, зоны и уровня (рост, повышение).
@export var weight: float = 1.0
## Из архитектурного пака Gemini: такие дома выбираются в BuildingCatalog.PREFERRED_SHARE случаев,
## если есть подходящий по размеру и уровню, — новых домов в городе большинство.
@export var preferred: bool = false
## Растёт ли сам на зоне. false — тип только для служб, сохранений или будущих уровней
## (например, многоэтажки), рост его не выбирает.
@export var grows: bool = true
## Цена постройки и содержание за тик (в интерфейсе — за час) — только для служебных зданий.
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

@export_group("Город вокруг")
## Сила загрязнения (цеха, ТЭЦ), шума (магазины) и прибавки к стоимости земли (парки, службы)
## в своей клетке, 0..100; вокруг слабеет (LandValue).
@export var pollution: int = 0
@export var noise: int = 0
@export var land_value: int = 0
## Парк: вид модели. NONE — не парк.
@export var park: Park = Park.NONE

@export_group("Вид")
## 3D-модель (GLB). Пусто — mesh, а если и его нет — коробка-заглушка.
@export var model: PackedScene
## Масштаб модели; итог всё равно ужимается, чтобы основание влезло в клетку (BuildingMeshes.FOOTPRINT).
@export var model_scale: float = 1.0
## Поворот модели в шагах по 90° по часовой, чтобы фасад смотрел на −Z (у Kenney фасад на +Z → 2).
@export var model_turns: int = 2
## Цвет вывески над служебным зданием; прозрачный — без вывески.
@export var sign_color: Color = Color(0, 0, 0, 0)
## Вывеска-крест (цвет sign_color на белой подложке) вместо таблички — для поликлиники.
@export var sign_cross: bool = false
## Готовый меш вместо модели. Фасад смотрит на −Z.
@export var mesh: Mesh
@export var placeholder_color: Color = Color.WHITE
## Высота заглушки, метры.
@export var placeholder_height: float = 1.5

@export_group("Ротор")
## Вращающаяся часть (ротор ветряка) — отдельная модель, её крутит RotorVisualizer; model — без неё.
@export var rotor: PackedScene
## Ось ротора в координатах модели (до поворота model_turns и вписывания в клетку), метры.
@export var rotor_pivot: Vector3 = Vector3.ZERO
## Вокруг чего крутится, в координатах ротора; знак — направление.
@export var rotor_axis: Vector3 = Vector3.UP
## Оборотов в секунду, пока игра идёт.
@export var rotor_speed: float = 0.25


## Площадь участка в клетках.
func area() -> int:
	return maxi(1, size.x * size.y)


## Габариты участка на сетке (X, Y) с учётом поворота 0..3 (N/E/S/W).
func footprint(orientation: int) -> Vector2i:
	return Vector2i(size.y, size.x) if posmod(orientation, 2) == 1 else size
