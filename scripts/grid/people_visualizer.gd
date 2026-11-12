class_name PeopleVisualizer
extends TrafficVisualizer
## Пешеходы (по тротуарам) и велосипедисты (у края проезжей части) — только визуал, как машинки.
## Пути — из выборок Traffic.walk_paths / bike_paths; число — по тому, сколько работников
## выбрали ходьбу или велосипед (больше в пробках и на коротких путях).
## Модели — пак Argon (assets/models/blender/people/, tools/blender/pack_people.py) в палитре Kenney:
## 8 пешеходов и 4 велосипедиста, каждый вид — свой слой, вид выбирается случайно. Одежда и рама
## велосипеда перекрашиваются по INSTANCE_CUSTOM, у каждого свой цвет; кожа, джинсы и колёса — свои.

## true — велосипедисты, false — пешеходы.
@export var cyclists: bool = false

const PEOPLE_DIR: String = "res://assets/models/blender/people/"
const WALKER_MODELS: Array[String] = [
	PEOPLE_DIR + "citizen_casual_m.glb",
	PEOPLE_DIR + "citizen_dress_f.glb",
	PEOPLE_DIR + "citizen_business_m.glb",
	PEOPLE_DIR + "citizen_shopper_f.glb",
	PEOPLE_DIR + "citizen_student_m.glb",
	PEOPLE_DIR + "citizen_coffee_f.glb",
	PEOPLE_DIR + "citizen_hiker_m.glb",
	PEOPLE_DIR + "citizen_coat_f.glb",
]
const CYCLIST_MODELS: Array[String] = [
	PEOPLE_DIR + "cyclist_road.glb",
	PEOPLE_DIR + "cyclist_city_cruiser.glb",
	PEOPLE_DIR + "cyclist_courier.glb",
	PEOPLE_DIR + "cyclist_commuter.glb",
]
## Человек 1.75 м → ~0.39 м: чуть крупнее масштаба машин Kenney (те мультяшно высокие), чтобы фигурки читались сверху.
const PEOPLE_SCALE: float = 0.22
## Сколько работников «изображает» одна фигурка и сколько фигурок не больше.
const WORKERS_PER_PERSON: float = 0.7
const MAX_WALKERS: int = 200
const MAX_CYCLISTS: int = 120
## Скорость, м в секунду на ×1 (машины — TrafficVisualizer.SPEED).
const WALK_SPEED: float = 0.9
const BIKE_SPEED: float = 2.6
## Велосипеды — у края асфальта: на столько ближе к оси, чем край, м.
const BIKE_EDGE: float = 0.16
## Ходьба: подпрыгивание и сколько шагов на метр.
const STEP_HEIGHT: float = 0.012
const STEPS_PER_METER: float = 3.0


func _load_layers() -> void:
	for path: String in (CYCLIST_MODELS if cyclists else WALKER_MODELS):
		if not ResourceLoader.exists(path):
			continue
		var mesh: Mesh = BuildingPalette.convert(ModelLoader.fitted(load(path), PEOPLE_SCALE, CAR_MODEL_TURNS))
		var layer := MultiMeshInstance3D.new()
		layer.multimesh = MultiMesh.new()
		layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		layer.multimesh.use_custom_data = true
		layer.multimesh.mesh = mesh
		layer.multimesh.instance_count = MAX_CARS
		layer.multimesh.visible_instance_count = 0
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(layer)
		_layers.append(layer)
		_weights.append(1.0)


func _paths() -> Array[PackedInt32Array]:
	return GameState.traffic.bike_paths if cyclists else GameState.traffic.walk_paths


func _homes() -> PackedInt32Array:
	return GameState.traffic.bike_homes if cyclists else GameState.traffic.walk_homes


func _target_count() -> int:
	if _layers.is_empty() or _paths().is_empty():
		return 0
	var traffic: Traffic = GameState.traffic
	var people: float = traffic.cyclists if cyclists else traffic.walkers
	return mini(MAX_CYCLISTS if cyclists else MAX_WALKERS, roundi(people / WORKERS_PER_PERSON))


func _speed() -> float:
	return BIKE_SPEED if cyclists else WALK_SPEED


## Пешеходы — по середине тротуара, велосипеды — у края асфальта, по ширине дороги.
func _offset(type: int, _lane: int) -> float:
	var asphalt: float = RoadTypes.ASPHALT_HALF.get(type, RoadTypes.ASPHALT_HALF[RoadTypes.Type.STREET])
	if cyclists:
		return asphalt - BIKE_EDGE
	return (asphalt + RoadTypes.HALF_WIDTH.get(type, RoadTypes.HALF_WIDTH[RoadTypes.Type.STREET])) * 0.5


## Пешеходы и велосипедисты не стоят в очереди и на светофорах (пока нет переходов).
func _obeys_rules() -> bool:
	return false


## Пробки пешеходов и велосипедистов не держат.
func _slowdown(_ratio: float) -> float:
	return 1.0


func _bob(car: Car) -> float:
	if cyclists:
		return 0.0
	return absf(sin(car.distance * PI * STEPS_PER_METER)) * STEP_HEIGHT


## Свой цвет одежды (рамы): тон и насыщенность акцента палитры.
func _dress(car: Car) -> void:
	car.custom = Color(_rng.randf(), _rng.randf_range(0.45, 1.0), 0.0, 1.0)


func travel_mode() -> String:
	return "на велосипеде" if cyclists else "пешком"


## У пешеходов пол — по модели (имя файла кончается на _m или _f).
func agent_gender(car: Car) -> Citizens.Gender:
	if cyclists:
		return Citizens.Gender.ANY
	var path: String = WALKER_MODELS[car.model] if car.model < WALKER_MODELS.size() else ""
	if path.ends_with("_f.glb"):
		return Citizens.Gender.FEMALE
	if path.ends_with("_m.glb"):
		return Citizens.Gender.MALE
	return Citizens.Gender.ANY


## Сколько фигурок видно (для проверок).
func visible_people_count() -> int:
	return visible_car_count()
