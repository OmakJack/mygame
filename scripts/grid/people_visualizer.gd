class_name PeopleVisualizer
extends TrafficVisualizer
## Пешеходы (по тротуарам) и велосипедисты (у края проезжей части) — только визуал, как машинки.
## Пути — из выборок Traffic.walk_paths / bike_paths; число — по тому, сколько работников
## выбрали ходьбу или велосипед (больше в пробках и на коротких путях).
## Модели — из Blender (tools/blender/make_people.py) в палитре Kenney: одежда и рама велосипеда
## перекрашиваются по INSTANCE_CUSTOM, у каждого свой цвет.

## true — велосипедисты, false — пешеходы.
@export var cyclists: bool = false

const WALKER_MODELS: Array[String] = [
	"res://assets/models/blender/person-a.glb",
	"res://assets/models/blender/person-b.glb",
]
const CYCLIST_MODELS: Array[String] = ["res://assets/models/blender/cyclist.glb"]
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


## Сколько фигурок видно (для проверок).
func visible_people_count() -> int:
	return visible_car_count()
