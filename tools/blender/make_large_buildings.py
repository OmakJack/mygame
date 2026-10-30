"""Крупные многоклеточные здания для CityBuilder (от 2 до 7 клеток) в палитре Kenney.

Запуск:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_large_buildings.py

Масштаб в метрах игры (CityGrid.CELL_SIZE = 2.0 м, model_scale = 1.0):
  - клетка (W, D) → основание до (2*W - 0.24) × (2*D - 0.24) м.
  - фасад смотрит на −Y в Blender → после экспорта glTF (+Z) и model_turns = 2 смотрит на −Z в Godot.
  - цвета из colormap.png (palette_builder): стены WALL и акценты ROOF перекрашиваются по районам.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palette_builder import (
    Builder,
    DARK,
    FRAME,
    GLASS,
    ROOF,
    SHIRT,
    TRIM,
    WALL,
    clear_scene,
    export_glb,
    palette_material,
)

CELL = 2.0
FLOOR_H = 0.48
WIN_STEP = 0.42
GRASS = (1, 1)  # зелёный газон во внутреннем дворе (или (2, 1))


def add_facade(b, cx, cy, z0, width, depth, floors, balconies=False, ribbon=False):
    """Окна на четырёх стенах прямоугольного крыла с центром (cx, cy) и низом z0."""
    sides = (
        ((cx, cy - depth * 0.5), (1, 0), width, True),
        ((cx, cy + depth * 0.5), (1, 0), width, False),
        ((cx - width * 0.5, cy), (0, 1), depth, False),
        ((cx + width * 0.5, cy), (0, 1), depth, False),
    )
    for (ox, oy), (ax, ay), length, front in sides:
        count = max(1, int(length / WIN_STEP))
        out = (0 if ax else (1 if ox > cx else -1), 0 if ay else (1 if oy > cy else -1))
        for fl in range(1, floors):
            z = z0 + fl * FLOOR_H + FLOOR_H * 0.54
            if ribbon:
                w_len = length * 0.88
                sz = (w_len if ax else 0.025, w_len if ay else 0.025, FLOOR_H * 0.46)
                b.box((ox + out[0] * 0.01, oy + out[1] * 0.01, z), sz, GLASS)
            else:
                for i in range(count):
                    t = (i + 0.5) / count - 0.5
                    x = ox + ax * t * length + out[0] * 0.01
                    y = oy + ay * t * length + out[1] * 0.01
                    sz = (WIN_STEP * 0.56 if ax else 0.025, WIN_STEP * 0.56 if ay else 0.025, FLOOR_H * 0.50)
                    b.box((x, y, z), sz, GLASS)
                    if front and balconies and fl % 2 == 1 and i % 2 == 0:
                        bx = x + out[0] * 0.07
                        by = y + out[1] * 0.07
                        b.box((bx, by, z - FLOOR_H * 0.26), (WIN_STEP * 0.88, 0.14, 0.04), FRAME)
                        b.box((bx, by + out[1] * 0.06, z - FLOOR_H * 0.14), (WIN_STEP * 0.88, 0.02, 0.14), WALL)
            b.box(
                (ox + out[0] * 0.006, oy + out[1] * 0.006, z0 + fl * FLOOR_H),
                (length if ax else 0.02, length if ay else 0.02, 0.028),
                TRIM,
            )


def add_wing(b, cx, cy, width, depth, floors, balconies=False, ribbon=False, arch_center=False):
    """Корпус крыла с цоколем, подъездами, окнами и парапетом крыши."""
    h = floors * FLOOR_H
    if arch_center and width >= 4.0:
        # Арка проезда по центру на высоту 2 этажей
        arch_w = 1.3
        side_w = (width - arch_w) * 0.5
        arch_h = FLOOR_H * 2.0
        for sign in (-1, 1):
            sx = cx + sign * (arch_w * 0.5 + side_w * 0.5)
            b.box((sx, cy, FLOOR_H * 0.5), (side_w, depth, FLOOR_H), DARK)
            b.box((sx, cy, FLOOR_H + FLOOR_H * 0.5), (side_w, depth, FLOOR_H), WALL)
        if floors > 2:
            b.box((cx, cy, arch_h + (h - arch_h) * 0.5), (width, depth, h - arch_h), WALL)
    else:
        b.box((cx, cy, FLOOR_H * 0.5), (width, depth, FLOOR_H), DARK)
        if floors > 1:
            b.box((cx, cy, FLOOR_H + (h - FLOOR_H) * 0.5), (width, depth, h - FLOOR_H), WALL)

    add_facade(b, cx, cy, 0.0, width, depth, floors, balconies=balconies, ribbon=ribbon)

    # Подъезды вдоль лицевой стены (−Y)
    entrances = max(1, int(width / 1.9))
    for i in range(entrances):
        ex = cx + ((i + 0.5) / entrances - 0.5) * width
        if arch_center and abs(ex - cx) < 0.8:
            continue
        b.box((ex, cy - depth * 0.5 - 0.01, FLOOR_H * 0.42), (0.24, 0.03, FLOOR_H * 0.78), FRAME)
        b.box((ex, cy - depth * 0.5 - 0.11, FLOOR_H * 0.88), (0.42, 0.22, 0.04), ROOF)

    # Крыша и вентшахты
    b.box((cx, cy, h + 0.03), (width + 0.06, depth + 0.06, 0.06), ROOF)
    shafts = max(1, int(width / 2.6))
    for i in range(shafts):
        sx = cx + ((i + 0.5) / shafts - 0.5) * (width * 0.7)
        b.box((sx, cy + 0.12, h + 0.16), (0.38, 0.34, 0.22), WALL)
        b.box((sx, cy + 0.12, h + 0.28), (0.42, 0.38, 0.03), TRIM)


def build_panel_linear(name, cells_w, floors, balconies, arch=False, end_towers=0):
    """Линейный многосекционный жилой дом на 3×1, 5×1 или 7×1 клеток."""
    clear_scene()
    b = Builder(name, palette_material())
    total_w = cells_w * CELL - 0.30
    depth = 1.38
    add_wing(b, 0.0, 0.0, total_w, depth, floors, balconies=balconies, arch_center=arch)
    if end_towers > 0:
        tw = 1.65
        td = 1.58
        for sign in (-1, 1):
            tx = sign * (total_w * 0.5 - tw * 0.5 + 0.05)
            add_wing(b, tx, -0.04, tw, td, floors + end_towers, balconies=True)
    export_glb(b.build(), name)


def build_panel_courtyard(name, floors_front, floors_back):
    """П-образный жилой квартал на 3×2 (6 клеток) с зелёным двориком внутри."""
    clear_scene()
    b = Builder(name, palette_material())
    full_w = 3 * CELL - 0.28  # 5.72 м
    full_d = 2 * CELL - 0.28  # 3.72 м
    # Плита двора и газон
    b.box((0.0, 0.0, 0.025), (full_w, full_d, 0.05), TRIM)
    b.box((0.0, 0.35, 0.055), (2.4, 1.5, 0.03), ROOF)
    wing_d = 1.22
    # Передний корпус вдоль улицы (−Y) с аркой во двор
    add_wing(b, 0.0, -full_d * 0.5 + wing_d * 0.5, full_w, wing_d, floors_front, balconies=True, arch_center=True)
    # Два боковых крыла вглубь двора (+Y)
    side_len = full_d - wing_d - 0.08
    for sign in (-1, 1):
        sx = sign * (full_w * 0.5 - wing_d * 0.5)
        sy = -full_d * 0.5 + wing_d + side_len * 0.5
        add_wing(b, sx, sy, wing_d, side_len, floors_back, balconies=True)
    export_glb(b.build(), name)


def build_commercial_strip(name, cells_w, floors):
    """Торговый ряд / пассаж на 3×1 или 5×1 клеток с витринами и цветными маркизами."""
    clear_scene()
    b = Builder(name, palette_material())
    w = cells_w * CELL - 0.28
    d = 1.52
    b.box((0.0, 0.0, 0.025), (w + 0.14, d + 0.24, 0.05), TRIM)
    add_wing(b, 0.0, 0.05, w, d, floors, balconies=False, ribbon=(floors >= 3))
    # Большие витрины 1-го этажа и навесы-маркизы
    bays = cells_w * 2
    bay_w = w / bays
    for i in range(bays):
        bx = ((i + 0.5) / bays - 0.5) * w
        b.box((bx, 0.05 - d * 0.5 - 0.015, FLOOR_H * 0.48), (bay_w * 0.76, 0.03, FLOOR_H * 0.72), GLASS)
        b.box((bx, 0.05 - d * 0.5 - 0.14, FLOOR_H * 0.92), (bay_w * 0.84, 0.26, 0.06), ROOF if i % 2 == 0 else SHIRT)
    export_glb(b.build(), name)


def build_shopping_mall(name, cells_w, cells_d, podium_floors, tower_floors):
    """Универмаг / ТРЦ на 2×2 (4 кл.) или 3×2 (6 кл.) со стеклянным атриумом и угловой башней."""
    clear_scene()
    b = Builder(name, palette_material())
    w = cells_w * CELL - 0.28
    d = cells_d * CELL - 0.28
    b.box((0.0, 0.0, 0.03), (w + 0.12, d + 0.12, 0.06), TRIM)
    add_wing(b, 0.0, 0.0, w, d, podium_floors, ribbon=True)
    podium_h = podium_floors * FLOOR_H
    # Стеклянный купол-фонарь атриума на крыше подиума
    atrium_w = w * 0.46
    atrium_d = d * 0.42
    b.box((-w * 0.12, 0.0, podium_h + 0.16), (atrium_w, atrium_d, 0.24), GLASS)
    b.box((-w * 0.12, 0.0, podium_h + 0.30), (atrium_w * 0.7, atrium_d * 0.7, 0.10), FRAME)
    # Входной портал ТРЦ
    b.box((-w * 0.12, -d * 0.5 - 0.08, podium_h * 0.45), (1.3, 0.18, podium_h * 0.85), GLASS)
    b.box((-w * 0.12, -d * 0.5 - 0.18, podium_h * 0.86), (1.5, 0.30, 0.08), SHIRT)
    # Угловая коммерческая башня
    if tower_floors > podium_floors:
        tw = min(1.85, w * 0.38)
        td = min(1.75, d * 0.52)
        add_wing(b, w * 0.5 - tw * 0.5 - 0.08, -d * 0.5 + td * 0.5 + 0.08, tw, td, tower_floors, ribbon=True)
    export_glb(b.build(), name)


def build_industrial_complex(name, cells_w, cells_d, hall_h, chimneys, tanks):
    """Заводские корпуса на 2×1 (2 кл.), 2×2 (4 кл.), 5×1 (5 кл.) и 3×2 (6 кл.)."""
    clear_scene()
    b = Builder(name, palette_material())
    w = cells_w * CELL - 0.26
    d = cells_d * CELL - 0.26
    # Бетонная промплощадка
    b.box((0.0, 0.0, 0.03), (w + 0.12, d + 0.12, 0.06), FRAME)
    hall_w = w * (0.72 if tanks > 0 else 0.92)
    hall_d = d * 0.78
    hx = -w * 0.5 + hall_w * 0.5 + 0.10
    hy = 0.06
    b.box((hx, hy, 0.22), (hall_w, hall_d, 0.44), DARK)
    b.box((hx, hy, 0.44 + (hall_h - 0.44) * 0.5), (hall_w, hall_d, hall_h - 0.44), WALL)
    b.box((hx, hy, hall_h + 0.04), (hall_w + 0.08, hall_d + 0.08, 0.08), ROOF)
    # Световые фонари шедовой крыши и ленточные окна цеха
    bays = max(2, int(hall_w / 1.15))
    for i in range(bays):
        bx = hx + ((i + 0.5) / bays - 0.5) * (hall_w * 0.88)
        b.box((bx, hy, hall_h + 0.18), (hall_w / bays * 0.65, hall_d * 0.76, 0.22), TRIM)
        b.box((bx, hy - hall_d * 0.38, hall_h + 0.18), (hall_w / bays * 0.58, 0.04, 0.16), GLASS)
        b.box((bx, hy - hall_d * 0.5 - 0.015, hall_h * 0.62), (hall_w / bays * 0.65, 0.03, 0.34), GLASS)
    # Ворота погрузки
    b.box((hx - hall_w * 0.28, hy - hall_d * 0.5 - 0.02, 0.34), (0.68, 0.04, 0.64), DARK)
    b.box((hx - hall_w * 0.28, hy - hall_d * 0.5 - 0.14, 0.70), (0.86, 0.26, 0.05), SHIRT)
    # Трубы
    for c in range(chimneys):
        cx = hx - hall_w * 0.32 + c * 0.85
        cy = hy + hall_d * 0.28
        ch_h = hall_h + 1.35 + c * 0.35
        b.cylinder((cx, cy, ch_h * 0.5), 0.20, ch_h, TRIM, axis="z", segments=12)
        b.cylinder((cx, cy, ch_h - 0.22), 0.22, 0.22, SHIRT, axis="z", segments=12)
        b.cylinder((cx, cy, ch_h - 0.58), 0.21, 0.18, SHIRT, axis="z", segments=12)
    # Цилиндрические резервуары справа на промплощадке
    for t in range(tanks):
        tx = w * 0.5 - 0.62
        ty = -d * 0.28 + t * 1.05
        b.cylinder((tx, ty, 0.52), 0.44, 0.98, TRIM, axis="z", segments=14)
        b.cylinder((tx, ty, 1.03), 0.46, 0.06, ROOF, axis="z", segments=14)
    export_glb(b.build(), name)


# --- Жилые многоэтажки (3, 5, 6 и 7 клеток, уровни 1..3) ---
build_panel_linear("panel-3x1-l1", 3, 5, False, arch=False)
build_panel_linear("panel-3x1-l2", 3, 8, True, arch=False)
build_panel_linear("panel-3x1-l3", 3, 11, True, arch=False, end_towers=2)

build_panel_linear("panel-5x1-l1", 5, 5, False, arch=True)
build_panel_linear("panel-5x1-l2", 5, 9, True, arch=True)
build_panel_linear("panel-5x1-l3", 5, 12, True, arch=True, end_towers=3)

build_panel_courtyard("panel-3x2-l1", 5, 4)
build_panel_courtyard("panel-3x2-l2", 8, 7)
build_panel_courtyard("panel-3x2-l3", 12, 10)

build_panel_linear("panel-7x1-l1", 7, 6, True, arch=True)
build_panel_linear("panel-7x1-l2", 7, 9, True, arch=True, end_towers=2)
build_panel_linear("panel-7x1-l3", 7, 12, True, arch=True, end_towers=4)

# --- Коммерция и ТРЦ (3, 4, 5 и 6 клеток, уровни 1..3) ---
build_commercial_strip("com-3x1-l1", 3, 1)
build_commercial_strip("com-3x1-l2", 3, 2)
build_commercial_strip("com-3x1-l3", 3, 3)

build_commercial_strip("com-5x1-l1", 5, 1)
build_commercial_strip("com-5x1-l2", 5, 2)
build_commercial_strip("com-5x1-l3", 5, 3)

build_shopping_mall("mall-2x2-l1", 2, 2, 2, 2)
build_shopping_mall("mall-2x2-l2", 2, 2, 3, 5)
build_shopping_mall("mall-2x2-l3", 2, 2, 3, 8)

build_shopping_mall("mall-3x2-l1", 3, 2, 2, 3)
build_shopping_mall("mall-3x2-l2", 3, 2, 3, 6)
build_shopping_mall("mall-3x2-l3", 3, 2, 4, 10)

# --- Промзона (2, 4, 5 и 6 клеток, уровни 1..3) ---
build_industrial_complex("ind-2x1-l1", 2, 1, 1.15, 1, 0)
build_industrial_complex("ind-2x1-l2", 2, 1, 1.50, 1, 1)
build_industrial_complex("ind-2x1-l3", 2, 1, 1.85, 2, 1)

build_industrial_complex("ind-2x2-l1", 2, 2, 1.25, 1, 1)
build_industrial_complex("ind-2x2-l2", 2, 2, 1.65, 2, 2)
build_industrial_complex("ind-2x2-l3", 2, 2, 2.10, 2, 2)

build_industrial_complex("ind-5x1-l1", 5, 1, 1.20, 1, 1)
build_industrial_complex("ind-5x1-l2", 5, 1, 1.55, 2, 1)
build_industrial_complex("ind-5x1-l3", 5, 1, 1.95, 3, 1)

build_industrial_complex("ind-3x2-l1", 3, 2, 1.40, 2, 2)
build_industrial_complex("ind-3x2-l2", 3, 2, 1.85, 2, 2)
build_industrial_complex("ind-3x2-l3", 3, 2, 2.30, 3, 3)
