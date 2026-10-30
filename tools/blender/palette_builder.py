"""Общие помощники для моделей CityBuilder в Blender: палитра Kenney и сборка модели из ящиков.

Каждая деталь берёт цвет одного образца палитры Kenney (colormap.png, сетка 8×4), поэтому свои
модели — в одном стиле с Kenney, и в игре их перекрашивает BuildingPalette (акценты — по INSTANCE_CUSTOM).
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
SKIN = (4, 2)       # тёплый — лица и руки (не перекрашивается)
PANTS = (4, 1)      # синий — брюки, джинсы (не перекрашивается)
SHIRT = (3, 1)      # красный акцент — одежда, рамы велосипедов (перекрашивается)
HAIR = (0, 3)       # почти чёрный — волосы, шины



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

    def cylinder(self, center, radius, depth, swatch, axis="z", segments=12):
        """Цилиндр (колёса, столбы): ось x, y или z; торцы — многоугольники."""
        cx, cy, cz = center
        base = len(self.verts)
        uv = swatch_uv(swatch)
        for side in (-0.5, 0.5):
            for i in range(segments):
                a = 2.0 * math.pi * i / segments
                u, v, w = radius * math.cos(a), radius * math.sin(a), depth * side
                if axis == "x":
                    self.verts.append((cx + w, cy + u, cz + v))
                elif axis == "y":
                    self.verts.append((cx + u, cy + w, cz + v))
                else:
                    self.verts.append((cx + u, cy + v, cz + w))
        for i in range(segments):
            j = (i + 1) % segments
            self.faces.append((base + i, base + j, base + segments + j, base + segments + i))
            self.uvs.append(uv)
        self.faces.append(tuple(base + i for i in reversed(range(segments))))
        self.uvs.append(uv)
        self.faces.append(tuple(base + segments + i for i in range(segments)))
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


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def export_glb(obj, name):
    """Сохраняет один объект в assets/models/blender/<name>.glb."""
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    print("MODEL", path, "verts", len(obj.data.vertices))
