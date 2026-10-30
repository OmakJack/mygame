"""Панельные многоэтажки для CityBuilder: Blender строит low-poly модели и сохраняет GLB.

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_panel_houses.py

Модели красятся палитрой Kenney (assets/models/kenney/suburban/Textures/colormap.png):
каждая деталь берёт цвет одного образца сетки 8×4. Поэтому в игре работает перекраска
BuildingPalette: стены (белый образец) получают оттенок района, крыши (зелёный акцент) — цвет крыши.
Размеры — в единицах Kenney (дом ~1 ед.), масштаб в игре задаёт генератор типов.
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from palette_builder import DARK, FRAME, GLASS, ROOF, TRIM, WALL, Builder, clear_scene, export_glb, palette_material  # noqa: E402

FLOOR_H = 0.3
WINDOW_STEP = 0.24


def facade_windows(b, width, depth, floors, balconies, base_z):
    """Окна на четырёх стенах; у лицевой (−Y, вход) — с балконами через этаж, если balconies."""
    sides = (
        ((0, -depth * 0.5), (1, 0), width, True),
        ((0, depth * 0.5), (1, 0), width, False),
        ((-width * 0.5, 0), (0, 1), depth, False),
        ((width * 0.5, 0), (0, 1), depth, False),
    )
    for (ox, oy), (ax, ay), length, front in sides:
        count = max(1, int(length / WINDOW_STEP))
        outward = (0 if ax else (1 if ox > 0 else -1), 0 if ay else (1 if oy > 0 else -1))
        for floor in range(1, floors):
            z = base_z + floor * FLOOR_H + FLOOR_H * 0.55
            for i in range(count):
                t = (i + 0.5) / count - 0.5
                x = ox + ax * t * length + outward[0] * 0.006
                y = oy + ay * t * length + outward[1] * 0.006
                size = (WINDOW_STEP * 0.55 if ax else 0.02, WINDOW_STEP * 0.55 if ay else 0.02, FLOOR_H * 0.5)
                b.box((x, y, z), size, GLASS)
                if front and balconies and floor % 2 == 1 and i % 2 == 0:
                    bx = x + outward[0] * 0.05
                    by = y + outward[1] * 0.05
                    b.box((bx, by, z - FLOOR_H * 0.27), (WINDOW_STEP * 0.9, 0.1, 0.03), FRAME)
                    b.box((bx, by + outward[1] * 0.045, z - FLOOR_H * 0.17), (WINDOW_STEP * 0.9, 0.012, 0.09), WALL)
            # Пояс между этажами.
            b.box((ox + outward[0] * 0.004, oy + outward[1] * 0.004, base_z + floor * FLOOR_H),
                  (length if ax else 0.012, length if ay else 0.012, 0.018), TRIM)


def panel_house(name, width, depth, floors, balconies, tower_roof):
    clear_scene()
    material = palette_material()
    b = Builder(name, material)
    height = floors * FLOOR_H
    # Цоколь (первый этаж темнее) и корпус.
    b.box((0, 0, FLOOR_H * 0.5), (width, depth, FLOOR_H), DARK)
    b.box((0, 0, FLOOR_H + (height - FLOOR_H) * 0.5), (width, depth, height - FLOOR_H), WALL)
    facade_windows(b, width, depth, floors, balconies, 0.0)
    # Подъезды: двери и козырьки на лицевой стороне.
    entrances = max(1, int(width / 0.45))
    for i in range(entrances):
        x = ((i + 0.5) / entrances - 0.5) * width
        b.box((x, -depth * 0.5 - 0.005, FLOOR_H * 0.4), (0.12, 0.02, FLOOR_H * 0.75), FRAME)
        b.box((x, -depth * 0.5 - 0.07, FLOOR_H * 0.85), (0.22, 0.14, 0.025), ROOF)
    # Крыша: парапет и надстройки.
    b.box((0, 0, height + 0.02), (width + 0.03, depth + 0.03, 0.04), ROOF)
    b.box((width * 0.25, 0, height + 0.1), (0.22, 0.2, 0.16), WALL)
    if tower_roof:
        b.box((-width * 0.2, depth * 0.1, height + 0.14), (0.25, 0.25, 0.24), WALL)
        b.box((-width * 0.2, depth * 0.1, height + 0.27), (0.29, 0.29, 0.03), ROOF)
        b.box((width * 0.3, -depth * 0.2, height + 0.3), (0.015, 0.015, 0.5), FRAME)
    export_glb(b.build(), name)


# Три дома: «хрущёвка» (ур.1), девятиэтажка с балконами (ур.2), башня с надстройкой (ур.3).
panel_house("panel-a", 1.25, 0.6, 5, False, False)
panel_house("panel-b", 1.2, 0.65, 9, True, False)
panel_house("panel-c", 0.75, 0.75, 14, True, True)
