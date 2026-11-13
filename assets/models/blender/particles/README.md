# Набор партиклов и визуальных эффектов (Low-Poly Particles & VFX Pack v1)

Полный набор **низкополигональных 3D-партиклов, составных шлейфов и 2D-спрайтов** для оживления города в духе *SimCity 4* и *Cities: Skylines*:
- **20 составных 3D-эффектов и шлейфов (`assets/models/blender/particles/*.glb`)** — дым из печных и заводских труб, двойной заводской шлейф, белый пар градирен и вентиляций, ароматный пар над чашками кофеен, пожар здания с искрами и чёрным дымом, газовый факел НПЗ, снопы сварочных искр на стройке, облако пыли и обломков при сносе бульдозером, строительная пыль, выхлоп машин в пробках, струи городского фонтана, водяная струя пожарного брандспойта, круги на воде, кружащаяся листва в парках, стайка птиц в небе, дождевая тучка со струями дождя, снежный вихрь и праздничный салют конфетти со звёздами при повышении уровня здания (`Level-Up`).
- **12 одиночных 3D-мешей частиц (`assets/models/blender/particles/units/*.glb`)** — отдельные клубы дыма, язык пламени, искра, капля воды, кольцо волны, обломок кирпича, листок, птица, снежинка, золотая звезда и конфетти (для `GPUParticles3D` / `CPUParticles3D` или поштучного `MultiMeshInstance3D`).
- **8 процедурных 2D-спрайтов (`assets/models/blender/particles/sprites/*.png`, `256×256 RGBA`)** — для билборд-частиц (`QuadMesh`).

Регенерация из исходников (Blender 5.2 headless):
```powershell
& "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/make_particles.py
```

Исходные генераторы:
- `tools/blender/pack_particles.py`
- `tools/blender/make_particles.py`
- Манифест: `assets/models/blender/particles/manifest.json`
- Рендеры-превью:
  - `assets/models/blender/particles/previews/particles_plumes_catalog.png` (каталог всех 20 составных 3D-эффектов)
  - `assets/models/blender/particles/previews/particles_units_catalog.png` (каталог всех 12 одиночных 3D-мешей `units/*.glb`)
  - `assets/models/blender/particles/previews/particles_in_action_diorama.png` (диорама города с дымом из труб заводов и пекарен, ароматом кофеен, фонтаном, листвой, искрами стройки, пожаром и сносом бульдозером)

---

## Конвенции Godot 4 и шейдерная анимация через `MultiMeshInstance3D`

Все 20 составных моделей (`fx_*.glb`) спроектированы так, чтобы их можно было рисовать **одним экземпляром `MultiMeshInstance3D` на здание/источник** (по аналогии с `BadgeVisualizer`, `RotorVisualizer` и `ConstructionVisualizer`), без спавна сотен отдельных узлов и с полной детерминированностью в headless-проверках (`bash tests/run.sh`):

1. **Точка привязки `(0, 0, 0)`:**
   Начало координат модели всегда находится в **точке выброса** (верхний срез трубы, форсунка фонтана, центр крыши или участка). Ось высоты в Godot — **`+Y`**, снос ветром по умолчанию — вдоль **`+X`**.
2. **Материалы поверхностей (`ModelLoader.merge`):**
   Каждая цветовая группа внутри `.glb` имеет свой `StandardMaterial3D` с готовым `albedo_color` (как в `make_badges.py` и `make_construction.py`). При замене материала на `ShaderMaterial` достаточно передать `source.albedo_color` в `uniform vec4 albedo` (точно как в `BadgeVisualizer._make_layer`).
3. **Запечённые в вершины атрибуты для анимации в вершинном шейдере:**
   У каждого отдельного клуба дыма / капли / искры / листка / птицы в составном меше записаны:
   - **`UV.x`** = нормализованная фаза `t` (`0.0 .. 1.0`) вдоль струи от устья (`0.0`) до верхушки/края (`1.0`).
   - **`UV.y`** = индивидуальное случайное зерно элемента `seed` (`0.0 .. 1.0`).
   - **`UV2.xy`** = вектор направления/радиуса `(dx, dz)` элемента от оси.
   - **`NORMAL`** = наружная нормаль каждого отдельного клуба/кристалла относительно его собственного центра. Поэтому смещение `VERTEX += NORMAL * pulse` **масштабирует каждый клуб дыма/каплю на месте вокруг его собственного центра**!

### Готовый шейдер для `ParticleVisualizer` (по образцу `BadgeVisualizer`)

