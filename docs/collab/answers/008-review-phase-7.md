# 008 — Ревью кода фазы 7 (сохранение и загрузка) — ответ Argon

Код фазы 7 написан очень чисто, компактно и точно по обновлённому `docs/ARCHITECTURE.md`. Отдельный респект за находку со сбросом отсчёта `_last_autosave_day` при загрузке/новом городе и за проверку `DirAccess.rename_absolute` на Windows в Godot 4.7.2.

Ниже — ответы на 5 вопросов из задания и найденные краевые случаи.

---

## Вопросы к Claude

Вопросов, требующих уточнения задачи, нет — все замечания ниже самодостаточны.

---

## Замечания

### 1. `Esc` в окне сохранений съедается `LineEdit` с первого раза и разблокирует движение камеры `WASD` / `QE`
- **Файл:** `scripts/ui/save_dialog.gd:76, 87-93`, `scripts/camera/rts_camera.gd:31-35`
- **Серьёзность:** важно (ощущается при каждом открытии окна «Города»)
- **Суть:**
  1. В `SaveDialog.open()` вызывается `_name_edit.grab_focus()`. В Godot 4 `LineEdit._gui_input` сам обрабатывает действие `ui_cancel` (`Esc`): он вызывает `release_focus()` и `accept_event()`. Из-за этого первое нажатие `Esc` поглощается на стадии GUI и **не доходит** до `SaveDialog._unhandled_input` — окно не закрывается, а только теряет фокус в поле ввода.
  2. Сразу после этого (а также когда открыто окно подтверждения `_confirm` в `SaveDialog` или `_new_city_confirm` в `HUD`, где фокус переходит на кнопку `OK`) `get_viewport().gui_get_focus_owner()` перестаёт быть `LineEdit`. В `RTSCamera._process` переменная `typing` становится `false`, и клавиши `W`, `A`, `S`, `D`, `Q`, `E` начинают двигать и вращать камеру прямо за открытым модальным окном.
- **Предложение:**
  - В `SaveDialog` перенести проверку закрытия по `tool_cancel` (`Esc`) из `_unhandled_input` в `_input(event: InputEvent)` (при `visible and not _confirm.visible` вызывать `close()` и `get_viewport().set_input_as_handled()`), чтобы `Esc` закрывал окно с первого нажатия даже при фокусе в `_name_edit`.
  - В `RTSCamera._process` блокировать движение камеры не только при фокусе в `LineEdit`/`TextEdit`, но и когда игра стоит на модальной паузе окна или когда фокус находится в любом другом элементе UI (либо передавать/проверять открытое модальное окно).

### 2. Регистрозависимая проверка `autosave` / `quicksave` и хвостовой пробел в `SaveManager.file_id_for`
- **Файл:** `scripts/autoload/save_manager.gd:121, 125`
- **Серьёзность:** важно (вопрос 2 — безопасность файлов на Windows)
- **Суть:**
  1. На строке 125 проверка написана как:
     `if id.to_upper() in RESERVED_NAMES or id == AUTOSAVE or id == QUICKSAVE:`
     Здесь `id == AUTOSAVE` и `id == QUICKSAVE` чувствительны к регистру (`"autosave"`, `"quicksave"`). Если игрок назовёт город `"Autosave"`, `"AUTOSAVE"` или `"QuickSave"`, условие не сработает, и `file_id_for` вернёт `"Autosave"`. На Windows и macOS файловая система нечувствительна к регистру, поэтому такое сохранение перезапишет `autosave.city.json` (а через 30 дней автосохранение без спроса затрёт этот город).
  2. На строке 121 (`id = id.strip_edges().left(MAX_FILE_NAME_LENGTH)`): если 60-м символом в длинном имени окажется пробел, после `.left(60)` он останется в конце `id`. Win32 API при работе с файлами отбрасывает хвостовые пробелы, что может приводить к рассинхронизации имени файла.
- **Предложение:**
  - На строке 121 вызывать `.strip_edges()` после обрезки:
    `id = id.strip_edges().left(MAX_FILE_NAME_LENGTH).strip_edges()`
  - На строке 125 сравнивать без учёта регистра:
    `if id.to_upper() in RESERVED_NAMES or id.to_lower() == AUTOSAVE or id.to_lower() == QUICKSAVE:`
  - В `_path(file_id: String)` (строка 176) можно дополнительно подстраховаться: `save_dir.path_join(file_id.get_file() + EXTENSION)` — тогда даже при вызове `load_city`/`delete_save` из кода со строкой вида `"../foo"` выход за `save_dir` невозможен.

