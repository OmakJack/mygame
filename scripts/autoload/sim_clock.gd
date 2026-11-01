extends Node
## Часы симуляции: шлют Events.sim_tick раз в TICK_SECONDS / speed. 1 тик = GameTime.TICK_MINUTES
## игровых минут (GameState.minutes) — темп как в SimCity 2013 (час — 2 мин на ×1).

## Допустимые скорости: пауза, ×1 (черепаха в SimCity), ×3 (лама), ×8 (гепард).
const SPEEDS: Array[int] = [0, 1, 3, 8]
## Длина тика (игровой минуты) на скорости ×1, секунды: час — 2 мин, сутки — 48 мин.
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
		GameState.minutes += GameTime.TICK_MINUTES
		Events.sim_tick.emit()
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0


## Часы на экране: «14:05».
func time_text() -> String:
	return GameTime.clock(GameState.minutes)


## Реальных секунд в игровом часе на скорости value (для подсказок).
func seconds_per_hour(value: int) -> float:
	return TICK_SECONDS * GameTime.TICKS_PER_HOUR / maxi(1, value)


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
