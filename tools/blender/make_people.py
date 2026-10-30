"""Пешеходы и велосипедист для CityBuilder: Blender строит low-poly фигурки и сохраняет GLB.

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_people.py

Размеры — в метрах (человек ~1.75 м), вперёд — −Y (в glTF это +Z, как у машин Kenney).
Одежда и рама велосипеда — образец-акцент палитры Kenney: в игре BuildingPalette перекрашивает
его по INSTANCE_CUSTOM, поэтому у каждого прохожего своя куртка, а модели всего три.
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from palette_builder import DARK, FRAME, HAIR, PANTS, ROOF, SHIRT, SKIN, Builder, clear_scene, export_glb, palette_material  # noqa: E402


def head(b, z, long_hair):
    b.box((0, 0, z), (0.22, 0.22, 0.24), SKIN)
    b.box((0, 0.02, z + 0.12), (0.24, 0.24, 0.07), HAIR)
    if long_hair:
        b.box((0, 0.08, z - 0.04), (0.24, 0.1, 0.28), HAIR)


def person_a():
    """Прохожий в брюках и куртке."""
    clear_scene()
    b = Builder("person-a", palette_material())
    for x in (-0.09, 0.09):
        b.box((x, 0, 0.42), (0.13, 0.15, 0.84), PANTS)
        b.box((x, -0.03, 0.04), (0.14, 0.22, 0.08), DARK)
    b.box((0, 0, 1.12), (0.4, 0.22, 0.62), SHIRT)
    for x in (-0.26, 0.26):
        b.box((x, 0, 1.12), (0.1, 0.12, 0.58), SHIRT)
        b.box((x, 0, 0.78), (0.08, 0.09, 0.1), SKIN)
    head(b, 1.58, False)
    export_glb(b.build(), "person-a")


def person_b():
    """Прохожая в платье."""
    clear_scene()
    b = Builder("person-b", palette_material())
    for x in (-0.08, 0.08):
        b.box((x, 0, 0.3), (0.09, 0.1, 0.6), SKIN)
        b.box((x, -0.03, 0.03), (0.11, 0.18, 0.06), DARK)
    b.box((0, 0, 0.78), (0.46, 0.32, 0.44), SHIRT)
    b.box((0, 0, 1.15), (0.36, 0.22, 0.5), SHIRT)
    for x in (-0.23, 0.23):
        b.box((x, 0, 1.12), (0.08, 0.1, 0.5), SKIN)
    head(b, 1.56, True)
    export_glb(b.build(), "person-b")


def cyclist():
    """Велосипедист: велосипед (рама — акцент) и сидящий человек в шлеме."""
    clear_scene()
    b = Builder("cyclist", palette_material())
    wheel_r = 0.33
    for y in (-0.52, 0.52):
        b.cylinder((0, y, wheel_r), wheel_r, 0.05, HAIR, axis="x", segments=14)
        b.cylinder((0, y, wheel_r), 0.05, 0.08, FRAME, axis="x", segments=6)
    # Рама: нижняя и верхняя трубы, подседельная, руль.
    b.box((0, 0.0, 0.48), (0.05, 1.0, 0.05), SHIRT)
    b.box((0, -0.12, 0.72), (0.05, 0.75, 0.05), SHIRT)
    b.box((0, 0.22, 0.62), (0.05, 0.05, 0.5), SHIRT)
    b.box((0, -0.48, 0.66), (0.05, 0.05, 0.62), FRAME)
    b.box((0, -0.48, 0.98), (0.5, 0.05, 0.05), DARK)
    b.box((0, 0.22, 0.9), (0.14, 0.24, 0.05), DARK)
    # Человек: ноги на педалях, наклонённое туловище, руки к рулю, голова в шлеме.
    for x in (-0.1, 0.1):
        b.box((x, 0.12, 0.66), (0.12, 0.14, 0.5), PANTS)
    b.box((0, 0.05, 1.22), (0.38, 0.4, 0.55), SHIRT)
    for x in (-0.22, 0.22):
        b.box((x, -0.22, 1.12), (0.09, 0.45, 0.1), SHIRT)
    b.box((0, -0.12, 1.62), (0.22, 0.22, 0.24), SKIN)
    b.box((0, -0.1, 1.76), (0.26, 0.3, 0.1), ROOF)
    export_glb(b.build(), "cyclist")


person_a()
person_b()
cyclist()