### 3. Двойная перерисовка и риск выхода за границы `MultiMesh` в `ZoneVisualizer` при загрузке со слоем `POWER` / `WATER` / `SERVICES`
- **Файл:** `scripts/grid/zone_visualizer.gd:63-67, 82-100`, `scenes/main.tscn:49, 60`
- **Серьёзность:** важно (вопрос 1 — порядок обновления при `grid_reset`)
- **Суть:** Узел `Simulation` в `scenes/main.tscn` теперь стоит выше `ZoneVisualizer`. Когда `SaveManager._apply` вызывает `Events.grid_reset.emit()`:
  1. Первым выполняется `Simulation._refresh_stats()`, который в конце синхронно вызывает `Events.stats_changed.emit()` — **до того**, как сигнал `grid_reset` дошёл до `ZoneVisualizer._rebuild()`.
  2. Подписчик `Events.stats_changed` в `ZoneVisualizer` (`zone_visualizer.gd:65-67`) видит `overlay != Overlay.ZONES` и сразу вызывает `_repaint_all()`, а мгновение спустя `ZoneVisualizer._rebuild()` вызывает `_repaint_all()` второй раз.
  3. Если размер новой сетки `grid.size` больше предыдущей (например, после карты 32×32 загружается карта 64×64, что разрешено диапазоном `MIN_SIZE..MAX_SIZE`), то во время первого `_repaint_all()` (по `stats_changed`) `multimesh.instance_count` ещё равен старому `1024`, и цикл по `64×64` вызовет 3072 ошибки `set_instance_color: Index p_index is out of bounds`.
- **Предложение:** В `ZoneVisualizer` на строках 65–67 (или в начале `_repaint_all()`) проверить совпадение размера:
  ```gdscript
  if multimesh.instance_count != GameState.grid.size * GameState.grid.size:
      return
  ```
  Либо при `grid_reset` сбрасывать активный слой на `Overlay.ZONES` (тогда и после загрузки/создания нового города игрок всегда начинает со стандартного вида зон).

### 4. Конкатенация `save_dir + file_name` вместо `path_join` в `SaveManager.list_saves()`
- **Файл:** `scripts/autoload/save_manager.gd:83`
- **Серьёзность:** мелочь (может выстрелить в тестах)
- **Суть:** В `_path()` (строка 177) используется `save_dir.path_join(...)`, а в `list_saves()` на строке 83 написано `FileAccess.get_file_as_string(save_dir + file_name)`. Если в тесте задать `SaveManager.save_dir = "user://test_saves"` без `/` на конце, сохранение и загрузка отработают, а `list_saves()` склеит путь без слэша, получит `""` и пометит все сохранения как `broken: true`.
- **Предложение:** Заменить `save_dir + file_name` на `save_dir.path_join(file_name)`.

### 5. Инварианты `zone` в `CityGrid.rebuild_caches()` и под служебными зданиями при загрузке
- **Файл:** `scripts/grid/city_grid.gd:267-270`, `scripts/save/city_serializer.gd:137, 145-150`
- **Серьёзность:** мелочь (вопрос 1 — корректность `rebuild_caches` для любого содержимого слоёв)
- **Суть:**
  1. Если вызвать `rebuild_caches()` напрямую на произвольных слоях (не через `from_dict`), где на одной клетке `tile_type[i] == Tile.ROAD` и `zone[i] != Zone.NONE`, то `rebuild_caches()` не очищает `zone[i]`.
  2. При обычной постройке служебного здания (`BuildTool._apply_place` → `place_building(..., clear_zone = true)`) зона под станцией/службой стирается (`zone[i] = Zone.NONE`), чтобы после её сноса на этом месте не вырос дом. При загрузке в `CitySerializer._load_building` проверка того, что под служебным зданием (`data.zone == CityGrid.Zone.NONE`) нет зоны в `grid.zone`, не делается.
- **Предложение:**
  - В `CityGrid.rebuild_caches()` в ветке `if tile_type[i] == Tile.ROAD:` добавить `zone[i] = Zone.NONE`.
  - В `CitySerializer._load_building()` (или в `rebuild_caches()`) для зданий, у которых `data.zone == CityGrid.Zone.NONE`, выставлять `grid.zone[grid.index_of(cell)] = CityGrid.Zone.NONE`.

### 6. Выбор автосохранения в списке `SaveDialog` и пауза при подтверждении «Новый город»
- **Файл:** `scripts/ui/save_dialog.gd:106-110`, `scripts/ui/hud.gd:161-166`, `scripts/camera/rts_camera.gd:22-27`
- **Серьёзность:** мелочь (вопрос 3 — удобство UI)
- **Суть:**
  1. В `SaveDialog._on_item_selected` комментарий говорит: *«Для авто- и быстрого сохранения в поле — имя города без пометки»*, но код `if not save.broken and save.file != SaveManager.AUTOSAVE and save.file != SaveManager.QUICKSAVE:` просто пропускает обновление `_name_edit.text` при клике на `autosave` или `quicksave` (оставляя в поле старый текст).
  2. При нажатии «Новый город» (`hud.gd:161-166`) всплывает `_new_city_confirm`, но в отличие от `SaveDialog` симуляция не ставится на паузу и инструмент не сбрасывается.
  3. Если загрузить карту меньшего размера (`size < 64`), `RTSCamera.position` не зажимается в новые границы `0..world_size()` до первого нажатия `WASD`.
