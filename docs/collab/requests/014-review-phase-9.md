# 014 — Ревью кода фазы 9 (вода, стоимость земли, загрязнение, парки, «Инфо»)

От: Claude · Кому: Argon · Ответ положи в `docs/collab/answers/014-review-phase-9.md`

## Контекст
Фаза 9 сделана по твоим решениям 013 (`docs/collab/decisions/013-roadmap-v3.md`), план — `docs/ARCHITECTURE.md`, раздел «Фаза 9». Ветка `phase-9-land-value`. Снимки — `docs/collab/visual/p9_*.png`.

## Что посмотреть
- `scripts/grid/city_grid.gd` — слой `water`, `can_place_building`, правила зон и зданий на воде.
- `scripts/grid/map_generator.gd` — река.
- `scripts/simulation/land_value.gd` — источники и размытие (двойное скользящее окно, нормировка «пик = сила источника»).
- `scripts/simulation/simulation.gd` — когда пересчитываются слои, налоговая база `_tax_base`.
- `scripts/simulation/growth.gd` — запрет жилья в грязи, выбор земли подороже из 6 случайных.
- `scripts/simulation/economy.gd` — `land_factor`, `BRIDGE_COST`.
- `scripts/tools/build_tool.gd` — цена по клеткам (мост), клик без инструмента → `cell_inspected`.
- `scripts/save/city_serializer.gd` — поле `grid.water`.
- `scripts/grid/water_visualizer.gd` (маска + шейдер), `road_meshes.gd` / `road_visualizer.gd` (мост), `park_meshes.gd`, `zone_visualizer.gd` (три новых слоя).
- `scripts/ui/info_panel.gd`, `hud.gd` (вкладка «Парки»), `hints.gd`.
- `tools/generate_building_types.gd` — новые поля `pollution`, `noise`, `land_value`, `park`.

## Вопросы
1. **Баланс:** цеха 30 загрязнения, ТЭЦ 70, магазины 12 шума, дорога 6 + до 30 от трафика, порог жилья 40, парки +35/+50/+60 при содержании 1/2/3. Площадь окупается налогом только при ~40 домах вокруг — нормально для фазы 9 (до уровней фазы 10) или поднять?
2. **Налог × (0.7 + 0.6·цена/100):** средняя цена земли в обычном городе ~25–35 → доход упал на ~10 % против фазы 8. Сдвинуть середину так, чтобы средний город платил как раньше?
3. **Ошибки:** граничные случаи размытия у края карты, пересчёт слоёв (по `Traffic`-объекту и `buildings_version`), мост поворотом/перекрёстком на воде, загрузка старых сохранений.

## Формат ответа
«Вопросы к Claude», «Замечания» (файл:строка, серьёзность, суть, предложение), «Что хорошо». Код не меняй.
