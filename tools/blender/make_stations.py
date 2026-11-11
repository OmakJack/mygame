"""Станции света и воды с модулями (как в SimCity): участок 4×3 клетки, на нём — здание станции,
служебный проезд и площадки под модули (ветряки, насосы, башни), которые игрок достраивает.

Запуск (без окна, Blender 5.2):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/make_stations.py

Результат — assets/models/blender/stations/:
  wind_station.glb   — ветростанция: диспетчерская, трансформатор, проезд, три площадки, ограда
  water_station.glb  — водозабор: насосная, резервуар, трубы, проезд, три площадки, ограда
  station_road.glb   — модуль «Служебная дорога»: проезд до краёв участка и ещё три площадки
  water_pump.glb     — модуль «Насос» (скважина с насосом), 1×1

Координаты — как в игре (метры, середина участка в нуле): x — вдоль улицы, z — вглубь, фасад на −z.
В Blender это (−x, z): игра разворачивает модель на 180° (model_turns = 2, как у остальных моделей).
Раскладка участка — в scripts/data/station_modules.gd (PADS): менять вместе.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arch_kit import (  # noqa: E402
    ALUM,
    CHARCOAL,
    CONCRETE,
    GUNMETAL,
    IRON,
    ROOT,
    SLATE,
    STEEL,
    STONE,
    WALL,
    ArchBuilder,
    clear_scene,
)

# Точные цвета строки 1 палитры Kenney (службы не перекрашиваются).
EMERALD = (0, 1)
GOLD = (1, 1)
CRIMSON = (3, 1)
ROYAL_BLUE = (4, 1)
SKY_BLUE = (5, 1)

OUT_DIR = os.path.join(ROOT, "assets", "models", "blender", "stations")

# Участок 4×3 клетки по 2 м, с отступом 0.1 м от края (как BuildingMeshes._max_size).
HALF_W = 3.9
HALF_D = 2.9
LANE_H = 0.03
PAD_H = 0.06
# Площадки под модули (x, z в координатах игры): три у станции, три — с модулем «Служебная дорога».
BASE_PADS = [(1.0, -2.0), (-1.0, 2.0), (1.0, 2.0)]
ROAD_PADS = [(3.0, -2.0), (3.0, 2.0), (-3.0, 2.0)]


def at(x, z, height=0.0):
    """Точка игры (x, z) и высота → координаты Blender."""
    return (-x, z, height)


def lane(b, x0, x1, z0, z1):
    """Асфальт проезда между точками игры."""
    b.box(at((x0 + x1) * 0.5, (z0 + z1) * 0.5, LANE_H * 0.5), (abs(x1 - x0), abs(z1 - z0), LANE_H), CHARCOAL,
          skip_bottom=True)


def dash(b, x, z, along_x):
    size = (0.34, 0.05, 0.006) if along_x else (0.05, 0.34, 0.006)
    b.box(at(x, z, LANE_H + 0.004), size, WALL, grad=False, skip_bottom=True)


def pad(b, x, z):
    """Бетонная площадка под модуль с анкерной плитой."""
    b.box(at(x, z, PAD_H * 0.5), (1.56, 1.56, PAD_H), CONCRETE, skip_bottom=True)
    b.box(at(x, z, PAD_H + 0.008), (1.36, 1.36, 0.016), STONE, skip_bottom=True)


def curb_and_fence(b, accent):
    """Бордюр по краю участка и лёгкая ограда с трёх сторон (фасад открыт)."""
    t = 0.07
    for x, z, w, d in [(0.0, -HALF_D + t * 0.5, HALF_W * 2.0, t), (0.0, HALF_D - t * 0.5, HALF_W * 2.0, t),
                       (-HALF_W + t * 0.5, 0.0, t, HALF_D * 2.0), (HALF_W - t * 0.5, 0.0, t, HALF_D * 2.0)]:
        b.box(at(x, z, 0.025), (w, d, 0.05), STONE, skip_bottom=True)
    post_h = 0.34
    inset = 0.1
    # Столбики: сзади и по бокам, шаг около метра.
    posts = []
    steps_w = 8
    for i in range(steps_w + 1):
        posts.append((-HALF_W + inset + (HALF_W * 2.0 - inset * 2.0) * i / steps_w, HALF_D - inset))
    steps_d = 6
    for i in range(steps_d):
        z = -HALF_D + inset + (HALF_D * 2.0 - inset * 2.0) * i / steps_d
        posts.append((-HALF_W + inset, z))
        posts.append((HALF_W - inset, z))
    for x, z in posts:
        b.box(at(x, z, post_h * 0.5), (0.05, 0.05, post_h), STEEL, skip_bottom=True)
    # Перекладины.
    for height, swatch in [(post_h - 0.03, accent), (post_h * 0.5, STEEL)]:
        b.box(at(0.0, HALF_D - inset, height), (HALF_W * 2.0 - inset * 2.0, 0.025, 0.025), swatch, grad=False)
        for x in (-HALF_W + inset, HALF_W - inset):
            b.box(at(x, 0.0, height), (0.025, HALF_D * 2.0 - inset * 2.0, 0.025), swatch, grad=False)
    # Ворота у въезда: две стойки с полосатым шлагбаумом.
    for x in (-1.62, -0.38):
        b.box(at(x, -HALF_D + 0.16, 0.2), (0.08, 0.08, 0.4), GUNMETAL, skip_bottom=True)
    b.box(at(-1.62, -HALF_D + 0.16, 0.43), (0.12, 0.12, 0.06), accent)
    b.box(at(-0.38, -HALF_D + 0.16, 0.43), (0.12, 0.12, 0.06), accent)


def base_lanes(b):
    """Проезд станции: въезд с улицы и поперечный проезд к площадкам."""
    lane(b, -1.5, -0.5, -HALF_D + 0.07, 0.5)
    lane(b, -1.5, 1.9, -0.5, 0.5)
    for z in (-2.2, -1.5, -0.8):
        dash(b, -1.0, z, False)
    for x in (-0.3, 0.5, 1.3):
        dash(b, x, 0.0, True)


def control_house(b, x, z, wall, band, roof):
    """Небольшое техническое здание: цоколь, стены, пояс цвета станции, плоская кровля, дверь и окно на фасаде."""
    w, d, h = 1.36, 1.42, 0.92
    bx, by, _ = at(x, z)
    b.box((bx, by, 0.05), (w + 0.08, d + 0.08, 0.1), CONCRETE, skip_bottom=True)
    b.box((bx, by, 0.1 + h * 0.5), (w, d, h), wall, skip_bottom=True)
    b.box((bx, by, 0.1 + h - 0.13), (w + 0.03, d + 0.03, 0.1), band, grad=False)
    b.box((bx, by, 0.1 + h + 0.035), (w + 0.1, d + 0.1, 0.07), roof)
    # Фасад смотрит на улицу (−Y Blender).
    y_wall = by - d * 0.5
    b.entrance_canopy(bx + 0.3, y_wall, 0.1, w=0.36, h=0.56, canopy_d=0.16, canopy_swatch=band)
    b.window_unit(bx - 0.3, y_wall, 0.42, (0, -1), 0.4, 0.3)
    b.window_unit(bx - w * 0.5, by + 0.1, 0.42, (-1, 0), 0.5, 0.3)
    return bx, by, 0.1 + h + 0.07


def build_wind_station():
    clear_scene()
    b = ArchBuilder("wind_station")
    curb_and_fence(b, EMERALD)
    base_lanes(b)
    for x, z in BASE_PADS:
        pad(b, x, z)
    bx, by, top = control_house(b, -3.1, -1.95, WALL, EMERALD, SLATE)
    # На крыше — мачта с анемометром и блок вентиляции.
    b.rooftop_hvac(bx - 0.3, by + 0.35, top, scale=0.6)
    b.cylinder((bx + 0.4, by + 0.4, top + 0.45), 0.025, 0.02, 0.9, STEEL, segments=6)
    b.box((bx + 0.4, by + 0.4, top + 0.86), (0.36, 0.03, 0.03), STEEL, grad=False)
    for dx in (-0.18, 0.18):
        b.cylinder((bx + 0.4 + dx, by + 0.4, top + 0.9), 0.045, 0.045, 0.05, EMERALD, segments=8)
    b.box((bx + 0.4, by + 0.4, top + 0.62), (0.03, 0.2, 0.12), GOLD, grad=False)
    # Трансформатор у здания: бак с рёбрами, изоляторы, жёлтая полоса.
    tx, ty, _ = at(-3.2, 0.0)
    b.box((tx, ty, 0.04), (1.1, 1.3, 0.08), CONCRETE, skip_bottom=True)
    b.box((tx, ty, 0.08 + 0.3), (0.62, 0.8, 0.6), ALUM, skip_bottom=True)
    b.box((tx, ty, 0.08 + 0.12), (0.64, 0.82, 0.05), GOLD, grad=False)
    for dy in (-0.3, -0.1, 0.1, 0.3):
        for sx in (-0.34, 0.34):
            b.box((tx + sx, ty + dy, 0.08 + 0.3), (0.05, 0.1, 0.46), GUNMETAL, skip_bottom=True)
    for dy in (-0.24, 0.0, 0.24):
        b.cylinder((tx, ty + dy, 0.08 + 0.6 + 0.09), 0.05, 0.035, 0.18, STONE, segments=8)
        b.cylinder((tx, ty + dy, 0.08 + 0.6 + 0.2), 0.02, 0.02, 0.06, IRON, segments=6)
    # Кабельный лоток от трансформатора к проезду.
    b.box(at(-2.1, 0.0, LANE_H + 0.02), (0.9, 0.14, 0.04), GUNMETAL, skip_bottom=True)
    return b


def build_water_station():
    clear_scene()
    b = ArchBuilder("water_station")
    curb_and_fence(b, ROYAL_BLUE)
    base_lanes(b)
    for x, z in BASE_PADS:
        pad(b, x, z)
    bx, by, top = control_house(b, -3.1, -1.95, WALL, ROYAL_BLUE, SLATE)
    b.rooftop_hvac(bx + 0.2, by + 0.3, top, scale=0.6)
    # Резервуар чистой воды: низкий бак с крышкой и лестницей.
    tx, ty, _ = at(-3.05, 0.05)
    b.cylinder((tx, ty, 0.03), 0.78, 0.78, 0.06, CONCRETE, segments=18)
    b.cylinder((tx, ty, 0.06 + 0.36), 0.7, 0.7, 0.72, ALUM, segments=18)
    b.cylinder((tx, ty, 0.06 + 0.5), 0.715, 0.715, 0.1, ROYAL_BLUE, segments=18, grad=False)
    b.cylinder((tx, ty, 0.06 + 0.72 + 0.05), 0.7, 0.2, 0.1, STONE, segments=18)
    b.cylinder((tx, ty, 0.06 + 0.72 + 0.14), 0.12, 0.12, 0.08, SKY_BLUE, segments=10)
    b.box((tx - 0.72, ty, 0.45), (0.04, 0.2, 0.78), STEEL, skip_bottom=True)
    # Трубы от резервуара к насосной и к проезду, задвижки.
    b.cylinder((tx, ty - 0.95, 0.2), 0.07, 0.07, 0.6, ROYAL_BLUE, axis="y", segments=10)
    b.cylinder((tx - 1.0, ty, 0.2), 0.07, 0.07, 0.7, ROYAL_BLUE, axis="x", segments=10)
    for px, py in [(tx, ty - 0.95), (tx - 1.0, ty)]:
        b.cylinder((px, py, 0.33), 0.09, 0.09, 0.03, CRIMSON, segments=10)
        b.cylinder((px, py, 0.27), 0.02, 0.02, 0.1, IRON, segments=6)
    b.box((tx - 1.38, ty, 0.14), (0.12, 0.24, 0.28), GUNMETAL, skip_bottom=True)
    return b


def build_station_road():
    clear_scene()
    b = ArchBuilder("station_road")
    # Проезд вправо до края участка и узкая дорожка влево, за трансформатор или резервуар станции.
    lane(b, 1.9, HALF_W - 0.07, -0.5, 0.5)
    lane(b, -1.5, -1.0, 0.5, 0.86)
    lane(b, -3.6, -1.0, 0.86, 1.18)
    for x in (2.4, 3.2):
        dash(b, x, 0.0, True)
    for x, z in ROAD_PADS:
        pad(b, x, z)
    # Разворотный карман и фонарь у дальнего конца проезда.
    lx, ly, _ = at(HALF_W - 0.5, -0.75)
    b.cylinder((lx, ly, 0.5), 0.03, 0.022, 1.0, STEEL, segments=6)
    b.box((lx, ly + 0.14, 1.0), (0.07, 0.3, 0.04), GUNMETAL)
    b.box((lx, ly + 0.24, 0.975), (0.06, 0.1, 0.02), GOLD, grad=False)
    return b


def build_water_pump():
    clear_scene()
    b = ArchBuilder("water_pump")
    # Основание — чуть меньше площадки станции, чтобы стоять на её анкерной плите.
    b.box((0.0, 0.0, 0.03), (1.3, 1.3, 0.06), CONCRETE, skip_bottom=True)
    # Обсадная труба скважины с оголовком и вертикальный насос с мотором.
    b.cylinder((-0.15, 0.1, 0.06 + 0.1), 0.24, 0.24, 0.2, GUNMETAL, segments=12)
    b.cylinder((-0.15, 0.1, 0.26 + 0.24), 0.17, 0.17, 0.48, ROYAL_BLUE, segments=12)
    b.cylinder((-0.15, 0.1, 0.74 + 0.03), 0.2, 0.2, 0.06, STEEL, segments=12)
    b.cylinder((-0.15, 0.1, 0.8 + 0.2), 0.14, 0.14, 0.4, ALUM, segments=12)
    b.cylinder((-0.15, 0.1, 1.2 + 0.03), 0.16, 0.12, 0.06, GUNMETAL, segments=12)
    # Напорная труба с задвижкой уходит в землю у края площадки.
    b.cylinder((0.18, 0.1, 0.44), 0.07, 0.07, 0.5, ROYAL_BLUE, axis="x", segments=10)
    b.cylinder((0.43, 0.1, 0.25), 0.07, 0.07, 0.42, ROYAL_BLUE, segments=10)
    b.cylinder((0.43, 0.1, 0.46), 0.1, 0.1, 0.05, STEEL, segments=10)
    b.cylinder((0.2, 0.1, 0.6), 0.1, 0.1, 0.03, CRIMSON, segments=10)
    b.cylinder((0.2, 0.1, 0.54), 0.02, 0.02, 0.1, IRON, segments=6)
    # Шкаф управления с жёлтой полосой.
    b.box((0.36, -0.42, 0.06 + 0.25), (0.3, 0.2, 0.5), ALUM, skip_bottom=True)
    b.box((0.36, -0.53, 0.06 + 0.36), (0.22, 0.01, 0.1), GOLD, grad=False)
    b.box((0.36, -0.42, 0.06 + 0.52), (0.34, 0.24, 0.04), SLATE)
    return b


def export(builder):
    obj = builder.build_object()
    os.makedirs(OUT_DIR, exist_ok=True)
    filepath = os.path.join(OUT_DIR, f"{builder.name}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=filepath, export_format="GLB", use_selection=True, export_yup=True,
                              export_animations=False)
    xs = [v[0] for v in builder.verts]
    ys = [v[1] for v in builder.verts]
    zs = [v[2] for v in builder.verts]
    tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
    print(f"STATION {builder.name}: x {min(xs):.2f}..{max(xs):.2f} y {min(ys):.2f}..{max(ys):.2f} "
          f"z {min(zs):.2f}..{max(zs):.2f} tris={tris}")


def main():
    for build in (build_wind_station, build_water_station, build_station_road, build_water_pump):
        export(build())


main()