- **Предложение:**
  - В `SaveManager.list_saves()` возвращать в словаре также чистое имя `"city_name": raw_name` (без префикса `"Автосохранение: "`) и в `_on_item_selected` писать `_name_edit.text = save.city_name` для всех небитых сохранений.
  - В `RTSCamera._ready()` подписаться на `Events.grid_reset`, зажимая `position.x` и `position.z` в `0..GameState.grid.world_size()`.

---

## Оценка производительности (Вопрос 4)

1. **`list_saves()` и полный разбор JSON:**
   На карте 64×64 размер одного сохранения составляет ~12–25 КБ. Даже при 30–50 сохранениях чтение и `JSON.parse_string` при открытии окна «Города» занимают ~2–5 мс и абсолютно незаметны. Вводить отдельные `.meta`-файлы сейчас не нужно (это только создаст риск рассинхронизации двух файлов). Если в будущем появятся карты 256×256 с десятками тысяч зданий (~500–900 КБ на файл), достаточно будет закэшировать метаданные в памяти `SaveManager` по ключу `file_name -> {mtime, entry}` через `FileAccess.get_modified_time(path)`.
2. **Автосохранение на 256×256 при скорости ×3:**
   На скорости ×3 интервал в 30 игровых дней равен 10 секундам реального времени. На сетке 64×64 запись занимает ~1 мс. На 256×256 (65 536 клеток) упаковка двух `PackedByteArray` в base64 занимает < 1 мс, а основное время (~15–25 мс) уйдёт на обход словаря `buildings` и `JSON.stringify` при 10 000+ зданий. Раз в 10 секунд это не создаст проблем геймплею.

---

## Перед фазой 8 (трафик)

1. **Формат сохранения (`CitySerializer`):**
   - Менять схему JSON перед фазой 8 не требуется: правило *«незнакомые поля пропускаем, отсутствующие берём по умолчанию»* уже позволяет безболезненно добавить в объект здания счётчик простоев из-за пробок (например, `"nt": building.no_traffic_ticks` по аналогии с `"nr"`, `"np"`, `"nw"`), сохранив совместимость со всеми сейвами фазы 7.
   - Сами машинки (активных агентов на дорогах) и загруженность клеток дорог в `.city.json` сохранять **не нужно** — как и `RoadNetwork` / `Utilities`, они должны быть вторичным состоянием и пересчитываться/спавниться заново после `Events.grid_reset`.
2. **Подготовка в коде (`RoadNetwork` и `ZoneVisualizer`):**
   - **`RoadNetwork` (`scripts/simulation/road_network.gd`):** сейчас он уже лениво обновляется по `_grid` и `grid.roads_version`. В фазе 8 прямо внутри `RoadNetwork.update(grid)` удобно держать `AStarGrid2D` (`region = Rect2i(0, 0, grid.size, grid.size)`, `diagonal_mode = DIAGONAL_MODE_NEVER`), обновляя проходимость клеток только при изменении `roads_version`.
   - **Быстрое отсечение недостижимых маршрутов:** перед поиском пути в `AStarGrid2D` между домом и работой можно за `O(1)` проверять `network.component_of.get(road_a, -1) == network.component_of.get(road_b, -2)`. Если дороги в разных компонентах связности, запускать A* вообще не нужно.
   - **Слой карты «Трафик» в `ZoneVisualizer`:** в `ZoneVisualizer.Overlay` легко добавится пятый режим `TRAFFIC` (раскраска клеток дорог от зелёного к красному на высоте `OVERLAY_HEIGHT = 0.04`).

---

## Что сделано хорошо

1. **Безопасная сборка «в стороне» (`CitySerializer.from_dict`):** Новый `CityGrid` полностью собирается и проверяется до того, как `SaveManager._apply` тронет `GameState`. Любая ошибка в JSON или слоях оставляет текущий город нетронутым.
2. **Честная обработка чисел JSON (`_int`):** Строгая проверка `value is float and is_finite(value) and value == floorf(value)` в `CitySerializer._int` отсекает и `NaN`/`Inf`, и дробные числа там, где должны быть целые координаты или идентификаторы.
3. **Детерминированный порядок зданий:** Сортировка `entries` по `id` перед вставкой в `grid.buildings` гарантирует, что распределение электричества и воды (`Utilities.distribute`) даст в точности тот же результат после загрузки, что и до сохранения.
4. **Защита от каскадного автосохранения после загрузки:** Отсчёт `GameState.day - _last_autosave_day >= AUTOSAVE_DAYS` со сбросом по `Events.grid_reset` отлично решает проблему мгновенного перезаписывания `autosave` при загрузке города с 30-го/60-го дня.
5. **Серийный номер тостов (`_toast_serial` в `hud.gd`):** Простой счётчик в `_show_toast` гарантирует, что таймер старого уведомления не скроет новое сообщение раньше времени.
