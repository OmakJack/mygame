# ARCHITECTURE — CityBuilder

Версия 2 (после ревью Gemini, 2026-10-23)

## Главные принципы
1. **Данные отдельно от визуала.** Состояние города хранится в `CityGrid` (доступ: `GameState.grid`). 3D-объекты только отображают эти данные и никогда не являются «источником правды».
2. **Симуляция отдельно от рендера.** Логика города считается по тикам (`SimClock`), а не в каждом кадре `_process`.
3. **Связь через сигналы.** Системы общаются через глобальную шину `Events`. Системы симуляции никогда не ищут узлы сцены через `get_node()`.
4. **Типы зданий — данные, а не код.** Каждый тип здания описан в `.tres`-ресурсе (`BuildingData`) со строковым `id`.
5. **Типизированный GDScript.** Везде указываем типы: `var money: int = 0`, `func get_cell(pos: Vector2i) -> int:`.
6. **Не строим заранее.** Системы из поздних фаз не добавляем, пока до них не дошли. Но оставляем для них одну точку входа.

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
│   ├── grid/        city_grid.gd, building_instance.gd, grid_visualizer.gd
│   ├── data/        building_data.gd
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
| `GameState` | scripts/autoload/game_state.gd | Деньги, население, дата, **`grid: CityGrid`** |
| `SimClock` | scripts/autoload/sim_clock.gd | Тики симуляции, скорость (0/1/3) |

`GameState` создаёт сетку при старте: `grid = CityGrid.new(GRID_SIZE)`.

## Модель данных

### CityGrid (`class_name CityGrid extends RefCounted`)
- Размер: `GRID_SIZE = 64`, размер клетки в мире: `CELL_SIZE = 2.0` метра.
- Координаты клетки: `Vector2i(x, y)`. В мире: X → ось X, Y → ось Z, высота = 0.
- Слои (по одному значению на клетку, индекс = `y * GRID_SIZE + x`):
  - `tile_type: PackedByteArray` — EMPTY, ROAD, BUILDING
  - `zone: PackedByteArray` — NONE, RESIDENTIAL, COMMERCIAL, INDUSTRIAL
  - `building_at: PackedInt32Array` — номер экземпляра здания на клетке или -1
- Кэши (чтобы не сканировать всю карту):
  - `buildings: Dictionary[int, BuildingInstance]` — все построенные здания
  - `road_cells: Dictionary[Vector2i, bool]` — все клетки с дорогой
  - `next_building_id: int` — счётчик номеров экземпляров
- Обязательные функции:
  - `grid_to_world(cell: Vector2i) -> Vector3`
  - `world_to_grid(pos: Vector3) -> Vector2i`
  - `is_in_bounds(cell: Vector2i) -> bool`
  - `set_road(cell)` / `remove_road(cell)` — **единственное** место изменения дорог (в фазе 6 сюда добавится поиск пути)
  - `place_building(type_id, cell, orientation) -> int` / `remove_building(instance_id)`

### BuildingInstance (`class_name BuildingInstance extends RefCounted`)
Один построенный дом.
- `id: int` — уникальный номер экземпляра
- `type_id: StringName` — тип, например `&"res_small_01"` (ссылка на BuildingData.id)
- `cell: Vector2i` — клетка-основание
- `orientation: int` — 0/1/2/3 = 0°/90°/180°/270°, здание смотрит на дорогу

### BuildingData (`class_name BuildingData extends Resource`)
Описание типа здания (файл `.tres`).
- `id: StringName` — уникальный строковый id. **Никогда не меняется после создания** (на нём держатся сохранения).
- `zone`, `population`, `jobs`, `cost`, `upkeep`, ссылка на меш
- Размер: в MVP всегда 1×1.

### Дороги
Форма (прямая/угол/T/крест) и поворот дороги **не хранятся** — они вычисляются по соседним дорожным клеткам. При загрузке сохранения пересчитываются.

## Сигналы (Events)
- `cells_changed(cells: Array[Vector2i])` — пакетный. Инструмент сначала меняет все клетки, затем шлёт **один** сигнал на всю операцию.
- `grid_reset()` — сетка полностью заменена (загрузка/новая игра), визуал перестраивается целиком.
- Остальные сигналы добавляются сюда по мере появления.

## Отображение
- Дороги и здания: `GridMap` + `MeshLibrary` (в 4.7 есть встроенный редактор MeshLibrary).
- Если зданий станет очень много — переход на `MultiMeshInstance3D`.
- Зоны: полупрозрачная раскраска клеток.

## Отложенные решения
- Поиск пути (фазы 6, 8): `AStarGrid2D` или обход в ширину по `road_cells` — добавляется в `set_road/remove_road`.
- Здания больше 1×1: экземпляр уже хранит основание, добавится поле размера.

## Соглашения
- Файлы и переменные: `snake_case`. Классы: `PascalCase` (`class_name CityGrid`).
- Один скрипт = одна ответственность.
- Комментарии на русском, имена в коде на английском.
- Любое изменение архитектуры сначала вносится в этот файл.
