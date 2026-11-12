extends Node
## Сохранения: файлы в save_dir, автосохранение, F5 / F9, новый город.
## Город ↔ словарь — CitySerializer; здесь только файлы и замена города.
## UI зовёт публичные методы напрямую (как SimClock.set_speed).

const EXTENSION: String = ".city.json"
const AUTOSAVE: String = "autosave"
const QUICKSAVE: String = "quicksave"
## Автосохранение каждые столько игровых дней.
## Автосохранение раз в 2 игровых часа (на ×1 — раз в 4 мин, на ×8 — в 30 с).
const AUTOSAVE_MINUTES: int = 2 * GameTime.MINUTES_PER_HOUR
const DEFAULT_CITY_NAME: String = "Новый город"
const MAX_FILE_NAME_LENGTH: int = 60
## Имена, которые Windows не даёт использовать для файлов.
const RESERVED_NAMES: Array[String] = [
	"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
]

## Папка сохранений. Переменная, чтобы тесты писали в свою.
var save_dir: String = "user://saves/"
## Река на новой карте. Переменная, чтобы тесты строили на ровной суше.
var with_river: bool = true
## Въезд трассы на новой карте (город растёт только связанный с ней). Тесты могут выключить.
var with_highway: bool = true
## Игровая минута последнего автосохранения (или загрузки / нового города).
var _last_autosave_minute: int = 0


func _ready() -> void:
	# Отсчёт — от текущего времени: город начинается в 07:00, а не в минуту 0 (иначе автосохранение
	# сработало бы на первом же тике, ещё до загрузки или нового города).
	_last_autosave_minute = GameState.minutes
	Events.sim_tick.connect(_on_sim_tick)
	Events.grid_reset.connect(func() -> void: _last_autosave_minute = GameState.minutes)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"save_quick"):
		_write(QUICKSAVE, "Быстрое сохранение")
	elif event.is_action_pressed(&"load_quick"):
		load_city(QUICKSAVE)


## Сохраняет город под именем city_name (оно же становится именем города).
func save_city(city_name: String) -> bool:
	GameState.city_name = city_name.strip_edges() if not city_name.strip_edges().is_empty() else DEFAULT_CITY_NAME
	return _write(file_id_for(GameState.city_name), GameState.city_name)


## Загружает сохранение. Битый файл не трогает текущий город. Возвращает true при успехе.
func load_city(file_id: String) -> bool:
	var path: String = _path(file_id)
	if not FileAccess.file_exists(path):
		Events.save_error.emit("Нет такого сохранения")
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: CitySerializer.LoadResult = CitySerializer.from_dict(data)
	if not result.ok:
		Events.save_error.emit("Не удалось загрузить: " + result.error)
		return false
	for warning: String in result.warnings:
		push_warning("Загрузка «%s»: %s" % [file_id, warning])
	_apply(result.grid, result.name, result.money, result.tax_rate, result.minutes, result.rank, result.budget_history)
	if result.rng_state.is_empty():
		GameState.rng.randomize()
	else:
		GameState.rng.seed = result.rng_state[0]
		GameState.rng.state = result.rng_state[1]
	Events.load_done.emit(result.name, result.warnings.size())
	return true


## Новый город: река и въезд трассы по случайному зерну; тесты выключают их через with_river / with_highway.
func new_city() -> void:
	var grid := CityGrid.new(CityGrid.GRID_SIZE)
	var map_seed: int = randi()
	if with_river:
		MapGenerator.add_river(grid, map_seed)
	if with_highway:
		MapGenerator.add_highway(grid, map_seed)
	_apply(grid, DEFAULT_CITY_NAME, Economy.START_MONEY, Economy.DEFAULT_TAX_RATE, GameTime.START_MINUTES, 0,
			Budget.History.new())
	GameState.rng.seed = map_seed


