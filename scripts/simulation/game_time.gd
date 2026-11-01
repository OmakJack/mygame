class_name GameTime
extends RefCounted
## Игровое время (как в SimCity 2013): на часах идут минуты, час на обычной скорости — около
## 2 реальных минут, сутки — 48 минут. Симуляция считает тиками: 1 тик = TICK_MINUTES игровых
## минут (GameState.minutes, считает SimClock). Тиков в реальную секунду — столько же, сколько
## было, когда тик считался днём, поэтому город растёт с прежней скоростью: медленнее идут только часы.

const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = MINUTES_PER_HOUR * HOURS_PER_DAY
## Игровых минут в одном тике симуляции.
const TICK_MINUTES: int = 1
## Тиков в игровом часе: деньги в HUD — «за час» (доход и содержание считаются за тик).
const TICKS_PER_HOUR: int = MINUTES_PER_HOUR / TICK_MINUTES
## Новый город начинается утром.
const START_HOUR: int = 7
const START_MINUTES: int = START_HOUR * MINUTES_PER_HOUR


## Номер суток, с 1.
@warning_ignore("integer_division")
static func day_of(minutes: int) -> int:
	return minutes / MINUTES_PER_DAY + 1


## «14:05».
@warning_ignore("integer_division")
static func clock(minutes: int) -> String:
	var in_day: int = posmod(minutes, MINUTES_PER_DAY)
	return "%02d:%02d" % [in_day / MINUTES_PER_HOUR, in_day % MINUTES_PER_HOUR]


## Сумма за тик → за игровой час (деньги в интерфейсе).
static func per_hour(per_tick: float) -> float:
	return per_tick * TICKS_PER_HOUR


## Сохранение, где 1 тик был днём: тот же день, утро.
static func from_old_days(days: int) -> int:
	return maxi(0, days) * MINUTES_PER_DAY + START_MINUTES


## Сохранение, где 1 тик был часом.
static func from_old_hours(hours: int) -> int:
	return maxi(0, hours) * MINUTES_PER_HOUR
