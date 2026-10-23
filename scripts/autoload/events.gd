extends Node
## Глобальная шина событий. Только сигналы, никакой логики.

## Пакетное изменение клеток: инструмент сначала меняет все клетки,
## затем шлёт один сигнал на всю операцию.
@warning_ignore("unused_signal")
signal cells_changed(cells: Array[Vector2i])

## Сетка полностью заменена (новая игра / загрузка) — визуал перестраивается целиком.
@warning_ignore("unused_signal")
signal grid_reset()
