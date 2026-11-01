extends Node
## Часы симуляции: шлют Events.sim_tick раз в TICK_SECONDS / speed. 1 тик = 1 игровой час
## (GameState.hours); минуты между тиками — для часов на экране (time_text).

## Допустимые скорости: пауза, ×1, ×3.
const SPEEDS: Array[int] = [0, 1, 3]
## Длина игрового часа (тика) на скорости ×1, секунды: сутки — 48 с, на ×3 — 16 с.
const TICK_SECONDS: float = 2.0
## Больше тиков за кадр не делаем, даже если кадр был очень долгим.
const MAX_TICKS_PER_FRAME: int = 3

var speed: int = 1

## Скорость до паузы — к ней возвращаемся по Пробелу.
var _speed_before_pause: int = 1
var _accumulator: float = 0.0


func _ready() -> void:
	# Новая карта — начинаем отсчёт тика заново.
	Events.grid_reset.connect(func() -> void: _accumulator = 0.0)


func _process(delta: float) -> void:
	if speed == 0:
		return
	_accumulator += delta * speed
	var ticks: int = 0
	while _accumulator >= TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_SECONDS
		ticks += 1
		GameState.hours += 1
		Events.sim_tick.emit()
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0


## Сколько прошло от текущего игрового часа, [0, 1).
func hour_fraction() -> float:
	return clampf(_accumulator / TICK_SECONDS, 0.0, 0.999)


## Часы на экране: «14:20».
func time_text() -> String:
	return GameTime.clock(GameState.hours, hour_fraction())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"sim_pause"):
		toggle_pause()


func set_speed(new_speed: int) -> void:
	if new_speed not in SPEEDS:
		push_error("SimClock: недопустимая скорость %d" % new_speed)
		return
	if new_speed != 0:
		_speed_before_pause = new_speed
	if new_speed == speed:
		return
	speed = new_speed
	Events.speed_changed.emit(speed)


func toggle_pause() -> void:
	set_speed(_speed_before_pause if speed == 0 else 0)