```gdscript
const PLUME_SHADER: String = """
shader_type spatial;
render_mode shadows_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float glow = 0.0;
uniform float speed = 2.2;
uniform float sway = 0.18;
uniform float bob = 0.10;
uniform float pulse = 0.035;

void vertex() {
	// INSTANCE_CUSTOM.r — фаза здания (0..1), INSTANCE_CUSTOM.g — масштаб интенсивности (0..1, Позволяет плавно гасить эффект на паузе или без света).
	float t = UV.x;
	float seed = UV.y;
	float phase = TIME * speed + INSTANCE_CUSTOM.r * TAU;
	// Бегущая волна подъёма и покачивания по ветру (сильнее к верхушке струи t -> 1):
	VERTEX.x += sin(phase - t * 4.5 + seed * 2.0) * sway * t;
	VERTEX.z += cos(phase * 0.85 - t * 4.0 + seed * TAU) * sway * 0.65 * t;
	VERTEX.y += sin(phase * 1.2 - t * 5.0 + seed * TAU) * bob * (0.15 + t);
	// Пульсация объёма каждого отдельного клуба вдоль его собственной нормали:
	VERTEX += NORMAL * (sin(phase * 1.5 + seed * TAU) * pulse * (0.4 + t));
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.75;
	EMISSION = albedo.rgb * glow;
}
"""
```

---

## Как автоматически находить устье трубы на любом здании

У всех заводов (`pack_industrial.py`), угольной ТЭЦ (`power_plant`), котельных и домов с трубами верхушка дымовой трубы — это **самая высокая часть меша здания (`mesh.get_aabb().end.y`)**.
Поэтому точные координаты среза трубы `(x, y, z)` в пространстве участка здания находятся за 5 строк без ручной разметки:

```gdscript
## Точка выброса дыма над самой высокой трубой меша здания (в координатах клетки здания).
static func chimney_top(mesh: Mesh) -> Vector3:
	var box: AABB = mesh.get_aabb()
	var top_y: float = box.end.y
	var sum := Vector2.ZERO
	var count: int = 0
	for surface: int in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			if v.y >= top_y - 0.06:
				sum += Vector2(v.x, v.z)
				count += 1
	var xz: Vector2 = sum / count if count > 0 else Vector2(box.get_center().x, box.get_center().z)
	return Vector3(xz.x, top_y, xz.y)
```

Кроме того, в `assets/models/blender/particles/manifest.json` в разделе `building_emitters.explicit_building_emitters_godot_xyz` приведена готовая таблица точных координат для зданий с несколькими трубами, градирнями, факелами НПЗ и гигантскими чашками кофе на крышах кофеен.

---

## 1. Составные 3D-эффекты и шлейфы (20 моделей в `assets/models/blender/particles/`)

### А. Дым из труб и пар (`smoke_steam` — 6 моделей)

| ID | Файл `.glb` | Описание | Где использовать в игре | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|---:|
| `fx_smoke_chimney_light` | `assets/models/blender/particles/fx_smoke_chimney_light.glb` | Лёгкий белый/светло-серый печной и каминный дымок (9 кучевых клубов) | Жилые дома (`RESIDENTIAL` 1×1…3×2), пекарни (`com_corner_bakery_1x1`), пиццерии (`com_bistro_terrace_2x1`) | `0.63 × 0.51 × 1.47` | 540 |
| `fx_smoke_factory_heavy` | `assets/models/blender/particles/fx_smoke_factory_heavy.glb` | Густой тёмный заводской дым и копоть с отблеском жара у жерла трубы | Заводские трубы (`INDUSTRIAL`) и угольная ТЭЦ (`power_plant`) | `1.73 × 0.93 × 2.59` | 1060 |
| `fx_smoke_twin_stacks` | `assets/models/blender/particles/fx_smoke_twin_stacks.glb` | Двойной шлейф индустриального дыма для сдвоенных труб | Крупные заводы и литейные цеха (`ind_red_foundry_3x1`, `ind_heavy_works_7x1`) | `1.82 × 0.89 × 2.25` | 1200 |
| `fx_steam_cooling_tower` | `assets/models/blender/particles/fx_steam_cooling_tower.glb` | Широкий бурлящий столб белоснежного пара градирни | Градирни и котельные (`ind_boiler_house_1x1`, `ind_thermo_plant_3x2`) | `1.36 × 1.35 × 2.19` | 1440 |
| `fx_steam_vent_puff` | `assets/models/blender/particles/fx_steam_vent_puff.glb` | Компактные клубы пара крышной вентиляции и кухонных вытяжек | Крышные блоки HVAC офисов, ТРЦ, больниц и ресторанов | `0.56 × 0.39 × 0.95` | 420 |
| `fx_cafe_aroma_swirl` | `assets/models/blender/particles/fx_cafe_aroma_swirl.glb` | Три спиральные ленты и облачка горячего кофейного пара/аромата | Гигантские 3D-чашки кофе на крышах кофеен, торговых рядов и моллов (`com_street_cafe_1x1`, `com_strip_shops_3x1`, `com_market_promenade_5x1`, `com_supermarket_plaza_3x2`, `com_metropolis_mall_3x2`) | `0.40 × 0.35 × 1.01` | 624 |

