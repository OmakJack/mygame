"""Значки над зданиями (как в SimCity): «булавка» в белой окантовке, в ней белый круг с символом.
Красные: жёлтая молния (нет света), голубая капля (нет воды), перечёркнутая дорога (нет дороги —
скоро опустеет). Тёмная: заколоченные крест-накрест доски (здание брошено, Decay).
Модели для BadgeVisualizer в Godot: он ставит значок остриём на крышу и поворачивает к камере.

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_badges.py

Результат:
  - assets/models/blender/badges/badge_power.glb, badge_water.glb, badge_road.glb, badge_abandoned.glb —
    острие внизу в (0, 0, 0),
    высота 1 м, лицевая сторона на −Y Blender (в Godot — на +Z, к камере);
  - docs/collab/visual/badges_preview.png — превью всех значков.

Только некоторые значки: BADGES_ONLY="badge_road,badge_abandoned" (остальные .glb не трогаются).
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "models", "blender", "badges")
PREVIEW = os.path.join(ROOT, "docs", "collab", "visual", "badges_preview.png")

# Цвета в sRGB, как в интерфейсе.
PIN_RED = (0.86, 0.22, 0.19)
WHITE = (0.98, 0.97, 0.94)
BOLT_YELLOW = (1.0, 0.76, 0.08)
DROP_BLUE = (0.14, 0.58, 0.96)
PIN_DARK = (0.34, 0.31, 0.3)
ROAD_GREY = (0.3, 0.31, 0.35)
DASH_YELLOW = (1.0, 0.84, 0.22)
WOOD = (0.7, 0.47, 0.24)
WOOD_DARK = (0.55, 0.35, 0.17)

# Булавка: острие в нуле, круг радиуса PIN_R с центром на высоте PIN_CENTER (верх — 1 м).
PIN_R = 0.38
PIN_CENTER = 0.62
PIN_DEPTH = 0.16
BORDER = 0.045
DISC_R = 0.285


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def make_mat(name, srgb, roughness=0.42):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb_to_linear(srgb), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def teardrop(tip, dist, radius, up=True, steps=40):
    """Контур капли/булавки [(x, z)]: острие tip, круг радиуса radius на расстоянии dist от острия
    (выше острия при up=False — булавка, ниже при up=True — капля). Стороны касаются круга."""
    phi0 = math.acos(radius / dist)
    sign = -1.0 if up else 1.0
    points = [tip]
    for i in range(steps + 1):
        phi = phi0 + (2.0 * math.pi - 2.0 * phi0) * i / steps
        points.append((radius * math.sin(phi), tip[1] + sign * (dist - radius * math.cos(phi))))
    return points


def circle(center, radius, steps=40):
    return [(center[0] + radius * math.cos(2.0 * math.pi * i / steps),
             center[1] + radius * math.sin(2.0 * math.pi * i / steps)) for i in range(steps)]


def prism(name, outline, y_front, depth, mat, bevel=0.0):
    """Плоская фигура outline [(x, z)] толщиной depth: лицевая грань на y_front, вглубь по +Y."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    front = [bm.verts.new((x, y_front, z)) for x, z in outline]
    back = [bm.verts.new((x, y_front + depth, z)) for x, z in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    count = len(outline)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def bolt_outline():
    # Молния вокруг центра круга, высота 0.5 м.
    cx, cz, k = 0.0, PIN_CENTER, 1.18
    shape = [(0.07, 0.21), (-0.12, -0.02), (-0.01, -0.02), (-0.07, -0.21), (0.13, 0.05), (0.02, 0.05)]
    return [(cx + x * k, cz + z * k) for x, z in shape]


def drop_outline():
    # Капля острием вверх: острие над центром, круг — чуть ниже центра.
    return teardrop((0.0, PIN_CENTER + 0.22), 0.28, 0.16, up=True)


def rect(cx, cz, width, height, angle=0.0):
    """Прямоугольник [(x, z)] с центром (cx, cz), повёрнутый на angle радиан."""
    c, s = math.cos(angle), math.sin(angle)
    corners = [(-width / 2, -height / 2), (width / 2, -height / 2), (width / 2, height / 2), (-width / 2, height / 2)]
    return [(cx + x * c - z * s, cz + x * s + z * c) for x, z in corners]


def road_symbol():
    # Дорога уходит вдаль (трапеция), жёлтая разметка, красная черта поперёк — «нет дороги».
    cz = PIN_CENTER
    road = [(-0.15, cz - 0.21), (0.15, cz - 0.21), (0.075, cz + 0.21), (-0.075, cz + 0.21)]
    dashes = [rect(0.0, cz - 0.12, 0.035, 0.09), rect(0.0, cz + 0.03, 0.028, 0.07), rect(0.0, cz + 0.15, 0.022, 0.05)]
    slash = rect(0.0, cz, 0.06, 0.56, math.radians(45.0))
    return [([road], ROAD_GREY), (dashes, DASH_YELLOW), ([slash], PIN_RED)]


def planks_symbol():
    # Две доски крест-накрест, как на заколоченном окне.
    cz = PIN_CENTER
    return [([rect(0.0, cz, 0.44, 0.1, math.radians(38.0))], WOOD_DARK),
            ([rect(0.0, cz, 0.44, 0.1, math.radians(-38.0))], WOOD)]


def build_badge(symbol_outline, symbol_color, pin_color=PIN_RED):
    """symbol_outline — контур символа, или symbol_color=None и symbol_outline — слои [([контуры], цвет)]:
    каждый следующий слой чуть ближе к зрителю."""
    red = make_mat("badge_pin", pin_color)
    white = make_mat("badge_white", WHITE, roughness=0.5)
    # Белая окантовка — та же булавка, крупнее и чуть сзади: видна на любой крыше.
    prism("border", teardrop((0.0, -BORDER * 1.6), PIN_CENTER + BORDER * 1.6, PIN_R + BORDER, up=False),
          -PIN_DEPTH * 0.5 + 0.03, PIN_DEPTH - 0.02, white, bevel=0.015)
    prism("pin", teardrop((0.0, 0.0), PIN_CENTER, PIN_R, up=False), -PIN_DEPTH * 0.5, PIN_DEPTH, red, bevel=0.03)
    prism("disc", circle((0.0, PIN_CENTER), DISC_R), -PIN_DEPTH * 0.5 - 0.03, 0.04, white, bevel=0.012)
    layers = symbol_outline if symbol_color is None else [([symbol_outline], symbol_color)]
    for index, (outlines, color) in enumerate(layers):
        mat = make_mat("badge_symbol_%d" % index, color, roughness=0.32)
        for part, outline in enumerate(outlines):
            prism("symbol_%d_%d" % (index, part), outline, -PIN_DEPTH * 0.5 - 0.075 - 0.02 * index, 0.06, mat,
                  bevel=0.012 if index == 0 else 0.008)


def export(name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True)
    tris = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.data.objects:
        mesh = obj.evaluated_get(depsgraph).to_mesh()
        mesh.calc_loop_triangles()
        tris += len(mesh.loop_triangles)
        obj.evaluated_get(depsgraph).to_mesh_clear()
    print("BADGE", path, "tris", tris)


def render_preview():
    clear_scene()
    for (name, outline, color, pin), x in zip(badges(), (-1.95, -0.65, 0.65, 1.95)):
        before = set(bpy.data.objects)
        build_badge(outline, color, pin)
        for obj in bpy.data.objects:
            if obj not in before:
                obj.location.x += x
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except Exception:
            pass
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 420
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass
    world = bpy.data.worlds.new("bg")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb_to_linear((0.55, 0.62, 0.52)), 1.0)
    scene.world = world
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 5.0
    bpy.context.collection.objects.link(cam)
    target = Vector((0.0, 0.0, 0.5))
    cam.location = target + Vector((0.35, -3.0, 0.9))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", type="SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(-20), math.radians(-25))
    bpy.context.collection.objects.link(sun)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", PREVIEW)


def badges():
    """[имя, контур или слои, цвет символа (None — слои), цвет булавки]."""
    return [("badge_power", bolt_outline(), BOLT_YELLOW, PIN_RED),
            ("badge_water", drop_outline(), DROP_BLUE, PIN_RED),
            ("badge_road", road_symbol(), None, PIN_RED),
            ("badge_abandoned", planks_symbol(), None, PIN_DARK)]


def main():
    only = [name for name in os.environ.get("BADGES_ONLY", "").split(",") if name]
    for name, outline, color, pin in badges():
        if only and name not in only:
            continue
        clear_scene()
        build_badge(outline, color, pin)
        export(name)
    render_preview()


main()
