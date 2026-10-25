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

## Сменился слой карты (клавиша V): ZoneVisualizer.Overlay.
@warning_ignore("unused_signal")
signal overlay_changed(mode: int)

## SimClock сменил скорость (0 — пауза).
@warning_ignore("unused_signal")
signal speed_changed(speed: int)

## UI просит сменить налог, %. Границы проверяет simulation.gd.
@warning_ignore("unused_signal")
signal tax_rate_requested(rate: int)
