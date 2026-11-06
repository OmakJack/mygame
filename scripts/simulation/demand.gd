class_name Demand
extends RefCounted
## Спрос R/C/I в [−1, 1]. Держит соотношение жители : заводы : магазины ≈ 1 : 0.7 : 0.3.
## Налог выше нейтрального тормозит рост, ниже — ускоряет (tax_offset).

## Буферы и шкалы — в людях; с 2026-11-01 жителей в доме втрое меньше (LevelStats), они тоже втрое меньше.
## Жители: стремятся к числу рабочих мест + стартовый буфер (пустому городу нужны первые дома).
const R_BUFFER: float = 7.0
const R_SCALE: float = 17.0
## Заводы: базовый работодатель, доля от населения + стартовый буфер.
const I_SHARE: float = 0.7
const I_BUFFER: float = 5.0
const I_SCALE: float = 13.0
## Магазины: появляются после первых жителей.
const C_SHARE: float = 0.3
const C_SCALE: float = 10.0
## Поправка спроса на каждый процент налога от нейтрального (Economy.DEFAULT_TAX_RATE).
const TAX_SENSITIVITY: float = 0.08
## Р5: в большом городе буфер и шкала растут вместе с ним — доля «своей» базы (жители; заводы — 0.7 жителей;
## магазины — 0.3). Буфер 7 человек в городе на 2000 почти не давал спроса (рост стоял), а шкала 17 —
## дом на 40 жителей перекидывал спрос из +1 в −1 (рост рывками). До ~350 жителей — прежние числа.
const BUFFER_SHARE: float = 0.02
const SCALE_SHARE: float = 0.05


static func tax_offset(tax_rate: int) -> float:
	return (Economy.DEFAULT_TAX_RATE - tax_rate) * TAX_SENSITIVITY


## service_offset — поправки от покрытия служб (Services.demand_offset) и трафика (Traffic.demand_offset).
static func residential(population: int, jobs_commercial: int, jobs_industrial: int, tax_rate: int,
		service_offset: float = 0.0) -> float:
	var target: float = jobs_commercial + jobs_industrial + maxf(R_BUFFER, population * BUFFER_SHARE)
	return clampf((target - population) / scale_of(CityGrid.Zone.RESIDENTIAL, population)
			+ tax_offset(tax_rate) + service_offset, -1.0, 1.0)


static func industrial(population: int, jobs_industrial: int, tax_rate: int) -> float:
	var target: float = population * I_SHARE + maxf(I_BUFFER, population * I_SHARE * BUFFER_SHARE)
	return clampf((target - jobs_industrial) / scale_of(CityGrid.Zone.INDUSTRIAL, population)
			+ tax_offset(tax_rate), -1.0, 1.0)


static func commercial(population: int, jobs_commercial: int, tax_rate: int) -> float:
	var target: float = population * C_SHARE
	return clampf((target - jobs_commercial) / scale_of(CityGrid.Zone.COMMERCIAL, population)
			+ tax_offset(tax_rate), -1.0, 1.0)


## Шкала спроса категории (R, C или I) в людях: спрос 1.0 — столько жителей или мест не хватает.
## Рост (Simulation._grow) по ней же знает, сколько строить за тик: спрос × шкала.
static func scale_of(category: CityGrid.Zone, population: int) -> float:
	match category:
		CityGrid.Zone.RESIDENTIAL:
			return maxf(R_SCALE, population * SCALE_SHARE)
		CityGrid.Zone.INDUSTRIAL:
			return maxf(I_SCALE, population * I_SHARE * SCALE_SHARE)
		CityGrid.Zone.COMMERCIAL:
			return maxf(C_SCALE, population * C_SHARE * SCALE_SHARE)
	return 1.0
