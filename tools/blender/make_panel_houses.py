"""Панельные многоэтажки для CityBuilder: Blender строит low-poly модели и сохраняет GLB.

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_panel_houses.py

Модели красятся палитрой Kenney (assets/models/kenney/suburban/Textures/colormap.png):
каждая деталь берёт цвет одного образца сетки 8×4. Поэтому в игре работает перекраска
BuildingPalette: стены (белый образец) получают оттенок района, крыши (зелёный акцент) — цвет крыши.
Размеры — в единицах Kenney (дом ~1 ед.), масштаб в игре задаёт генератор типов.
"""

import math
import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PALETTE = os.path.join(ROOT, "assets", "models", "kenney", "suburban", "Textures", "colormap.png")
OUT_DIR = os.path.join(ROOT, "assets", "models", "blender")

# Образцы палитры: (столбец, строка) в сетке 8×4 (строка 0 — чёрная полоса сверху).
WALL = (3, 2)       # белый — стены (перекрашивается в оттенок района)
ROOF = (0, 1)       # зелёный акцент — крыша и козырьки (перекрашивается в цвет крыши)
GLASS = (5, 1)      # голубой — окна (не трогается)
FRAME = (1, 2)      # серый — рамы, балконы
DARK = (2, 2)       # тёмно-серый — цоколь, двери
TRIM = (0, 2)       # светло-серый — пояса между этажами

FLOOR_H = 0.3
WINDOW_STEP = 0.24


def swatch_uv(swatch):
    """Центр образца в UV Blender (v снизу вверх; glTF перевернёт обратно)."""
    col, row = swatch
    return ((col + 0.5) / 8.0, 1.0 - (row + 0.5) / 4.0)


def palette_material():
    material = bpy.data.materials.new("colormap")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(PALETTE)
    image.interpolation = "Closest"
    material.node_tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    return material


class Builder:
    """Собирает одну модель из ящиков; каждый ящик — своего образца палитры."""

    def __init__(self, name, material):
        self.name = name
        self.material = material
        self.verts = []
        self.faces = []
        self.uvs = []

    def box(self, center, size, swatch):
        cx, cy, cz = center
        sx, sy, sz = (s * 0.5 for s in size)
        base = len(self.verts)
        for dz in (-sz, sz):
            for dy in (-sy, sy):
                for dx in (-sx, sx):
                    self.verts.append((cx + dx, cy + dy, cz + dz))
        uv = swatch_uv(swatch)
        for quad in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self.faces.append(tuple(base + i for i in quad))
            self.uvs.append(uv)

    def build(self):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        layer = mesh.uv_layers.new(name="UVMap")
        for poly, uv in zip(mesh.polygons, self.uvs):
            for loop in poly.loop_indices:
                layer.data[loop].uv = uv
        mesh.materials.append(self.material)
        mesh.validate()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


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
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
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
    obj = b.build()
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    print("MODEL", path, "verts", len(obj.data.vertices))


# Три дома: «хрущёвка» (ур.1), девятиэтажка с балконами (ур.2), башня с надстройкой (ур.3).
panel_house("panel-a", 1.25, 0.6, 5, False, False)
panel_house("panel-b", 1.2, 0.65, 9, True, False)
panel_house("panel-c", 0.75, 0.75, 14, True, True)
