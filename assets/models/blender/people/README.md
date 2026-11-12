# Набор горожан и велосипедистов (People & Cyclists Low-Poly Pack v1)

Набор из **12 лоу-поли 3D-моделей** для оживления тротуаров и дорог города (в духе *SimCity* / *Cities: Skylines*):
- **8 пешеходов (`walker`)** в позе ходьбы с характерными аксессуарами (рюкзаки, портфель, шоппинг-пакеты, стаканчик кофе навынос, багет из пекарни, дамская сумочка, походный ранец).
- **4 велосипедиста (`cyclist`)** на разных типах велосипедов (шоссейный, городской круизер с передней корзиной, велокурьер с термо-коробом доставки на багажнике, коммьютер с боковыми велосумками).

Регенерация из исходников (Blender 5.2 headless):
```powershell
& "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/make_people_and_commercial.py
```

Исходные генераторы:
- `tools/blender/pack_people.py`
- `tools/blender/make_people_and_commercial.py`
- Манифест: `assets/models/blender/people/manifest.json`
- Рендер-превью: `assets/models/blender/people/previews/people_and_cyclists.png`

---

## Конвенции Godot и совместимость с `PeopleVisualizer`

Все 12 моделей спроектированы специально под `scripts/grid/people_visualizer.gd`:
- **Текстура-палитра:** `res://assets/models/kenney/suburban/Textures/colormap.png` (`8×4` ячейки с вертикальным градиентом AO).
- **Ориентация:** В Blender персонажи и велосипеды смотрят вдоль **`-Y`**. При загрузке через `ModelLoader.fitted(load(path), PEOPLE_SCALE, CAR_MODEL_TURNS)` с `CAR_MODEL_TURNS = 2` в Godot модель поворачивается на `180°` и смотрит вдоль **`-Z`** (`Transform3D.looking_at(vel, Vector3.UP)` направляет `-Z` точно по вектору движения).
- **Масштаб:** В Blender рост пешеходов составляет `1.60–1.68 м` (у велосипедистов длина базы `1.70 м`, высота `1.72–1.79 м`). При штатном `PEOPLE_SCALE = 0.22` из `PeopleVisualizer` их высота в мире игры составляет **`~0.35–0.39 м`** (как в существующем тесте `tests/18_pedestrians.gd`, который проверяет `y in 0.15..0.60`).
- **Перекраска одежды и рам через `INSTANCE_CUSTOM`:**
  `PeopleVisualizer` записывает `Color(_rng.randf(), _rng.randf_range(0.45, 1.0), 0.0, 1.0)` в `multimesh.set_instance_custom_data(...)` и прогоняет меш через `BuildingPalette.convert(...)`.
  В каждой модели **верхняя одежда / платья / худи / рамы велосипедов / термо-короб курьера** развёрнуты в перекрашиваемые ячейки палитры (`ROOF`, `ROOF_LITE`, `ROOF_WARM`, `ROOF_DEEP`, где `(row == 1 and col != 4 and col != 5) or (row == 3 and col == 1)`), а **кожа лица/рук (`TERRACOTTA`/`COPPER`), джинсы и костюмы (`GLASS_DARK`/`GLASS_LITE`), белые рубашки/тренчи/кроссовки (`WALL`/`CREAM`), сумки/волосы (`SANDSTONE`/`BRICK`) и серебристые обода колёс (`ALUM`)** остаются в своих фиксированных цветах. Благодаря этому каждый экземпляр `MultiMeshInstance3D` получает уникальный цвет одежды без перекрашивания лица или колёс!

---

## Состав набора (12 моделей)

### 1. Пешеходы (`walker`, 8 моделей)