## Сохранения: file, name, day, population, money, saved_at, broken. Новые — первыми.
## У автосохранения и быстрого сохранения к имени города добавляется пометка.
func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return saves
	for file_name: String in dir.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var file_id: String = file_name.trim_suffix(EXTENSION)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_dir.path_join(file_name)))
		var root: Dictionary = data if data is Dictionary else {}
		var meta: Dictionary = root.get("meta", {}) if root.get("meta") is Dictionary else {}
		var city_name: String = str(meta.get("name", file_id))
		var display_name: String = city_name
		if file_id == AUTOSAVE:
			display_name = "Автосохранение: " + city_name
		elif file_id == QUICKSAVE:
			display_name = "Быстрое сохранение: " + city_name
		saves.append({
			"file": file_id,
			"name": display_name,
			"city_name": city_name,
			"broken": root.get("format") != CitySerializer.FORMAT,
			"day": _number(meta.get("day")),
			"population": _number(meta.get("population")),
			"money": _number(meta.get("money")),
			"saved_at": str(root.get("saved_at", "")),
		})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved_at > b.saved_at)
	return saves


func delete_save(file_id: String) -> bool:
	return DirAccess.remove_absolute(_path(file_id)) == OK


## Пустой город (нет дорог и зданий) не сохраняем автоматически,
## чтобы не затереть прошлое автосохранение.
func is_city_empty() -> bool:
	return GameState.grid.road_cells.is_empty() and GameState.grid.buildings.is_empty()


## Имя файла из имени города: буквы, цифры, пробел, _ и -; остальное — «_».
static func file_id_for(city_name: String) -> String:
	var id: String = ""
	for character: String in city_name.strip_edges():
		var is_letter: bool = character.to_upper() != character.to_lower()
		var is_digit: bool = character >= "0" and character <= "9"
		id += character if is_letter or is_digit or character in [" ", "_", "-"] else "_"
	# Ещё раз strip_edges после обрезки: Windows отбрасывает пробел в конце имени файла.
	id = id.strip_edges().left(MAX_FILE_NAME_LENGTH).strip_edges()
	if id.is_empty():
		id = "city"
	# Служебные и зарезервированные имена Windows — с «_» спереди. Без учёта регистра:
	# в Windows «Autosave» и «autosave» — один и тот же файл.
	var lower: String = id.to_lower()
	if id.to_upper() in RESERVED_NAMES or lower == AUTOSAVE or lower == QUICKSAVE:
		id = "_" + id
	return id


func _write(file_id: String, label: String) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var data: Dictionary = CitySerializer.to_dict(GameState.grid, GameState.city_name, GameState.money,
			GameState.tax_rate, GameState.minutes, GameState.population, GameState.rank, GameState.rng,
			GameState.budget_history)
	var path: String = _path(file_id)
	var temp_path: String = path + ".tmp"
	# Сначала во временный файл, потом поверх старого: при сбое старое сохранение цело.
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		Events.save_error.emit("Не удалось сохранить: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	var error: Error = DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		DirAccess.remove_absolute(temp_path)
		Events.save_error.emit("Не удалось сохранить: %s" % error_string(error))
		return false
	Events.save_done.emit(label)
	return true


func _apply(grid: CityGrid, city_name: String, money: int, tax_rate: int, minutes: int, rank: int,
		budget_history: Budget.History) -> void:
	GameState.grid = grid
	GameState.budget_history = budget_history
	GameState.rank = rank
	GameState.city_name = city_name
	GameState.money = money
	GameState.tax_rate = tax_rate
	GameState.minutes = minutes
	# Сеть сверяется со ссылкой на сетку сама; свет, вода и службы пересчитает Simulation.
	GameState.utilities = Utilities.new()
	GameState.service_coverage = {}
	GameState.land = LandValue.new()
	GameState.happiness = Happiness.new()
	Events.grid_reset.emit()


## Раз в AUTOSAVE_MINUTES игровых минут от последнего автосохранения (а не «в полночь»:
## иначе после загрузки сохранения, сделанного в 23:50, автосохранение сработало бы сразу).
func _on_sim_tick() -> void:
	if GameState.minutes - _last_autosave_minute >= AUTOSAVE_MINUTES:
		_autosave()


func _autosave() -> void:
	if not is_city_empty() and _write(AUTOSAVE, "Автосохранение"):
		_last_autosave_minute = GameState.minutes


## Только имя файла (get_file): даже «../что-то» не выйдет за папку сохранений.
func _path(file_id: String) -> String:
	return save_dir.path_join(file_id.get_file() + EXTENSION)


static func _number(value: Variant) -> int:
	return int(value) if (value is int or value is float) else 0
