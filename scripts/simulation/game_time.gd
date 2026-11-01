class_name GameTime
extends RefCounted
## Игровое время (как в CityRT): на часах идут минуты и часы, из 24 часов складываются сутки.
## Симуляция считает целыми часами — 1 тик = 1 час (GameState.hours, считает SimClock);
## минуты между тиками нужны только часам на экране.

const HOURS_PER_DAY: int = 24
const MINUTES_PER_HOUR: int = 60
## Новый город начинается утром.
const START_HOUR: int = 7
## Часы на экране меняются шагом в столько минут (на ×1 — три раза в секунду).
const CLOCK_STEP: int = 10


## Номер суток, с 1.
@warning_ignore("integer_division")
static func day_of(hours: int) -> int:
	return hours / HOURS_PER_DAY + 1


## Час суток, 0..23.
static func hour_of(hours: int) -> int:
	return posmod(hours, HOURS_PER_DAY)


## «14:20»; fraction — сколько прошло от текущего часа, [0, 1).
static func clock(hours: int, fraction: float = 0.0) -> String:
	var minute: int = floori(clampf(fraction, 0.0, 0.999) * MINUTES_PER_HOUR / CLOCK_STEP) * CLOCK_STEP
	return "%02d:%02d" % [hour_of(hours), minute]


## Часы из сохранения до игрового времени: тогда 1 тик был днём — тот же день, утро.
static func from_old_days(days: int) -> int:
	return maxi(0, days) * HOURS_PER_DAY + START_HOUR
