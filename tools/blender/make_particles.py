"""Главный скрипт генерации набора партиклов и визуальных эффектов (VFX Pack v1) в Blender 5.2.

Запуск (headless):
  & "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/make_particles.py

Генерирует:
  1) 20 составных 3D-эффектов (.glb) -> assets/models/blender/particles/<id>.glb
  2) 12 одиночных 3D-мешей частиц (.glb) -> assets/models/blender/particles/units/<id>.glb
  3) 8 2D-спрайтов частиц (256x256 RGBA .png) -> assets/models/blender/particles/sprites/<id>.png
  4) Манифест -> assets/models/blender/particles/manifest.json
  5) 3 рендера-превью -> assets/models/blender/particles/previews/:
     - particles_plumes_catalog.png (все 20 составных 3D-эффектов)
     - particles_units_catalog.png (все 12 одиночных 3D-мешей частиц)
     - particles_in_action_diorama.png (диорама города с дымом из труб заводов/пекарен, паром кофеен, фонтаном, листвой, искрами стройки и сносом)
"""

import json
import math
import os
import struct
import sys
import zlib
import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from pack_particles import (
    PARTICLE_PLUMES,
    PARTICLE_UNITS,
    clear_scene,
    srgb_to_linear,
)

ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
OUT_DIR = os.path.join(ROOT, "assets", "models", "blender", "particles")
UNITS_DIR = os.path.join(OUT_DIR, "units")
SPRITES_DIR = os.path.join(OUT_DIR, "sprites")
PREVIEWS_DIR = os.path.join(OUT_DIR, "previews")


def scene_stats_and_bounds():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    verts = 0
    tris = 0
    min_v = Vector((1e9, 1e9, 1e9))
    max_v = Vector((-1e9, -1e9, -1e9))
    has_mesh = False
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        has_mesh = True
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = eval_obj.to_mesh()
        mesh.calc_loop_triangles()
        verts += len(mesh.vertices)
        tris += len(mesh.loop_triangles)
        for v in mesh.vertices:
            wv = obj.matrix_world @ v.co
            min_v.x = min(min_v.x, wv.x)
            min_v.y = min(min_v.y, wv.y)
            min_v.z = min(min_v.z, wv.z)
            max_v.x = max(max_v.x, wv.x)
            max_v.y = max(max_v.y, wv.y)
            max_v.z = max(max_v.z, wv.z)
        eval_obj.to_mesh_clear()
    if not has_mesh:
        return 0, 0, [0, 0, 0], [0, 0, 0], [0, 0, 0]
    dims = [round(max_v.x - min_v.x, 3), round(max_v.y - min_v.y, 3), round(max_v.z - min_v.z, 3)]
    bmin = [round(min_v.x, 3), round(min_v.y, 3), round(min_v.z, 3)]
    bmax = [round(max_v.x, 3), round(max_v.y, 3), round(max_v.z, 3)]
    return verts, tris, dims, bmin, bmax


def export_glb(path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
    )


# ===========================================================================
# ПРОЦЕДУРНЫЕ 2D-СПРАЙТЫ ЧАСТИЦ (256x256 RGBA PNG)
# ===========================================================================

