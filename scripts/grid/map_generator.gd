class_name MapGenerator
extends RefCounted
## Природа новой карты (фаза 9): пока — одна извилистая река поперёк карты.

## Ширина реки, клетки (местами на клетку шире).
const RIVER_WIDTH: int = 2
## Насколько далеко река гуляет от прямой — доля стороны карты.
const RIVER_SWING: float = 0.18
## Частота изгибов реки.
const RIVER_FREQUENCY: float = 0.035


## Длина трассы внутри карты от въезда, клетки.
const HIGHWAY_LENGTH: int = 5


## Въезд трассы на случайном крае, ближе к середине края, там, где на всём отрезке трассы суша.
## Ставится после реки. Если такого места нет — без въезда (рост без условия).
static func add_highway(grid: CityGrid, map_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 17
	var first_dir: int = rng.randi_range(0, 3)
	for attempt: int in 40:
		var dir: int = (first_dir + attempt) % 4
		var along: int = roundi(grid.size * rng.randf_range(0.3, 0.7))
		var edge: Vector2i
		match dir:
			0: edge = Vector2i(along, 0)
			1: edge = Vector2i(grid.size - 1, along)
			2: edge = Vector2i(along, grid.size - 1)
			_: edge = Vector2i(0, along)
		var inward: Vector2i = -CityGrid.NEIGHBORS[dir]
		var dry: bool = true
		for k: int in HIGHWAY_LENGTH + 3:
			if grid.is_water(edge + inward * k):
				dry = false
		if dry:
			grid.set_entry(edge, dir, HIGHWAY_LENGTH)
			return


## Река поперёк карты по зерну map_seed: вдоль X или вдоль Z, ближе к краю, чем к центру,
## чтобы с одного берега оставалось много места под город.
static func add_river(grid: CityGrid, map_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var bend := FastNoiseLite.new()
	bend.seed = map_seed
	bend.frequency = RIVER_FREQUENCY
	var widen := FastNoiseLite.new()
	widen.seed = map_seed + 1
	widen.frequency = RIVER_FREQUENCY * 2.0
	var along_x: bool = rng.randf() < 0.5
	var side: float = 0.25 if rng.randf() < 0.5 else 0.75
	var base: float = grid.size * (side + rng.randf_range(-0.05, 0.05))
	for t: int in grid.size:
		var center: float = base + bend.get_noise_1d(t) * grid.size * RIVER_SWING
		var width: int = RIVER_WIDTH + (1 if widen.get_noise_1d(t) > 0.2 else 0)
		var from: int = roundi(center - width * 0.5)
		for k: int in width:
			var cell := Vector2i(t, from + k) if along_x else Vector2i(from + k, t)
			if grid.is_in_bounds(cell):
				grid.water[grid.index_of(cell)] = 1
