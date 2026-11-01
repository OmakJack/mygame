"""Стройка (как в Cities: Skylines): строительные леса и башенный кран — детали для ConstructionVisualizer.
Godot собирает из них площадку любого размера: леса — модулями вокруг дома до текущей высоты,
кран — секциями мачты нужной высоты, стрела растягивается под размер участка.

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_construction.py

Результат (метры игры; Blender −Y → Godot +Z):
  - assets/models/blender/construction/scaffold.glb — модуль лесов 1 × 0.5 м: x −0.5..0.5, высота 0..0.5,
    у стены — y = 0, наружу — на −Y (в Godot — на +Z);
  - crane_mast.glb — секция мачты 1 м (основание в нуле);
  - crane_top.glb — поворотная часть над мачтой: кабина, оголовок, противовесная консоль (начало — верх мачты);
  - crane_jib.glb — стрела длиной 1 вдоль +X (Godot растягивает по X) с тягой к оголовку;
  - crane_cable.glb — трос длиной 1 вниз от нуля (растягивается по Y);
  - crane_hook.glb — крюковая обойма с пачкой балок (начало — низ троса);
  - docs/collab/visual/construction_preview.png — превью собранного крана и лесов.
"""

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "models", "blender", "construction")
PREVIEW = os.path.join(ROOT, "docs", "collab", "visual", "construction_preview.png")

# Цвета в sRGB.
CRANE_YELLOW = (1.0, 0.74, 0.08)
DARK = (0.18, 0.19, 0.21)
STEEL = (0.62, 0.66, 0.7)
WOOD = (0.78, 0.58, 0.33)
CONCRETE = (0.66, 0.65, 0.62)
GLASS = (0.32, 0.5, 0.62)
WHITE = (0.94, 0.93, 0.9)
LOAD = (0.55, 0.36, 0.22)

MAST_W = 0.32
MAST_POST = 0.045


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


_materials = {}


def mat(name, srgb, roughness=0.55, metallic=0.0):
    if name not in _materials:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*srgb_to_linear(srgb), 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        _materials[name] = m
    return _materials[name]


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    _materials.clear()


def box(center, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def beam(a, b, thickness, material):
    """Брус квадратного сечения thickness от точки a до точки b."""
    a, b = Vector(a), Vector(b)
    direction = b - a
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(a + b) * 0.5)
    obj = bpy.context.active_object
    obj.scale = (thickness, thickness, direction.length)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(material)
    return obj


# --- Детали ---

def build_scaffold():
    steel = mat("scaffold_steel", STEEL, roughness=0.4, metallic=0.3)
    wood = mat("scaffold_wood", WOOD, roughness=0.8)
    pole = 0.028
    inner, outer = -0.03, -0.2
    for x in (-0.48, 0.48):
        for y in (inner, outer):
            beam((x, y, 0.0), (x, y, 0.5), pole, steel)
        beam((x, inner, 0.49), (x, outer, 0.49), pole * 0.8, steel)
    for y in (inner, outer):
        beam((-0.5, y, 0.49), (0.5, y, 0.49), pole * 0.8, steel)
    beam((-0.5, outer, 0.27), (0.5, outer, 0.27), pole * 0.7, steel)
    beam((-0.47, outer, 0.03), (0.47, outer, 0.46), pole * 0.7, steel)
    box((0.0, (inner + outer) * 0.5, 0.465), (0.96, 0.19, 0.03), wood)
    box((0.0, outer - 0.005, 0.505), (0.96, 0.012, 0.06), wood)


def build_mast():
    yellow = mat("crane_yellow", CRANE_YELLOW, roughness=0.45)
    h = MAST_W * 0.5
    corners = [(-h, -h), (h, -h), (h, h), (-h, h)]
    for x, y in corners:
        beam((x, y, 0.0), (x, y, 1.0), MAST_POST, yellow)
    for i in range(4):
        x0, y0 = corners[i]
        x1, y1 = corners[(i + 1) % 4]
        beam((x0, y0, 0.03), (x1, y1, 0.03), MAST_POST * 0.6, yellow)
        beam((x0, y0, 0.03), (x1, y1, 0.97), MAST_POST * 0.55, yellow)


def build_top():
    yellow = mat("crane_yellow", CRANE_YELLOW, roughness=0.45)
    dark = mat("crane_dark", DARK, roughness=0.6)
    concrete = mat("crane_concrete", CONCRETE, roughness=0.9)
    glass = mat("crane_glass", GLASS, roughness=0.15)
    white = mat("crane_white", WHITE, roughness=0.5)
    # Поворотный круг и площадка.
    box((0.0, 0.0, 0.06), (0.44, 0.44, 0.12), dark)
    # Кабина крановщика сбоку от мачты, окнами вперёд по стреле.
    box((0.16, -0.31, 0.24), (0.3, 0.24, 0.26), white)
    box((0.315, -0.31, 0.27), (0.02, 0.2, 0.16), glass)
    # Оголовок — пирамида над мачтой.
    h = 0.15
    for x, y in ((-h, -h), (h, -h), (h, h), (-h, h)):
        beam((x, y, 0.12), (0.0, 0.0, 1.0), 0.035, yellow)
    # Противовесная консоль назад по −X, блоки противовеса на конце.
    for y in (-0.1, 0.1):
        beam((0.0, y, 0.14), (-1.45, y, 0.14), 0.04, yellow)
        beam((0.0, y, 0.3), (-1.2, y, 0.22), 0.03, yellow)
    for k in range(6):
        x0 = -0.2 * k
        beam((x0, -0.1, 0.14), (x0 - 0.2, 0.1, 0.14), 0.022, yellow)
    box((-0.75, 0.0, 0.17), (0.9, 0.24, 0.02), dark)
    for i in range(3):
        box((-1.18 - i * 0.1, 0.0, 0.0), (0.09, 0.36, 0.44), concrete)
    # Тяга от оголовка к консоли.
    beam((0.0, 0.0, 1.0), (-1.35, 0.0, 0.3), 0.02, dark)


