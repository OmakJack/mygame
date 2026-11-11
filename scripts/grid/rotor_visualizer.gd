class_name RotorVisualizer
extends Node3D
## Крутящиеся роторы ветряков (BuildingData.rotor): основание рисует BuildingVisualizer, ротор — здесь,
## один мультимеш на тип ротора (как краны в ConstructionVisualizer). Ротор стоит на своей оси
## (rotor_pivot) тем же трансформом, каким модель вписана в участок (BuildingMeshes.model_placement).
## Крутится, пока игра идёт; на стройке ротора нет, у ветряка без дороги (не даёт свет) ротор стоит.
## Ветряки-модули станции (StationModules) — так же: ось ротора на своей площадке участка.

## Мультимеш по id типа.
var _layers: Dictionary[StringName, MultiMeshInstance3D] = {}
## Ветряки по типу: [трансформ оси ротора в мире, начальный угол, крутится ли].
var _rotors: Dictionary[StringName, Array] = {}
## Время роторов: идёт только при идущей игре.
var _time: float = 0.0


func _ready() -> void:
	Events.cells_changed.connect(func(_cells: Array[Vector2i]) -> void: _sync())
	Events.grid_reset.connect(_sync)
	_sync()


## Сколько роторов нарисовано и сколько из них крутится (для проверок).
func counts() -> Vector2i:
	var result := Vector2i.ZERO
	for rotors: Array in _rotors.values():
		for rotor: Array in rotors:
			result.x += 1
			if rotor[2]:
				result.y += 1
	return result


func _process(delta: float) -> void:
	if _rotors.is_empty():
		return
	if SimClock.speed > 0:
		_time += delta
	_write()


## Ветряки — по готовым зданиям с ротором: новые появляются, снесённые уходят.
func _sync() -> void:
	var grid: CityGrid = GameState.grid
	_rotors.clear()
	for building: BuildingInstance in grid.buildings.values():
		var data: BuildingData = BuildingCatalog.get_type(building.type_id)
		if data == null or building.construction_ticks > 0:
			continue
		var place: Transform3D = grid.building_transform(building)
		var working: bool = grid.has_building_road_access(building)
		# Модули станции с ротором — на своих площадках.
		for item: Array in StationModules.placed(building):
			var visual: BuildingData = StationModules.visual_data(item[0])
			if visual == null or visual.rotor == null or visual.model == null:
				continue
			if not _rotors.has(visual.id):
				_rotors[visual.id] = []
			var seat: Transform3D = place * StationModules.pad_transform(item[1]) * BuildingMeshes.model_placement(visual) \
					* Transform3D(Basis.IDENTITY, visual.rotor_pivot)
			_rotors[visual.id].append([seat, fposmod((building.id * 7 + item[1]) * 2.399, TAU), working])
		if data.rotor == null or data.model == null:
			continue
		if not _rotors.has(data.id):
			_rotors[data.id] = []
		var pivot: Transform3D = place * BuildingMeshes.model_placement(data) * Transform3D(Basis.IDENTITY, data.rotor_pivot)
		# Начальный угол по id: соседние ветряки не крутятся в такт.
		var phase: float = fposmod(building.id * 2.399, TAU)
		_rotors[data.id].append([pivot, phase, working])
	for id: StringName in _rotors:
		if not _layers.has(id):
			_layers[id] = _make_layer(BuildingCatalog.get_type(id))
	_write()


func _make_layer(data: BuildingData) -> MultiMeshInstance3D:
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	layer.multimesh.mesh = ModelLoader.merge(data.rotor)
	add_child(layer)
	return layer


func _write() -> void:
	for id: StringName in _layers:
		var multimesh: MultiMesh = _layers[id].multimesh
		var rotors: Array = _rotors.get(id, [])
		# Число экземпляров — только если изменилось: присвоение заново выделяет буфер.
		if multimesh.instance_count != rotors.size():
			multimesh.instance_count = rotors.size()
		if rotors.is_empty():
			continue
		var data: BuildingData = BuildingCatalog.get_type(id)
		var axis: Vector3 = data.rotor_axis.normalized()
		var turn: float = _time * data.rotor_speed * TAU
		for i: int in rotors.size():
			var rotor: Array = rotors[i]
			var angle: float = rotor[1] + (turn if rotor[2] else 0.0)
			multimesh.set_instance_transform(i, rotor[0] * Transform3D(Basis(axis, angle), Vector3.ZERO))
