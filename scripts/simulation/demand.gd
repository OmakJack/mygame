class_name Demand
extends RefCounted
## Спрос R/C/I в [−1, 1]. Держит соотношение жители : заводы : магазины ≈ 1 : 0.7 : 0.3.
## В фазе 5 из спроса вычитается налоговая поправка.

## Жители: стремятся к числу рабочих мест + стартовый буфер (пустому городу нужны первые дома).
const R_BUFFER: float = 20.0
const R_SCALE: float = 50.0
## Заводы: базовый работодатель, доля от населения + стартовый буфер.
const I_SHARE: float = 0.7
const I_BUFFER: float = 15.0
const I_SCALE: float = 40.0
## Магазины: появляются после первых жителей.
const C_SHARE: float = 0.3
const C_SCALE: float = 30.0


static func residential(population: int, jobs_commercial: int, jobs_industrial: int) -> float:
	var target: float = jobs_commercial + jobs_industrial + R_BUFFER
	return clampf((target - population) / R_SCALE, -1.0, 1.0)


static func industrial(population: int, jobs_industrial: int) -> float:
	var target: float = population * I_SHARE + I_BUFFER
	return clampf((target - jobs_industrial) / I_SCALE, -1.0, 1.0)


static func commercial(population: int, jobs_commercial: int) -> float:
	var target: float = population * C_SHARE
	return clampf((target - jobs_commercial) / C_SCALE, -1.0, 1.0)
