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

## После тика в GameState обновлены население, рабочие места и спрос.
@warning_ignore("unused_signal")
signal stats_changed()
