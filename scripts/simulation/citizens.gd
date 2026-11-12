class_name Citizens
extends RefCounted
## Жители для карточки над фигуркой: имя, возраст, работа, семья, питомец, увлечение.
## Ничего не хранится и не сохраняется: житель выводится из дома, пути и зерна фигурки
## (одни и те же — один и тот же человек). Симуляция считает людей числами, а не поимённо.

## Один житель.
class Citizen extends RefCounted:
	var first_name: String = ""
	var last_name: String = ""
	var male: bool = true
	var age: int = 30
	## id дома (−1 — живёт за городом, приезжает по трассе).
	var home_id: int = -1
	## id здания, где работает (−1 — не нашли).
	var work_id: int = -1
	## Кем работает: «бариста», «сварщица».
	var job: String = ""
	## Семья одной строкой: «жена Ольга, дети: Миша (7), Аня (3)», «живёт один».
	var family: String = ""
	## Сколько человек в семье вместе с ним.
	var family_size: int = 1
	## «кот Барсик» или пусто.
	var pet: String = ""
	var hobby: String = ""

	func full_name() -> String:
		return first_name + " " + last_name


## Пол фигурки: по модели (у пешеходов он в имени файла), иначе — случайный.
enum Gender { ANY, MALE, FEMALE }

const MALE_NAMES: Array[String] = ["Андрей", "Олег", "Дмитрий", "Сергей", "Максим", "Иван", "Артём", "Тарас",
	"Богдан", "Николай", "Павел", "Юрий", "Виктор", "Роман", "Денис", "Евгений", "Игорь", "Владимир",
	"Алексей", "Михаил", "Антон", "Василий", "Кирилл", "Степан"]
const FEMALE_NAMES: Array[String] = ["Ольга", "Анна", "Мария", "Елена", "Ирина", "Наталья", "Оксана", "Светлана",
	"Юлия", "Татьяна", "Дарина", "Кристина", "Виктория", "Алина", "Екатерина", "Софья", "Людмила", "Галина",
	"Полина", "Вера", "Марина", "Надежда", "Леся", "Яна"]
const BOY_NAMES: Array[String] = ["Миша", "Саша", "Тёма", "Ваня", "Максим", "Матвей", "Лёша", "Дима", "Костя",
	"Назар", "Егор", "Тимур"]
const GIRL_NAMES: Array[String] = ["Аня", "Маша", "Соня", "Катя", "Лиза", "Даша", "Вика", "Поля", "Злата",
	"Ева", "Настя", "Уля"]
## Фамилии: [мужская, женская].
const SURNAMES: Array[Array] = [["Коваленко", "Коваленко"], ["Шевченко", "Шевченко"], ["Бондаренко", "Бондаренко"],
	["Ткаченко", "Ткаченко"], ["Кравченко", "Кравченко"], ["Мельник", "Мельник"], ["Бойко", "Бойко"],
	["Ковальчук", "Ковальчук"], ["Полищук", "Полищук"], ["Олейник", "Олейник"], ["Руденко", "Руденко"],
	["Лысенко", "Лысенко"], ["Иванов", "Иванова"], ["Петров", "Петрова"], ["Смирнов", "Смирнова"],
	["Соколов", "Соколова"], ["Морозов", "Морозова"], ["Волков", "Волкова"], ["Лебедев", "Лебедева"],
	["Новиков", "Новикова"], ["Орлов", "Орлова"], ["Белов", "Белова"], ["Калинин", "Калинина"],
	["Зайцев", "Зайцева"], ["Ковальский", "Ковальская"], ["Вишневский", "Вишневская"], ["Яблонский", "Яблонская"]]
## Работа по зоне здания: [мужская форма, женская].
const JOBS: Dictionary = {
	CityGrid.Zone.COMMERCIAL: [["продавец", "продавщица"], ["кассир", "кассир"], ["бариста", "бариста"],
		["повар", "повар"], ["официант", "официантка"], ["пекарь", "пекарь"], ["администратор", "администратор"]],
	CityGrid.Zone.COMMERCIAL_HIGH: [["консультант", "консультант"], ["менеджер зала", "менеджер зала"],
		["кассир", "кассир"], ["охранник", "охранница"], ["мерчендайзер", "мерчендайзер"], ["товаровед", "товаровед"]],
	CityGrid.Zone.OFFICE: [["менеджер", "менеджер"], ["бухгалтер", "бухгалтер"], ["программист", "программистка"],
		["юрист", "юрист"], ["аналитик", "аналитик"], ["дизайнер", "дизайнер"], ["секретарь", "секретарь"]],
	CityGrid.Zone.INDUSTRIAL: [["оператор станка", "оператор станка"], ["сварщик", "сварщица"],
		["технолог", "технолог"], ["кладовщик", "кладовщица"], ["слесарь", "слесарь"], ["мастер участка", "мастер участка"],
		["водитель погрузчика", "водитель погрузчика"]],
}
const PETS: Array[String] = ["кот Барсик", "кошка Мурка", "кот Рыжик", "собака Рекс", "собака Бублик",
	"пёс Шарик", "попугай Кеша", "хомяк Пончик", "кошка Соня"]