def _write_rgba_png(path: str, width: int, height: int, pixel_fn):
    """Записывает RGBA PNG без внешних зависимостей (через стандартные struct + zlib)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = bytearray()
    for iy in range(height):
        raw.append(0)  # filter type 0 (None)
        v = (iy + 0.5) / height * 2.0 - 1.0
        for ix in range(width):
            u = (ix + 0.5) / width * 2.0 - 1.0
            r, g, b, a = pixel_fn(u, -v)
            raw.append(max(0, min(255, int(r * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(g * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(b * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(a * 255.0 + 0.5))))

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), level=9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def _smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def generate_all_sprites():
    size = 256
    sprites_meta = []

    # 1. Мягкий клуб дыма/пара с объёмным освещением сверху
    def px_smoke_soft(x, y):
        lobes = [
            (0.0, 0.04, 0.62),
            (-0.26, -0.06, 0.46),
            (0.26, -0.04, 0.45),
            (-0.14, 0.24, 0.42),
            (0.16, 0.22, 0.40),
        ]
        d_max = 0.0
        for cx, cy, rad in lobes:
            dist = math.hypot(x - cx, y - cy) / rad
            val = max(0.0, 1.0 - dist * dist)
            d_max = max(d_max, val)
        alpha = _smoothstep(0.05, 0.72, d_max)
        shade = 0.74 + 0.26 * max(-1.0, min(1.0, (y * 0.7 - x * 0.25 + 0.35)))
        return (shade, shade, min(1.0, shade * 1.02), alpha)

    # 2. Стилизованный чёткий тун-клуб дыма
    def px_smoke_toon(x, y):
        lobes = [(0.0, -0.04, 0.54), (-0.28, -0.10, 0.38), (0.28, -0.08, 0.38), (0.0, 0.24, 0.40)]
        min_ratio = 10.0
        for cx, cy, rad in lobes:
            min_ratio = min(min_ratio, math.hypot(x - cx, y - cy) / rad)
        alpha = 1.0 - _smoothstep(0.88, 0.98, min_ratio)
        rim = _smoothstep(0.55, 0.85, y + 0.35)
        c = 0.78 + 0.20 * rim
        return (c, c, min(1.0, c * 1.03), alpha)

    # 3. Язык пламени
    def px_flame(x, y):
        # Сужается кверху и слегка изгибается
        yn = (y + 0.75) / 1.55
        if yn < 0.0 or yn > 1.05:
            return (0, 0, 0, 0)
        w = 0.52 * math.sin(max(0.0, min(1.0, 1.0 - yn * 0.85)) * math.pi * 0.72)
        curve = 0.08 * math.sin(yn * 4.5)
        dx = abs(x - curve) / max(0.02, w)
        alpha = 1.0 - _smoothstep(0.45, 1.0, dx)
        alpha *= _smoothstep(0.0, 0.12, yn) * (1.0 - _smoothstep(0.82, 1.02, yn))
        core = 1.0 - _smoothstep(0.0, 0.65, dx + yn * 0.35)
        r = 1.0
        g = min(1.0, 0.28 + 0.68 * (1.0 - yn * 0.65) + core * 0.35)
        b = min(1.0, core * 0.75)
        return (r, g, b, alpha)

    # 4. Четырёхлучевая яркая искра / звезда
    def px_spark(x, y):
        r = math.hypot(x, y)
        star = max(0.0, 1.0 - (abs(x) * 3.2 + abs(y) * 0.55)) + max(0.0, 1.0 - (abs(y) * 3.2 + abs(x) * 0.55))
        diag = max(0.0, 1.0 - (abs(x - y) * 3.8 + abs(x + y) * 0.75)) * 0.55
        glow = max(0.0, 1.0 - r * 1.35) ** 2.2
        a = min(1.0, max(star, diag) + glow * 0.85)
        return (1.0, min(1.0, 0.76 + glow * 0.24), min(1.0, 0.25 + glow * 0.75), _smoothstep(0.04, 0.65, a))

    # 5. Капля воды
    def px_drop(x, y):
        yn = (y + 0.75) / 1.55
        if yn < 0.0 or yn > 1.0:
            return (0, 0, 0, 0)
        w = 0.46 * ((1.0 - yn) ** 0.55) * (yn ** 0.28) * 1.65
        d = abs(x) / max(0.02, w)
        alpha = (1.0 - _smoothstep(0.78, 0.98, d)) * _smoothstep(0.0, 0.08, yn) * (1.0 - _smoothstep(0.92, 1.0, yn))
        hl = max(0.0, 1.0 - math.hypot(x + 0.12, y + 0.18) * 3.5)
        r = min(1.0, 0.32 + hl * 0.68)
        g = min(1.0, 0.76 + hl * 0.24)
        b = 0.98
        return (r, g, b, alpha)

    # 6. Концентрическое кольцо волны на воде
    def px_ripple(x, y):
        r = math.hypot(x, y)
        ring1 = max(0.0, 1.0 - abs(r - 0.74) / 0.09)
        ring2 = max(0.0, 1.0 - abs(r - 0.42) / 0.07) * 0.75
        a = _smoothstep(0.05, 0.85, max(ring1, ring2))
        return (0.82, 0.96, 1.0, a)

    # 7. Древесный листок
    def px_leaf(x, y):
        yn = (y + 0.75) / 1.50
        if yn < 0.0 or yn > 1.0:
            return (0, 0, 0, 0)
        w = 0.48 * math.sin(yn * math.pi)
        d = abs(x) / max(0.015, w)
        alpha = (1.0 - _smoothstep(0.84, 0.98, d)) * _smoothstep(0.0, 0.05, yn) * (1.0 - _smoothstep(0.94, 1.0, yn))
        vein = max(0.0, 1.0 - abs(x) / 0.03) * 0.22
        r = min(1.0, 0.36 + yn * 0.18 + vein)
        g = min(1.0, 0.72 + yn * 0.14 + vein)
        b = min(1.0, 0.24 + vein * 0.5)
        return (r, g, b, alpha)

    # 8. Шестилучевая снежинка
    def px_snow(x, y):
        r = math.hypot(x, y)
        if r > 0.92:
            return (0, 0, 0, 0)
        ang = math.atan2(y, x)
        # 6 осей симметрии
        sector = abs(((ang + math.pi) % (math.pi / 3.0)) - (math.pi / 6.0))
        u = r * math.cos(sector)
        v = r * math.sin(sector)
        arm = max(0.0, 1.0 - v / 0.055) * (1.0 - _smoothstep(0.75, 0.88, u))
        branch1 = max(0.0, 1.0 - abs(v - (u - 0.32) * 0.75) / 0.045) if 0.30 < u < 0.58 else 0.0
        branch2 = max(0.0, 1.0 - abs(v - (u - 0.52) * 0.75) / 0.040) if 0.50 < u < 0.74 else 0.0
        core = max(0.0, 1.0 - r / 0.22)
        val = max(arm, branch1, branch2, core)
        return (0.94, 0.98, 1.0, _smoothstep(0.1, 0.75, val))

    specs = [
        ("sprite_smoke_puff", "Мягкий клуб дыма и пара", px_smoke_soft),
        ("sprite_smoke_toon", "Стилизованный тун-клуб дыма", px_smoke_toon),
        ("sprite_flame_glow", "Язык пламени и жара", px_flame),
        ("sprite_spark_star", "Яркая четырёхлучевая искра / блик", px_spark),
        ("sprite_water_drop", "Капля воды с бликом", px_drop),
        ("sprite_ripple_ring", "Концентрические круги на воде", px_ripple),
        ("sprite_leaf", "Древесный листок с прожилкой", px_leaf),
        ("sprite_snowflake", "Шестилучевая снежинка", px_snow),
    ]
    for sid, title, fn in specs:
        rel = f"assets/models/blender/particles/sprites/{sid}.png"
        full = os.path.join(SPRITES_DIR, f"{sid}.png")
        _write_rgba_png(full, size, size, fn)
        print(f"SPRITE {sid} -> {full}")
        sprites_meta.append({
            "id": sid,
            "display_name": title,
            "resolution": [size, size],
            "file": rel,
            "godot_res_path": f"res://{rel}",
        })
    return sprites_meta


# ===========================================================================
# КАРТА ТОЧЕК ЭМИССИИ (EMITTERS) ДЛЯ ЗДАНИЙ ИГРЫ
# ===========================================================================

def build_emitter_recommendations():
    """Готовая таблица точек привязки партиклов к зданиям в координатах клетки Godot (после turns=2, фасад на -Z).
    В Godot: +Y — вверх, -Z — фасад к улице, (x_blender, y_blender, z_blender) при turns=2 -> (-x_b, z_b, y_b).
    """
    return {
        "auto_detection_rule": (
            "Для любого здания с трубой (INDUSTRIAL, power_plant, пекарни, котельные) устье трубы — "
            "это самая высокая вершина меша (v.y >= mesh.get_aabb().end.y - 0.06). "
            "Среднее (v.x, box.end.y, v.z) таких вершин даёт точный центр среза трубы без ручной разметки!"
        ),
        "zone_defaults": {
            "INDUSTRIAL": {
                "primary_effect": "res://assets/models/blender/particles/fx_smoke_factory_heavy.glb",
                "secondary_effect": "res://assets/models/blender/particles/fx_steam_cooling_tower.glb",
                "flare_effect": "res://assets/models/blender/particles/fx_fire_refinery_flare.glb",
            },
            "RESIDENTIAL": {
                "chimney_effect": "res://assets/models/blender/particles/fx_smoke_chimney_light.glb",
            },
            "COMMERCIAL": {
                "bakery_chimney_effect": "res://assets/models/blender/particles/fx_smoke_chimney_light.glb",
                "cafe_rooftop_effect": "res://assets/models/blender/particles/fx_cafe_aroma_swirl.glb",
                "hvac_vent_effect": "res://assets/models/blender/particles/fx_steam_vent_puff.glb",
            },
            "PARKS": {
                "plaza_fountain_effect": "res://assets/models/blender/particles/fx_fountain_park_jets.glb",
                "trees_leaves_effect": "res://assets/models/blender/particles/fx_nature_falling_leaves.glb",
                "sky_birds_effect": "res://assets/models/blender/particles/fx_nature_flock_birds.glb",
            },
            "CONSTRUCTION_AND_BULLDOZE": {
                "welding_sparks_effect": "res://assets/models/blender/particles/fx_sparks_welding_burst.glb",
                "construction_dust_effect": "res://assets/models/blender/particles/fx_dust_construction_site.glb",
                "bulldoze_demolition_effect": "res://assets/models/blender/particles/fx_dust_bulldoze_burst.glb",
                "levelup_celebration_effect": "res://assets/models/blender/particles/fx_celebrate_levelup_confetti.glb",
            },
        },
        "explicit_building_emitters_godot_xyz": {
            "ind_brick_workshop_1x1": [{"pos": [-0.58, 1.85, 0.48], "effect": "fx_smoke_factory_heavy"}],
            "ind_boiler_house_1x1": [
                {"pos": [-0.46, 2.58, 0.36], "effect": "fx_smoke_factory_heavy"},
                {"pos": [0.24, 1.52, 0.12], "effect": "fx_steam_vent_puff"},
            ],
            "ind_sawtooth_mill_2x1": [{"pos": [-1.50, 2.23, 0.36], "effect": "fx_smoke_factory_heavy"}],
            "ind_red_foundry_3x1": [
                {"pos": [-1.94, 2.88, 0.38], "effect": "fx_smoke_factory_heavy"},
                {"pos": [-2.48, 2.58, 0.38], "effect": "fx_smoke_factory_heavy"},
            ],
            "ind_heavy_works_7x1": [
                {"pos": [6.18, 3.28, 0.42], "effect": "fx_smoke_factory_heavy"},
                {"pos": [-6.28, 2.98, 0.42], "effect": "fx_smoke_factory_heavy"},
            ],
            "ind_thermo_plant_3x2": [
                {"pos": [-2.24, 3.48, 1.18], "effect": "fx_smoke_factory_heavy"},
                {"pos": [1.10, 2.45, 0.45], "effect": "fx_steam_cooling_tower"},
            ],
            "ind_refinery_complex_3x2": [
                {"pos": [0.96, 3.58, 0.78], "effect": "fx_fire_refinery_flare"},
                {"pos": [-1.85, 2.85, 0.62], "effect": "fx_smoke_factory_heavy"},
            ],
            "com_corner_bakery_1x1": [{"pos": [-0.42, 1.88, 0.38], "effect": "fx_smoke_chimney_light"}],
            "com_street_cafe_1x1": [{"pos": [0.22, 2.06, -0.18], "effect": "fx_cafe_aroma_swirl"}],
            "com_bistro_terrace_2x1": [{"pos": [-0.15, 2.29, 0.36], "effect": "fx_smoke_chimney_light"}],
            "com_strip_shops_3x1": [{"pos": [0.0, 2.28, -0.12], "effect": "fx_cafe_aroma_swirl"}],
            "com_market_promenade_5x1": [{"pos": [0.0, 2.78, -0.10], "effect": "fx_cafe_aroma_swirl"}],
            "com_supermarket_plaza_3x2": [{"pos": [-2.12, 3.21, -1.06], "effect": "fx_cafe_aroma_swirl"}],
            "com_metropolis_mall_3x2": [{"pos": [1.85, 4.70, 0.92], "effect": "fx_cafe_aroma_swirl"}],
        },
    }


# ===========================================================================
# РЕНДЕРЫ ПРЕВЬЮ (КАТАЛОГ ЭФФЕКТОВ, КАТАЛОГ ЮНИТОВ И ГОРОДСКАЯ ДИОРАМА)
# ===========================================================================

def _setup_render_scene(res_x, res_y, ortho_scale, cam_loc, cam_target, bg_srgb=(0.82, 0.89, 0.96)):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except Exception:
            pass
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass
    world = bpy.data.worlds.new("preview_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*srgb_to_linear(bg_srgb), 1.0)
    scene.world = world

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector(cam_target)
    cam.location = Vector(cam_loc)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    sun_d = bpy.data.lights.new("SunKey", type="SUN")
    sun_d.energy = 3.2
    sun = bpy.data.objects.new("SunKey", sun_d)
    sun.rotation_euler = (math.radians(48), math.radians(-18), math.radians(-32))
    bpy.context.collection.objects.link(sun)

    fill_d = bpy.data.lights.new("SunFill", type="SUN")
    fill_d.energy = 1.25
    fill = bpy.data.objects.new("SunFill", fill_d)
    fill.rotation_euler = (math.radians(55), math.radians(25), math.radians(140))
    bpy.context.collection.objects.link(fill)
    return scene


def _add_pedestal(x, y, w=1.75, d=1.75, top_srgb=(0.38, 0.43, 0.50), rim_srgb=(0.26, 0.30, 0.36)):
    for z, h, s, col, name in (
        (-0.04, 0.04, 1.0, top_srgb, "ped_top"),
        (-0.09, 0.06, 1.08, rim_srgb, "ped_rim"),
    ):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z))
        obj = bpy.context.active_object
        obj.scale = (w * s, d * s, h)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*srgb_to_linear(col), 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85
        obj.data.materials.append(mat)


def _get_palette_mat():
    mat = bpy.data.materials.get("city_palette_mat")
    if mat is not None:
        return mat
    cmap = os.path.join(ROOT, "assets", "models", "kenney", "suburban", "Textures", "colormap.png")
    mat = bpy.data.materials.new("city_palette_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.82
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.interpolation = "Closest"
    if os.path.exists(cmap):
        tex.image = bpy.data.images.load(cmap, check_existing=True)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def _import_glb_at(glb_path, location=(0.0, 0.0, 0.0), scale=1.0, rot_z=0.0, use_palette=False):
    if not os.path.exists(glb_path):
        print("WARN: missing glb:", glb_path)
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    added = [o for o in bpy.data.objects if o not in before]
    holder = bpy.data.objects.new("glb_holder", None)
    bpy.context.collection.objects.link(holder)
    pmat = _get_palette_mat() if use_palette else None
    for o in added:
        if use_palette and o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(pmat)
        if o.parent is None:
            o.parent = holder
    holder.location = Vector(location)
    holder.scale = (scale, scale, scale)
    holder.rotation_euler = (0.0, 0.0, rot_z)
    return holder


def render_plumes_catalog():
    """Рендерит все 20 составных 3D-эффектов в сетке 5x4 на контрастных подиумах."""
    clear_scene()
    cols = 5
    step_x = 2.95
    step_y = 2.85
    # Насыщенные цвета подиумов по категориям, чтобы и белые пары, и тёмный дым отлично читались
    cat_colors = {
        "smoke_steam": (0.34, 0.44, 0.56),
        "fire_sparks": (0.28, 0.28, 0.34),
        "dust_traffic": (0.36, 0.48, 0.38),
        "water": (0.26, 0.38, 0.52),
        "nature_weather": (0.34, 0.46, 0.36),
        "celebrate": (0.36, 0.32, 0.48),
    }
    for idx, (pid, cat, _, _, _, _, _) in enumerate(PARTICLE_PLUMES):
        col = idx % cols
        row = idx // cols
        x = (col - (cols - 1) * 0.5) * step_x
        y = (1.5 - row) * step_y
        top_c = cat_colors.get(cat, (0.38, 0.43, 0.50))
        _add_pedestal(x, y, w=1.95, d=1.95, top_srgb=top_c)
        # Маленькая труба-эмиттер под дымовыми эффектами для наглядности
        if pid in ("fx_smoke_chimney_light", "fx_smoke_factory_heavy", "fx_fire_refinery_flare"):
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.14, depth=0.36, location=(x, y, 0.16))
            cyl = bpy.context.active_object
            mat = bpy.data.materials.new("chimney_brick")
            mat.use_nodes = True
            mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb_to_linear((0.68, 0.34, 0.26)), 1.0)
            cyl.data.materials.append(mat)
            _import_glb_at(os.path.join(OUT_DIR, f"{pid}.glb"), (x, y, 0.34))
        elif pid == "fx_smoke_twin_stacks":
            for ox, oy in ((-0.28, -0.10), (0.28, 0.10)):
                bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.12, depth=0.36, location=(x + ox, y + oy, 0.16))
                cyl = bpy.context.active_object
                mat = bpy.data.materials.new("chimney_twin")
                mat.use_nodes = True
                mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb_to_linear((0.68, 0.34, 0.26)), 1.0)
                cyl.data.materials.append(mat)
            _import_glb_at(os.path.join(OUT_DIR, f"{pid}.glb"), (x, y, 0.34))
        elif pid == "fx_steam_cooling_tower":
            bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.38, radius2=0.26, depth=0.42, location=(x, y, 0.19))
            cone = bpy.context.active_object
            mat = bpy.data.materials.new("tower_conc")
            mat.use_nodes = True
            mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb_to_linear((0.72, 0.73, 0.75)), 1.0)
            cone.data.materials.append(mat)
            _import_glb_at(os.path.join(OUT_DIR, f"{pid}.glb"), (x, y, 0.40))
        else:
            _import_glb_at(os.path.join(OUT_DIR, f"{pid}.glb"), (x, y, 0.02))

    scene = _setup_render_scene(
        res_x=2200, res_y=1450, ortho_scale=16.8,
        cam_loc=(9.5, -13.5, 10.2), cam_target=(0.2, 0.1, 0.85),
        bg_srgb=(0.76, 0.85, 0.94),
    )
    out_png = os.path.join(PREVIEWS_DIR, "particles_plumes_catalog.png")
    os.makedirs(PREVIEWS_DIR, exist_ok=True)
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out_png)


def render_units_catalog():
    """Рендерит все 12 одиночных 3D-элементов частиц (units/*.glb) в сетке 4x3."""
    clear_scene()
    cols = 4
    step_x = 2.15
    step_y = 2.05
    for idx, (uid, _, _, _) in enumerate(PARTICLE_UNITS):
        col = idx % cols
        row = idx // cols
        x = (col - (cols - 1) * 0.5) * step_x
        y = (1.0 - row) * step_y
        _add_pedestal(x, y, w=1.40, d=1.40, top_srgb=(0.32, 0.40, 0.50))
        _import_glb_at(os.path.join(UNITS_DIR, f"{uid}.glb"), (x, y, 0.52), scale=1.15)

    scene = _setup_render_scene(
        res_x=1800, res_y=1150, ortho_scale=9.8,
        cam_loc=(6.0, -8.5, 6.2), cam_target=(0.0, 0.0, 0.45),
        bg_srgb=(0.78, 0.86, 0.95),
    )
    out_png = os.path.join(PREVIEWS_DIR, "particles_units_catalog.png")
    os.makedirs(PREVIEWS_DIR, exist_ok=True)
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out_png)


def render_diorama_in_action():
    """Рендерит живую сцену города с подключёнными к реальным зданиям эффектами дыма, пара, фонтана, листвы, стройки и пожара."""
    clear_scene()
    # Зелёное основание квартала и асфальтовая улица
    _add_pedestal(0.0, 0.0, w=19.5, d=10.5, top_srgb=(0.46, 0.68, 0.36), rim_srgb=(0.34, 0.48, 0.28))
    _add_pedestal(0.0, -0.2, w=19.2, d=1.7, top_srgb=(0.26, 0.28, 0.32), rim_srgb=(0.76, 0.76, 0.74))

    ind_dir = os.path.join(ROOT, "assets", "models", "blender", "pack", "industrial")
    com_dir = os.path.join(ROOT, "assets", "models", "blender", "commercial")
    people_dir = os.path.join(ROOT, "assets", "models", "blender", "people")

    # Задний ряд (y = +2.5): промзона с дымом из труб, паром градирни и газовым факелом + высотный молл с салютом Level-Up
    _import_glb_at(os.path.join(ind_dir, "ind_brick_workshop_1x1.glb"), (-7.2, 2.5, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_smoke_factory_heavy.glb"), (-7.2 + 0.58, 2.5 + 0.48, 1.85), scale=1.05)

    _import_glb_at(os.path.join(ind_dir, "ind_boiler_house_1x1.glb"), (-5.0, 2.5, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_smoke_factory_heavy.glb"), (-5.0 + 0.46, 2.5 + 0.36, 2.58), scale=1.10)
    _import_glb_at(os.path.join(OUT_DIR, "fx_steam_cooling_tower.glb"), (-5.0 - 0.24, 2.5 + 0.12, 1.48), scale=0.85)

    _import_glb_at(os.path.join(ind_dir, "ind_red_foundry_3x1.glb"), (-1.0, 2.5, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_smoke_twin_stacks.glb"), (-1.0 + 2.20, 2.5 + 0.38, 2.75), scale=1.15)
    _import_glb_at(os.path.join(OUT_DIR, "fx_fire_refinery_flare.glb"), (-1.0 - 1.65, 2.5 + 0.35, 2.15), scale=1.10)
    _import_glb_at(os.path.join(OUT_DIR, "fx_sparks_welding_burst.glb"), (-1.0 + 0.2, 2.5 - 0.55, 1.35), scale=1.20)

    # Справа сзади: горящее здание, которое тушат водяной струёй + триумфальный Level-Up над бутиком
    _import_glb_at(os.path.join(com_dir, "com_cinema_palace_2x1.glb"), (4.0, 2.5, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_fire_building_blaze.glb"), (3.7, 2.4, 2.55), scale=1.15)
    _import_glb_at(os.path.join(OUT_DIR, "fx_water_fire_hose.glb"), (4.2, 0.7, 0.65), scale=1.15, rot_z=math.pi)

    _import_glb_at(os.path.join(com_dir, "com_flagship_store_1x1.glb"), (7.2, 2.5, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_celebrate_levelup_confetti.glb"), (7.2, 2.5, 4.75), scale=1.25)

    # Передний ряд (y = -2.8): пекарня с печным дымком, кофейня с ароматом над 3D-чашкой, бистро, сквер с фонтаном/листвой/птицами и площадка сноса бульдозером
    _import_glb_at(os.path.join(com_dir, "com_corner_bakery_1x1.glb"), (-7.2, -2.8, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_smoke_chimney_light.glb"), (-7.2 + 0.42, -2.8 + 0.38, 1.92), scale=1.05)

    _import_glb_at(os.path.join(com_dir, "com_street_cafe_1x1.glb"), (-5.0, -2.8, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_cafe_aroma_swirl.glb"), (-5.0 - 0.22, -2.8 - 0.18, 2.02), scale=1.15)

    _import_glb_at(os.path.join(com_dir, "com_bistro_terrace_2x1.glb"), (-1.8, -2.8, 0.0), use_palette=True)
    _import_glb_at(os.path.join(OUT_DIR, "fx_smoke_chimney_light.glb"), (-1.8 + 0.15, -2.8 + 0.36, 2.25), scale=1.10)
    _import_glb_at(os.path.join(OUT_DIR, "fx_steam_vent_puff.glb"), (-1.8 - 0.85, -2.8 + 0.20, 1.65), scale=1.05)

    # Парковая площадь с фонтаном, кружащейся листвой и птицами в небе
    _add_pedestal(2.4, -2.8, w=3.6, d=2.2, top_srgb=(0.78, 0.76, 0.70), rim_srgb=(0.55, 0.54, 0.50))
    _import_glb_at(os.path.join(OUT_DIR, "fx_fountain_park_jets.glb"), (2.0, -2.8, 0.04), scale=1.25)
    _import_glb_at(os.path.join(OUT_DIR, "fx_nature_falling_leaves.glb"), (3.3, -2.8, 0.15), scale=1.15)
    _import_glb_at(os.path.join(OUT_DIR, "fx_nature_flock_birds.glb"), (2.4, -2.5, 2.10), scale=1.25)

    # Участок сноса бульдозером с клубами пыли и обломками + дождевая тучка
    _add_pedestal(6.8, -2.8, w=2.6, d=2.2, top_srgb=(0.56, 0.46, 0.34), rim_srgb=(0.44, 0.36, 0.28))
    _import_glb_at(os.path.join(OUT_DIR, "fx_dust_bulldoze_burst.glb"), (6.8, -2.8, 0.04), scale=1.35)
    _import_glb_at(os.path.join(OUT_DIR, "fx_weather_rain_cloud.glb"), (6.8, -2.8, 1.55), scale=1.15)

    # Велосипедисты и пешеходы на улице + выхлопной дымок
    _import_glb_at(os.path.join(people_dir, "cyclist_courier.glb"), (-3.2, -0.2, 0.02), scale=0.45, rot_z=-math.pi * 0.5)
    _import_glb_at(os.path.join(people_dir, "citizen_coffee_f.glb"), (-4.6, -1.3, 0.02), scale=0.42, rot_z=math.pi * 0.5)
    _import_glb_at(os.path.join(OUT_DIR, "fx_car_exhaust_puff.glb"), (-0.2, -0.2, 0.15), scale=1.25, rot_z=math.pi * 0.5)

    scene = _setup_render_scene(
        res_x=2200, res_y=1300, ortho_scale=20.8,
        cam_loc=(12.5, -16.5, 12.0), cam_target=(0.0, 0.2, 1.4),
        bg_srgb=(0.82, 0.89, 0.96),
    )
    out_png = os.path.join(PREVIEWS_DIR, "particles_in_action_diorama.png")
    os.makedirs(PREVIEWS_DIR, exist_ok=True)
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out_png)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(UNITS_DIR, exist_ok=True)
    os.makedirs(SPRITES_DIR, exist_ok=True)
    os.makedirs(PREVIEWS_DIR, exist_ok=True)

    plumes_meta = []
    for pid, cat, title, usage, rec_scale, anim_mode, build_fn in PARTICLE_PLUMES:
        build_fn()
        glb_path = os.path.join(OUT_DIR, f"{pid}.glb")
        export_glb(glb_path)
        verts, tris, dims, bmin, bmax = scene_stats_and_bounds()
        rel = f"assets/models/blender/particles/{pid}.glb"
        print(f"PLUME [{cat}] {pid} -> dims={dims}m verts={verts} tris={tris}")
        plumes_meta.append({
            "id": pid,
            "category": cat,
            "display_name": title,
            "target_usage": usage,
            "anim_mode": anim_mode,
            "recommended_scale": rec_scale,
            "file": rel,
            "godot_res_path": f"res://{rel}",
            "dimensions_m": dims,
            "aabb_min_m": bmin,
            "aabb_max_m": bmax,
            "vertices": verts,
            "triangles": tris,
        })

    units_meta = []
    for uid, title, desc, build_fn in PARTICLE_UNITS:
        build_fn()
        glb_path = os.path.join(UNITS_DIR, f"{uid}.glb")
        export_glb(glb_path)
        verts, tris, dims, bmin, bmax = scene_stats_and_bounds()
        rel = f"assets/models/blender/particles/units/{uid}.glb"
        print(f"UNIT {uid} -> dims={dims}m verts={verts} tris={tris}")
        units_meta.append({
            "id": uid,
            "display_name": title,
            "description": desc,
            "file": rel,
            "godot_res_path": f"res://{rel}",
            "dimensions_m": dims,
            "vertices": verts,
            "triangles": tris,
        })

    sprites_meta = generate_all_sprites()

    manifest = {
        "pack_name": "CityBuilder Low-Poly Particles & VFX Pack v1",
        "godot_conventions": {
            "origin": "(0, 0, 0) at emission point (chimney top, fountain nozzle, ground center)",
            "up_axis_in_godot": "+Y",
            "wind_default_in_godot": "+X",
            "shader_uv_encoding": {
                "UV.x": "Normalized lifecycle phase t in 0.0..1.0 from emitter to tip",
                "UV.y": "Per-element deterministic random seed in 0.0..1.0",
                "UV2.xy": "Radial/directional vector (dx, dz) of the element",
                "NORMAL": "Outward normal of each individual puff/droplet/crystal (use VERTEX += NORMAL * pulse to scale puffs in place)",
            },
        },
        "plumes": plumes_meta,
        "units": units_meta,
        "sprites": sprites_meta,
        "building_emitters": build_emitter_recommendations(),
    }
    manifest_path = os.path.join(OUT_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print("MANIFEST", manifest_path, "plumes:", len(plumes_meta), "units:", len(units_meta), "sprites:", len(sprites_meta))

    render_plumes_catalog()
    render_units_catalog()
    render_diorama_in_action()


if __name__ == "__main__":
    main()