### Б. Огонь, факелы НПЗ и сварочные искры (`fire_sparks` — 3 модели)

| ID | Файл `.glb` | Описание | Где использовать в игре | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|---:|
| `fx_fire_building_blaze` | `assets/models/blender/particles/fx_fire_building_blaze.glb` | Языки пламени, разлетающиеся искры и столб чёрного дыма сверху | Пожары зданий, выезды пожарных машин (`fire_station`, `fire_depot_2x1`) | `1.11 × 0.90 × 2.15` | 820 |
| `fx_fire_refinery_flare` | `assets/models/blender/particles/fx_fire_refinery_flare.glb` | Вертикальный газовый факел с голубой горелкой и шапкой копоти | Факельные трубы нефтехимии и НПЗ (`ind_refinery_complex_3x2`, `ind_chem_reactor_2x1`) | `0.62 × 0.41 × 1.39` | 198 |
| `fx_sparks_welding_burst` | `assets/models/blender/particles/fx_sparks_welding_burst.glb` | Яркая бело-голубая вспышка электродуги и 18 разлетающихся дугой искр | Стройплощадки (`ConstructionVisualizer` — у крюка крана или верхнего среза стены `cut_height`) и ремонт зданий | `1.00 × 1.00 × 0.50` | 188 |

### В. Стройка, снос бульдозером и выхлоп транспорта (`dust_traffic` — 3 модели)

| ID | Файл `.glb` | Описание | Где использовать в игре | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|---:|
| `fx_dust_bulldoze_burst` | `assets/models/blender/particles/fx_dust_bulldoze_burst.glb` | Кольцо клубов цементной пыли с летящими кирпичами, бетоном и досками | Снос зданий, модулей и дорог бульдозером (`BuildTool` — одноразовая вспышка на `0.8–1.2 с`) | `1.82 × 1.63 × 0.68` | 872 |
| `fx_dust_construction_site` | `assets/models/blender/particles/fx_dust_construction_site.glb` | Стелющиеся клубы песочно-строительной пыли у земли | Вокруг фундамента строящихся зданий (`ConstructionVisualizer`) и у грузовых рамп заводов | `1.42 × 0.67 × 0.55` | 360 |
| `fx_car_exhaust_puff` | `assets/models/blender/particles/fx_car_exhaust_puff.glb` | Горизонтальная струйка серо-сизого выхлопного дыма | За грузовиками и машинами на загруженных дорогах/пробках (`TrafficVisualizer`) | `0.28 × 0.70 × 0.35` | 120 |

### Г. Вода, фонтаны, брандспойты и круги на воде (`water` — 3 модели)

| ID | Файл `.glb` | Описание | Где использовать в игре | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|---:|
| `fx_fountain_park_jets` | `assets/models/blender/particles/fx_fountain_park_jets.glb` | Центральный пенный гейзер, 6 дугообразных струй из капель и круги на воде | Парки и площади (`Park.PLAZA`, `Park.SQUARE`), скверы у многоэтажек и ТРЦ | `1.20 × 1.14 × 1.29` | 1044 |
| `fx_water_fire_hose` | `assets/models/blender/particles/fx_water_fire_hose.glb` | Направленная параболическая струя воды с веером пенных брызг | Тушение пожаров, полив в парках или авария водопровода | `0.52 × 1.82 × 1.10` | 408 |
| `fx_water_ripples_splash` | `assets/models/blender/particles/fx_water_ripples_splash.glb` | Три концентрических пенных кольца на воде с каплями всплеска | У водозаборных станций (`water_station`), насосов (`water_pump`) и берегов | `1.32 × 1.30 × 0.33` | 444 |

### Д. Природа, парки, погода и праздник (`nature_weather` & `celebrate` — 5 моделей)