const HOBBIES: Array[String] = ["футбол", "рыбалка", "шахматы", "велопрогулки", "готовить", "сад и огород",
	"настольные игры", "фотография", "бег по утрам", "гитара", "читать детективы", "вязание", "походы",
	"компьютерные игры", "танцы", "кино"]
## Доля жителей с питомцем.
const PET_SHARE: float = 0.35
## С какого возраста у жителя бывают дети (старший ребёнок младше его на столько лет).
const PARENT_AGE: int = 20
## Дети живут с родителями до этого возраста.
const CHILD_MAX_AGE: int = 17


## Житель фигурки: дом home_id, путь path (клетки от дороги дома до дороги работы),
## зерно фигурки agent_seed. job_sites — Traffic.job_sites (у какой дороги какие работы).
static func make(grid: CityGrid, job_sites: Dictionary[int, PackedInt32Array], home_id: int,
		path: PackedInt32Array, agent_seed: int, gender: Gender = Gender.ANY) -> Citizen:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([home_id, agent_seed])
	var person := Citizen.new()
	person.home_id = home_id
	person.male = rng.randf() < 0.5 if gender == Gender.ANY else gender == Gender.MALE
	person.first_name = _pick(rng, MALE_NAMES if person.male else FEMALE_NAMES)
	var surname: Array = SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)]
	person.last_name = surname[0] if person.male else surname[1]
	person.age = rng.randi_range(19, 64)
	person.work_id = _work_of(grid, job_sites, path, rng)
	person.job = _job_of(grid, person.work_id, person.male, rng)
	_make_family(grid, person, rng)
	person.pet = _pick(rng, PETS) if rng.randf() < PET_SHARE else ""
	person.hobby = _pick(rng, HOBBIES)
	return person


## Где работает: одно из зданий с работой у последней клетки пути (чаще — где мест больше).
static func _work_of(grid: CityGrid, job_sites: Dictionary[int, PackedInt32Array], path: PackedInt32Array,
		rng: RandomNumberGenerator) -> int:
	if path.is_empty() or not job_sites.has(path[path.size() - 1]):
		return -1
	var ids: PackedInt32Array = job_sites[path[path.size() - 1]]
	var weights := PackedFloat32Array()
	for id: int in ids:
		var building: BuildingInstance = grid.buildings.get(id)
		var data: BuildingData = BuildingCatalog.get_type(building.type_id) if building != null else null
		weights.append(float(data.jobs) if data != null else 0.0)
	var index: int = rng.rand_weighted(weights)
	return ids[index] if index >= 0 and grid.buildings.has(ids[index]) else -1


static func _job_of(grid: CityGrid, work_id: int, male: bool, rng: RandomNumberGenerator) -> String:
	var building: BuildingInstance = grid.buildings.get(work_id)
	var data: BuildingData = BuildingCatalog.get_type(building.type_id) if building != null else null
	if data == null or not JOBS.has(data.zone):
		return "работает в городе"
	var options: Array = JOBS[data.zone]
	var pair: Array = options[rng.randi_range(0, options.size() - 1)]
	return pair[0] if male else pair[1]


## Семья по дому: сколько в среднем людей в семье этого дома (LevelStats.families) ± разброс.
static func _make_family(grid: CityGrid, person: Citizen, rng: RandomNumberGenerator) -> void:
	var average: float = LevelStats.FAMILY_SIZE
	var home: BuildingInstance = grid.buildings.get(person.home_id)
	var data: BuildingData = BuildingCatalog.get_type(home.type_id) if home != null else null
	if data != null and data.population > 0:
		average = float(data.population) / LevelStats.families(data.population)
	var size: int = clampi(roundi(average + rng.randf_range(-1.6, 1.6)), 1, 6)
	person.family_size = size
	if size == 1:
		person.family = "живёт один" if person.male else "живёт одна"
		return
	var parts: PackedStringArray = []
	var others: int = size - 1
	var max_child_age: int = mini(CHILD_MAX_AGE, person.age - PARENT_AGE)
	# Супруг — у взрослых, чаще всего; детей не бывает у совсем молодых.
	if person.age >= 21 and (rng.randf() < 0.78 or max_child_age < 0):
		var spouse: String = _pick(rng, FEMALE_NAMES if person.male else MALE_NAMES)
		parts.append(("жена " if person.male else "муж ") + spouse)
		others -= 1
	if others > 0 and max_child_age >= 0:
		var kids: PackedStringArray = []
		var used: PackedStringArray = []
		for i: int in others:
			var boy: bool = rng.randf() < 0.5
			var kid: String = _pick(rng, BOY_NAMES if boy else GIRL_NAMES)
			while used.has(kid):
				kid = _pick(rng, BOY_NAMES if boy else GIRL_NAMES)
			used.append(kid)
			kids.append("%s (%d)" % [kid, rng.randi_range(0, max_child_age)])
		parts.append(("ребёнок: " if kids.size() == 1 else "дети: ") + ", ".join(kids))
	elif others > 0:
		# Молодым без супруга и детей — родители или соседи.
		parts.append("с родителями" if rng.randf() < 0.5 else "с соседями (%d)" % others)
	# Фамилия у семьи общая — в карточке её не повторяем.
	person.family = ", ".join(parts)


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return list[rng.randi_range(0, list.size() - 1)]