| ID | Файл `.glb` | Описание | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|
| `citizen_casual_m` | `assets/models/blender/people/citizen_casual_m.glb` | Горожанин в расстёгнутой куртке поверх белой футболки, джинсах и кроссовках с рюкзаком (замена `person-a`) | `0.60 × 0.62 × 1.63` | 368 |
| `citizen_dress_f` | `assets/models/blender/people/citizen_dress_f.glb` | Горожанка в расклешённом летнем платье с поясом, длинными волосами и сумочкой через плечо (замена `person-b`) | `0.56 × 0.57 × 1.60` | 460 |
| `citizen_business_m` | `assets/models/blender/people/citizen_business_m.glb` | Офисный работник в тёмном деловом костюме, галстуке, очках и с кожаным портфелем в руке | `0.64 × 0.57 × 1.64` | 424 |
| `citizen_shopper_f` | `assets/models/blender/people/citizen_shopper_f.glb` | Покупательница в жакете, светлых брюках и шляпке-канотье с двумя цветными шоппинг-пакетами | `0.68 × 0.57 × 1.67` | 532 |
| `citizen_student_m` | `assets/models/blender/people/citizen_student_m.glb` | Студент в худи с капюшоном и карманом-кенгуру, кепке с козырьком, светлых джинсах и с рюкзаком | `0.60 × 0.64 × 1.64` | 424 |
| `citizen_coffee_f` | `assets/models/blender/people/citizen_coffee_f.glb` | Девушка в светлом тренче, шарфе и берете со стаканчиком кофе навынос в поднятой правой руке | `0.58 × 0.66 × 1.65` | 544 |
| `citizen_hiker_m` | `assets/models/blender/people/citizen_hiker_m.glb` | Турист в двухцветной ветровке, шортах, панаме и с походным рюкзаком с пенкой сверху | `0.60 × 0.66 × 1.66` | 492 |
| `citizen_coat_f` | `assets/models/blender/people/citizen_coat_f.glb` | Дама в длинном пальто с высокой причёской-пучком и крафтовым пакетом со свежими багетами | `0.60 × 0.60 × 1.68` | 440 |

### 2. Велосипедисты (`cyclist`, 4 модели)

| ID | Файл `.glb` | Описание | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|
| `cyclist_road` | `assets/models/blender/people/cyclist_road.glb` | Шоссейный велосипедист в велошлеме и джерси в спортивной посадке на руле-баране (замена `cyclist`) | `0.52 × 1.70 × 1.72` | 1012 |
| `cyclist_city_cruiser` | `assets/models/blender/people/cyclist_city_cruiser.glb` | Горожанка на городском сити-байке с заниженной рамой, в шляпке и с передней плетёной корзиной с покупками | `0.52 × 1.70 × 1.79` | 1180 |
| `cyclist_courier` | `assets/models/blender/people/cyclist_courier.glb` | Велокурьер доставки еды в кепке и куртке с большим квадратным термо-коробом на заднем багажнике | `0.52 × 1.70 × 1.74` | 1076 |
| `cyclist_commuter` | `assets/models/blender/people/cyclist_commuter.glb` | Офисный вело-коммьютер в городском шлеме с рюкзаком и двойными боковыми велосумками на заднем багажнике | `0.52 × 1.70 × 1.76` | 1116 |

---

## Готовые массивы путей для `scripts/grid/people_visualizer.gd`

```gdscript
const WALKER_MODELS: Array[String] = [
	"res://assets/models/blender/people/citizen_casual_m.glb",
	"res://assets/models/blender/people/citizen_dress_f.glb",
	"res://assets/models/blender/people/citizen_business_m.glb",
	"res://assets/models/blender/people/citizen_shopper_f.glb",
	"res://assets/models/blender/people/citizen_student_m.glb",
	"res://assets/models/blender/people/citizen_coffee_f.glb",
	"res://assets/models/blender/people/citizen_hiker_m.glb",
	"res://assets/models/blender/people/citizen_coat_f.glb",
]

const CYCLIST_MODELS: Array[String] = [
	"res://assets/models/blender/people/cyclist_road.glb",
	"res://assets/models/blender/people/cyclist_city_cruiser.glb",
	"res://assets/models/blender/people/cyclist_courier.glb",
	"res://assets/models/blender/people/cyclist_commuter.glb",
]
```
