extends Node
## Глобальная шина событий. Только сигналы, никакой логики.

## Пакетное изменение клеток: инструмент или симуляция сначала меняет все клетки,
## затем шлёт один сигнал на всю операцию (тик).
@warning_ignore("unused_signal")
signal cells_changed(cells: Array[Vector2i])

## Сетка полностью заменена (новая игра / загрузка) — визуал перестраивается целиком.
@warning_ignore("unused_signal")
signal grid_reset()

## Тик симуляции (шлёт SimClock).
@warning_ignore("unused_signal")
signal sim_tick()

## В GameState обновлены деньги, население, рабочие места и спрос (после тика или изменений вне тика).
@warning_ignore("unused_signal")
signal stats_changed()

## UI просит сменить инструмент (BuildTool.Mode).
@warning_ignore("unused_signal")
signal tool_requested(mode: int)

## Инструмент сменил режим (от кнопки или клавиши). type_id — здание для режима PLACE.
@warning_ignore("unused_signal")
signal tool_mode_changed(mode: int, type_id: StringName)

## UI просит режим постановки служебного здания.
@warning_ignore("unused_signal")
signal building_place_requested(type_id: StringName)

## UI просит поставить модуль станции (карточка станции): режим BuildTool.Mode.MODULE.
@warning_ignore("unused_signal")
signal module_place_requested(station_id: int, module_id: StringName)

## Сохранения (для сообщений в HUD).
@warning_ignore("unused_signal")
signal save_done(name: String)
@warning_ignore("unused_signal")
signal load_done(name: String, warnings: int)
@warning_ignore("unused_signal")
signal save_error(message: String)

## Открылось или закрылось окно поверх игры (сохранения, подтверждение) — камера стоит.
@warning_ignore("unused_signal")
signal modal_changed(open: bool)

## Клик по клетке без инструмента в руке — HUD показывает карточку «Инфо» (фаза 9).
@warning_ignore("unused_signal")
signal cell_inspected(cell: Vector2i)

## Город получил новое звание (Ranks, фаза 10) — HUD показывает сообщение.
@warning_ignore("unused_signal")
signal rank_changed(rank: int)

## Советник просит показать место на карте: камера плавно летит к клетке (RTSCamera).
@warning_ignore("unused_signal")
signal camera_focus_requested(cell: Vector2i)

## Кнопка «Меню» в HUD просит открыть главное меню (как Esc).
@warning_ignore("unused_signal")
signal menu_requested

## Сменился слой карты (клавиша V): ZoneVisualizer.Overlay.
@warning_ignore("unused_signal")
signal overlay_changed(mode: int)
## Просьба показать слой карты (панель «Фильтры», инструмент): ZoneVisualizer.Overlay.
signal overlay_requested(mode: int)

## SimClock сменил скорость (0 — пауза).
@warning_ignore("unused_signal")
signal speed_changed(speed: int)

## UI просит сменить налог, %. Границы проверяет simulation.gd.
@warning_ignore("unused_signal")
signal tax_rate_requested(rate: int)

## Инструмент дорог (RoadTool): форма (RoadTool.Shape) и привязка к сетке. Просит HUD, сообщает RoadTool.
@warning_ignore("unused_signal")
signal road_shape_requested(shape: int)
@warning_ignore("unused_signal")
signal road_grid_snap_requested(enabled: bool)
@warning_ignore("unused_signal")
signal road_tool_changed(shape: int, grid_snap: bool)