def build_jib():
    yellow = mat("crane_yellow", CRANE_YELLOW, roughness=0.45)
    dark = mat("crane_dark", DARK, roughness=0.6)
    # Треугольная ферма вдоль +X: два нижних пояса и верхний; Godot растягивает её по X.
    x0, x1 = 0.16, 1.0
    for y in (-0.1, 0.1):
        beam((x0, y, 0.12), (x1, y, 0.12), 0.035, yellow)
    beam((x0, 0.0, 0.34), (x1, 0.0, 0.2), 0.03, yellow)
    steps = 8
    for i in range(steps):
        a = x0 + (x1 - x0) * i / steps
        b = x0 + (x1 - x0) * (i + 1) / steps
        for y in (-0.1, 0.1):
            beam((a, y, 0.12), (b, 0.0, 0.34 - 0.14 * (b - x0) / (x1 - x0)), 0.018, yellow)
        beam((a, -0.1, 0.12), (a, 0.1, 0.12), 0.018, yellow)
    box((x1 - 0.01, 0.0, 0.16), (0.03, 0.22, 0.1), dark)
    # Тяга от оголовка (0, 0, 1) к стреле.
    beam((0.0, 0.0, 1.0), (0.7, 0.0, 0.25), 0.018, dark)


def build_cable():
    dark = mat("crane_dark", DARK, roughness=0.6)
    beam((0.0, 0.0, 0.0), (0.0, 0.0, -1.0), 0.016, dark)


def build_hook():
    yellow = mat("crane_yellow", CRANE_YELLOW, roughness=0.45)
    dark = mat("crane_dark", DARK, roughness=0.6)
    load = mat("crane_load", LOAD, roughness=0.8)
    box((0.0, 0.0, -0.07), (0.1, 0.07, 0.14), yellow)
    box((0.0, 0.0, -0.165), (0.03, 0.03, 0.05), dark)
    for x in (-0.24, 0.24):
        beam((0.0, 0.0, -0.19), (x, 0.0, -0.42), 0.012, dark)
    for y, z in ((-0.05, -0.47), (0.05, -0.47), (0.0, -0.55)):
        box((0.0, y, z), (0.62, 0.09, 0.08), load)


PARTS = (
    ("scaffold", build_scaffold),
    ("crane_mast", build_mast),
    ("crane_top", build_top),
    ("crane_jib", build_jib),
    ("crane_cable", build_cable),
    ("crane_hook", build_hook),
)


def export(name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True)
    tris = sum(len(o.data.polygons) * 2 for o in bpy.data.objects if o.type == "MESH")
    print("PART", path, "tris", tris)


def placed(build_fn, location=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0), rot_z=0.0):
    """Строит деталь и ставит её на место (для превью)."""
    before = set(bpy.data.objects)
    build_fn()
    holder = bpy.data.objects.new("holder", None)
    bpy.context.collection.objects.link(holder)
    for obj in bpy.data.objects:
        if obj not in before and obj is not holder:
            obj.parent = holder
    holder.location = location
    holder.scale = scale
    holder.rotation_euler = (0.0, 0.0, rot_z)
    return holder


def render_preview():
    clear_scene()
    ground = mat("ground", (0.55, 0.44, 0.32), roughness=1.0)
    box((0.0, 0.0, -0.02), (7.0, 5.0, 0.04), ground)
    # Кран: 5 секций мачты, стрела 3.2 м, крюк с грузом.
    height = 5.0
    for i in range(5):
        placed(build_mast, (1.2, 1.2, i * 1.0))
    yaw = math.radians(205)
    placed(build_top, (1.2, 1.2, height), rot_z=yaw)
    placed(build_jib, (1.2, 1.2, height), scale=(3.2, 1.0, 1.0), rot_z=yaw)
    reach = 2.0
    hx, hy = 1.2 + reach * math.cos(yaw), 1.2 + reach * math.sin(yaw)
    placed(build_cable, (hx, hy, height + 0.12), scale=(1.0, 1.0, 2.6))
    placed(build_hook, (hx, hy, height + 0.12 - 2.6))
    # Леса: стена 3 модуля на 4 яруса вдоль фасада, наружу на −Y.
    for level in range(4):
        for i in range(3):
            placed(build_scaffold, (-1.0 + i * 1.0, -0.6, level * 0.5))
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except Exception:
            pass
    scene.render.resolution_x = 760
    scene.render.resolution_y = 620
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass
    world = bpy.data.worlds.new("bg")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb_to_linear((0.62, 0.72, 0.82)), 1.0)
    scene.world = world
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 9.0
    bpy.context.collection.objects.link(cam)
    target = Vector((0.0, 0.0, 2.6))
    cam.location = target + Vector((6.0, -9.0, 5.5))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", type="SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(45), math.radians(-15), math.radians(-35))
    bpy.context.collection.objects.link(sun)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", PREVIEW)


def main():
    for name, build_fn in PARTS:
        clear_scene()
        build_fn()
        export(name)
    render_preview()


main()
