# ARCHITECTURE — CityBuilder

## Главные принципы
1. **Данные отдельно от визуала.** Состояние города хранится в массивах данных (`CityGrid`). 3D-объекты только отображают эти данные и никогда не являются «источником правды».
2. **Симуляция отдельно от рендера.** Логика города считается по тикам (`SimClock`), а не в каждом кадре `_process`.
3. **Связь через сигналы.** Системы не вызывают друг друга напрямую, где можно — общаются через глобальную шину `Events`.
4. **Типы зданий — данные, а не код.** Каждый тип здания описан в `.tres`-ресурсе (`BuildingData`).
5. **Типизированный GDScript.** Везде указываем типы: `var money: int = 0`, `func get_cell(pos: Vector2i) -> int:`.

## Структура папок
```
res://
├── docs/            GDD.md, ARCHITECTURE.md, TASKS.md, CHANGELOG.md
├── scenes/
│   ├── main.tscn    главная сцена
│   ├── camera/
│   ├── ui/
│   └── world/
├── scripts/
│   ├── autoload/    events.gd, game_state.gd, sim_clock.gd
│   ├── grid/        city_grid.gd, grid_visualizer.gd
│   ├── camera/      rts_camera.gd
│   ├── tools/       build_tool.gd (режимы: дорога, зона, снос)
│   └── simulation/  demand.gd, growth.gd, economy.gd
├── data/
│   └── buildings/   *.tres (BuildingData)
└── assets/
    ├── models/
    └── textures/
```

## Автозагрузки (Autoload, глобальные синглтоны)
| Имя | Файл | Назначение |
|---|---|---|
| `Events` | scripts/autoload/events.gd | Только сигналы (шина событий) |
| `GameState` | scripts/autoload/game_state.gd | Деньги, население, дата |
| `SimClock` | scripts/autoload/sim_clock.gd | Тики симуляции, скорость (0/1/3) |

## Модель данных сетки (CityGrid)
- Размер: `GRID_SIZE = 64`, размер клетки в мире: `CELL_SIZE = 2.0` метра.
- Координаты клетки: `Vector2i(x, y)`. В мире: X → ось X, Y → ось Z, высота = 0.
- Слои данных (по одному значению на клетку):
  - `tile_type`: EMPTY, ROAD, BUILDING
  - `zone`: NONE, RESIDENTIAL, COMMERCIAL, INDUSTRIAL
  - `building_id`: id здания или -1
- Обязательные функции:
  - `grid_to_world(cell: Vector2i) -> Vector3`
  - `world_to_grid(pos: Vector3) -> Vector2i`
  - `is_in_bounds(cell: Vector2i) -> bool`
- При изменении клетки шлётся сигнал `Events.cell_changed(cell)`, визуал обновляется по нему.

## Отображение
- Дороги и здания: `GridMap` + `MeshLibrary` (в 4.7 есть встроенный редактор MeshLibrary).
- Если зданий станет очень много — переход на `MultiMeshInstance3D`.
- Зоны: полупрозрачная раскраска клеток.

## Соглашения
- Файлы и переменные: `snake_case`. Классы: `PascalCase` (`class_name CityGrid`).
- Один скрипт = одна ответственность.
- Комментарии на русском, имена в коде на английском.
- Любое изменение архитектуры сначала вносится в этот файл.