| ID | Файл `.glb` | Описание | Где использовать в игре | Габариты (`X × Y × Z`, м) | Треугольники |
|---|---|---|---|---|---:|
| `fx_nature_falling_leaves` | `assets/models/blender/particles/fx_nature_falling_leaves.glb` | Вихрь из 18 зелёных, салатовых, золотых и осенних листочков | Над парками (`SQUARE`, `GARDEN`), деревьями (`TreeVisualizer`) и зелёными дворами | `1.34 × 1.37 × 1.34` | 576 |
| `fx_nature_flock_birds` | `assets/models/blender/particles/fx_nature_flock_birds.glb` | Стайка из 7 кружащих белых чаек и сизых голубей с разным взмахом крыльев | В небе над парками, площадями, рынками и водоёмами | `1.41 × 1.19 × 0.72` | 154 |
| `fx_weather_rain_cloud` | `assets/models/blender/particles/fx_weather_rain_cloud.glb` | Грозовая тучка с 14 косыми струями дождя и кругами на лужах | Погодный эффект дождя | `1.09 × 0.82 × 1.82` | 568 |
| `fx_weather_snow_swirl` | `assets/models/blender/particles/fx_weather_snow_swirl.glb` | Вихрь из 10 шестилучевых 3D-снежинок и 8 снежных пушинок | Зимняя погода и снегопад | `1.26 × 1.27 × 1.34` | 520 |
| `fx_celebrate_levelup_confetti` | `assets/models/blender/particles/fx_celebrate_levelup_confetti.glb` | Праздничный салют из 7 золотых 3D-звёзд и 20 разноцветных конфетти | Вспышка радости над зданием при повышении уровня (`Level-Up`) или новом звании города | `1.25 × 1.32 × 1.35` | 380 |

---

## 2. Одиночные 3D-меши частиц (`assets/models/blender/particles/units/*.glb` — 12 моделей)

Для использования в `GPUParticles3D.draw_pass_1`, `CPUParticles3D.mesh` или поштучном `MultiMeshInstance3D`:

1. `res://assets/models/blender/particles/units/unit_smoke_puff_soft.glb` — кучевой клуб дыма/пара из 4 долей (`80 tris`)
2. `res://assets/models/blender/particles/units/unit_smoke_puff_faceted.glb` — лёгкий икосаэдрический клуб дыма/пыли (`20 tris`)
3. `res://assets/models/blender/particles/units/unit_flame_shard.glb` — гранёный язык пламени (`46 tris`)
4. `res://assets/models/blender/particles/units/unit_spark_crystal.glb` — октаэдрический кристалл искры (`8 tris`)
5. `res://assets/models/blender/particles/units/unit_water_drop.glb` — объёмная капля воды (`24 tris`)
6. `res://assets/models/blender/particles/units/unit_water_ripple_ring.glb` — горизонтальное кольцо волны на воде (`108 tris`)
7. `res://assets/models/blender/particles/units/unit_rubble_chunk.glb` — гранёный обломок кирпича/бетона (`12 tris`)
8. `res://assets/models/blender/particles/units/unit_leaf.glb` — резной древесный листок с V-прожилкой (`32 tris`)
9. `res://assets/models/blender/particles/units/unit_bird_glide.glb` — одиночная птица в полёте (`22 tris`)
10. `res://assets/models/blender/particles/units/unit_snowflake_hex.glb` — шестилучевая объёмная снежинка (`36 tris`)
11. `res://assets/models/blender/particles/units/unit_star_gold.glb` — пятиконечная золотая звезда (`20 tris`)
12. `res://assets/models/blender/particles/units/unit_confetti_tile.glb` — пластинка праздничного конфетти (`12 tris`)

---

## 3. Процедурные 2D-спрайты (`assets/models/blender/particles/sprites/*.png` — 8 текстур `256×256 RGBA`)

1. `res://assets/models/blender/particles/sprites/sprite_smoke_puff.png` — мягкий клуб дыма и пара
2. `res://assets/models/blender/particles/sprites/sprite_smoke_toon.png` — стилизованный тун-клуб дыма
3. `res://assets/models/blender/particles/sprites/sprite_flame_glow.png` — язык пламени и свечения
4. `res://assets/models/blender/particles/sprites/sprite_spark_star.png` — четырёхлучевая искра / блик
5. `res://assets/models/blender/particles/sprites/sprite_water_drop.png` — капля воды с бликом
6. `res://assets/models/blender/particles/sprites/sprite_ripple_ring.png` — концентрические круги на воде
7. `res://assets/models/blender/particles/sprites/sprite_leaf.png` — древесный листок с прожилкой
8. `res://assets/models/blender/particles/sprites/sprite_snowflake.png` — шестилучевая снежинка
