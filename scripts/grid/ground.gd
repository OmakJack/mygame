extends MeshInstance3D
## Земля под картой. Размер и положение берутся из GameState.grid,
## материал задаётся в сцене (у PlaneMesh).


func _ready() -> void:
	Events.grid_reset.connect(_resize)
	_resize()


func _resize() -> void:
	var size: float = GameState.grid.world_size()
	var plane := mesh as PlaneMesh
	plane.size = Vector2(size, size)
	position = Vector3(size * 0.5, 0.0, size * 0.5)
