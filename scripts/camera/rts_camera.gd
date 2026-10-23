extends Node3D
## RTS-камера. Этот узел — точка на земле, вокруг которой вращается камера.
## WASD — движение, колесо — зум, Q/E — поворот.

@export var move_speed: float = 25.0
## Градусов в секунду.
@export var rotate_speed: float = 90.0
## Наклон камеры вниз, градусы.
@export var pitch_degrees: float = 55.0
@export var min_distance: float = 8.0
@export var max_distance: float = 90.0
@export var zoom_step: float = 5.0
## Скорость сглаживания зума (чем больше, тем быстрее; не зависит от FPS).
@export var zoom_smoothing: float = 10.0

var _distance: float = 40.0
var _target_distance: float = 40.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# Стартуем в центре карты.
	var half: float = GameState.grid.world_size() * 0.5
	position = Vector3(half, 0.0, half)
	_apply_distance()


func _process(delta: float) -> void:
	var input: Vector2 = Input.get_vector(&"cam_left", &"cam_right", &"cam_forward", &"cam_back")
	if input != Vector2.ZERO:
		# Движение относительно поворота камеры. Чем дальше камера — тем быстрее.
		var dir: Vector3 = basis * Vector3(input.x, 0.0, input.y)
		position += dir * move_speed * (_distance / 40.0) * delta
		var limit: float = GameState.grid.world_size()
		position.x = clampf(position.x, 0.0, limit)
		position.z = clampf(position.z, 0.0, limit)

	var turn: float = Input.get_axis(&"cam_rotate_right", &"cam_rotate_left")
	rotation.y += deg_to_rad(rotate_speed) * turn * delta

	if _distance != _target_distance:
		if absf(_distance - _target_distance) < 0.01:
			_distance = _target_distance
		else:
			_distance = lerpf(_distance, _target_distance, 1.0 - exp(-zoom_smoothing * delta))
		_apply_distance()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_target_distance = clampf(_target_distance - zoom_step, min_distance, max_distance)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_target_distance = clampf(_target_distance + zoom_step, min_distance, max_distance)


## Ставит камеру на расстояние _distance от точки, наклонённой на pitch_degrees.
func _apply_distance() -> void:
	var pitch: float = deg_to_rad(pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * _distance
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
