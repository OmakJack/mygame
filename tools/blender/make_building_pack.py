"""Генератор полного пака 3D-зданий для CityBuilder (48 моделей: жилые дома, офисы, заводы).

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup ^
      --python tools/blender/make_building_pack.py

Результат:
  - assets/models/blender/pack/residential/*.glb  (18 жилых зданий: 1×1 .. 7×1, 2×2, 3×2)
  - assets/models/blender/pack/offices/*.glb      (15 офисных зданий: 1×1 .. 7×1, 2×2, 3×2)
  - assets/models/blender/pack/industrial/*.glb   (15 заводов и комбинатов: 1×1 .. 7×1, 2×2, 3×2)
  - assets/models/blender/pack/manifest.json      (метаданные для быстрого подключения в Godot)
  - assets/models/blender/pack/previews/*.png     (контакт-листы с клеточной сеткой и диорама)
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arch_kit import CELL, PACK_DIR, clear_scene  # noqa: E402
from pack_industrial import INDUSTRIAL_SPECS  # noqa: E402
from pack_offices import OFFICE_SPECS  # noqa: E402
from pack_residential import RESIDENTIAL_SPECS  # noqa: E402

PREVIEW_DIR = os.path.join(PACK_DIR, "previews")


def _simple_mat(name, rgb, roughness=0.72, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _add_flat_box(center, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def _import_pack_glb(glb_path, location=(0.0, 0.0, 0.0), rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    imported = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in imported if o.parent not in imported]
    holder = bpy.data.objects.new("holder", None)
    bpy.context.collection.objects.link(holder)
    for r in roots:
        r.parent = holder
    holder.location = location
    holder.rotation_euler = (0.0, 0.0, rot_z)
    for o in imported:
        if o.type == "MESH" and o.data:
            for mat in o.data.materials:
                if mat and mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type == "TEX_IMAGE":
                            node.interpolation = "Linear"
    return holder


def _setup_studio_render(res_x=1920, res_y=1200, padding=1.10, cam_vec=(0.82, -1.0, 0.72), bg_rgb=(0.84, 0.89, 0.94)):
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = eng
            break
        except Exception:
            pass
    scene.render.film_transparent = False
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"

    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass
    scene.view_settings.exposure = 0.08

    if scene.world is None:
        scene.world = bpy.data.worlds.new("StudioWorld")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (*bg_rgb, 1.0)
        bg.inputs["Strength"].default_value = 0.85

    depsgraph = bpy.context.evaluated_depsgraph_get()
    pts = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.name.startswith("bg_"):
            continue
        ev = obj.evaluated_get(depsgraph)
        m = ev.to_mesh()
        for v in m.vertices:
            pts.append(obj.matrix_world @ v.co)
        ev.to_mesh_clear()

    center = sum(pts, Vector((0, 0, 0))) / max(1, len(pts))
    cam_dir = Vector(cam_vec).normalized()
    forward = -cam_dir
    right = forward.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(forward).normalized()

    min_u = min_v = 1e9
    max_u = max_v = -1e9
    for p in pts:
        rel = p - center
        u = rel.dot(right)
        v = rel.dot(up)
        min_u, max_u = min(min_u, u), max(max_u, u)
        min_v, max_v = min(min_v, v), max(max_v, v)

    target = center + right * ((min_u + max_u) * 0.5) + up * ((min_v + max_v) * 0.5)
    cam_pos = target + cam_dir * 65.0

    aspect = res_x / res_y
    span_u = (max_u - min_u) * padding
    span_v = (max_v - min_v) * padding
    ortho_scale = max(span_u, span_v * aspect, 1.0)

    cam_data = bpy.data.cameras.new("SheetCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam_data.clip_end = 300.0
    cam_obj = bpy.data.objects.new("SheetCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = cam_pos
    cam_obj.rotation_euler = (target - cam_pos).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    # Солнечный ключ, небесный заполняющий и тёплый рефлекс снизу
    lights = [
        ("SunKey", 3.6, (1.0, 0.96, 0.88), (48, -22, 32), True),
        ("SkyFill", 1.8, (0.76, 0.87, 1.0), (62, 42, -55), False),
        ("WarmRim", 1.0, (0.98, 0.91, 0.80), (118, 0, 35), False),
    ]
    for lname, energy, col, rot_deg, shadows in lights:
        ld = bpy.data.lights.new(lname, type="SUN")
        ld.energy = energy
        ld.color = col
        ld.use_shadow = shadows
        lo = bpy.data.objects.new(lname, ld)
        bpy.context.collection.objects.link(lo)
        lo.rotation_euler = tuple(math.radians(a) for a in rot_deg)


def _add_lot_checkerboard(cx, cy, cells_w, cells_d, mat_a, mat_b, mat_rim):
    """Рисует под зданием аккуратную подставку с шахматной разметкой клеток 2×2 м."""
    tot_w, tot_d = cells_w * CELL, cells_d * CELL
    _add_flat_box((cx, cy, -0.09), (tot_w + 0.16, tot_d + 0.16, 0.14), mat_rim)
    for ix in range(cells_w):
        for iy in range(cells_d):
            tx = cx - tot_w * 0.5 + (ix + 0.5) * CELL
            ty = cy - tot_d * 0.5 + (iy + 0.5) * CELL
            m = mat_a if (ix + iy) % 2 == 0 else mat_b
            _add_flat_box((tx, ty, -0.015), (CELL - 0.04, CELL - 0.04, 0.03), m)


def render_category_sheet(filename, entries, cols=4):
    """Рендерит контакт-лист всех моделей категории с шахматными клеточными подиумами."""
    clear_scene()
    grass_a = _simple_mat("grass_a", (0.44, 0.69, 0.36), roughness=0.85)
    grass_b = _simple_mat("grass_b", (0.37, 0.61, 0.30), roughness=0.85)
    rim_mat = _simple_mat("rim", (0.28, 0.32, 0.37), roughness=0.75)

    # Раскладываем по строкам с учётом реальной ширины участков
    rows = []
    cur = []
    cur_span = 0.0
    max_row_span = 26.0
    for item in entries:
        w_m = item["cells"][0] * CELL + 2.2
        if cur and cur_span + w_m > max_row_span and len(cur) >= 2:
            rows.append(cur)
            cur = [item]
            cur_span = w_m
        else:
            cur.append(item)
            cur_span += w_m
    if cur:
        rows.append(cur)

    y_cursor = 0.0
    for row in rows:
        row_depth = max(it["cells"][1] * CELL for it in row)
        total_w = sum(it["cells"][0] * CELL for it in row) + 2.4 * max(0, len(row) - 1)
        x_cursor = -total_w * 0.5
        for it in row:
            cw, cd = it["cells"]
            w_m = cw * CELL
            cx = x_cursor + w_m * 0.5
            cy = y_cursor
            _add_lot_checkerboard(cx, cy, cw, cd, grass_a, grass_b, rim_mat)
            glb_full = os.path.join(PACK_DIR, it["category"], f"{it['id']}.glb")
            _import_pack_glb(glb_full, location=(cx, cy, 0.0))
            x_cursor += w_m + 2.4
        y_cursor += row_depth + 4.4

    _setup_studio_render(res_x=2000, res_y=1300, padding=1.08, cam_vec=(0.76, -1.0, 0.74))
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out_path = os.path.join(PREVIEW_DIR, filename)
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("SHEET", out_path)


def render_showcase_diorama(filename):
    """Рендерит живую городскую диораму: проспект, жилой квартал, деловой даунтаун и промзону."""
    clear_scene()
    ground = _simple_mat("ground", (0.43, 0.67, 0.35), roughness=0.88)
    road = _simple_mat("road", (0.30, 0.33, 0.38), roughness=0.80)
    sidewalk = _simple_mat("walk", (0.76, 0.75, 0.72), roughness=0.78)
    stripe = _simple_mat("stripe", (0.94, 0.88, 0.66), roughness=0.6)

    # Основание квартала и три параллельные улицы (передняя, центральный проспект, верхняя)
    _add_flat_box((0, 1.5, -0.08), (40.0, 26.0, 0.16), ground)
    for y_rd, w_walk, w_road in ((-7.2, 2.2, 1.60), (-2.2, 2.5, 1.85), (5.8, 2.3, 1.70)):
        _add_flat_box((0, y_rd, 0.015), (40.0, w_walk, 0.03), sidewalk)
        _add_flat_box((0, y_rd, 0.025), (40.0, w_road, 0.03), road)
        for sx in range(-18, 19, 2):
            _add_flat_box((sx, y_rd, 0.042), (0.8, 0.08, 0.01), stripe)

    placements = [
        # Передний ряд (жилые дома, променад и мастерская, смотрят главным фасадом -Y на улицу Y=-7.2)
        ("residential", "res_dutch_row_2x1", (-14.5, -5.0, 0.0), 0.0),
        ("residential", "res_english_townhouses_3x1", (-8.8, -5.0, 0.0), 0.0),
        ("residential", "res_nordic_cottage_1x1", (-4.2, -5.0, 0.0), 0.0),
        ("residential", "res_brick_villa_1x1", (-2.0, -5.0, 0.0), 0.0),
        ("residential", "res_modern_cube_1x1", (0.2, -5.0, 0.0), 0.0),
        ("residential", "res_modern_promenade_5x1", (6.8, -5.0, 0.0), 0.0),
        ("industrial", "ind_sawtooth_mill_2x1", (14.4, -5.0, 0.0), 0.0),

        # Средний квартал (смотрит фасадом -Y на главный проспект Y=-2.2): деловой центр + жилой ансамбль + завод
        ("residential", "res_cloister_quarter_3x2", (-14.2, 1.8, 0.0), 0.0),
        ("residential", "res_stalin_block_4x1", (-6.6, 0.8, 0.0), 0.0),
        ("offices", "off_skybridge_gate_4x1", (1.8, 0.8, 0.0), 0.0),
        ("offices", "off_silicon_campus_3x2", (9.2, 1.8, 0.0), 0.0),
        ("industrial", "ind_thermo_plant_3x2", (15.6, 1.8, 0.0), 0.0),

        # Дальний высотный ряд (небоскрёбы даунтауна и крупная промышленность, смотрят на Y=5.8)
        ("residential", "res_boulevard_mansard_7x1", (-11.2, 8.6, 0.0), 0.0),
        ("offices", "off_citadel_tower_2x2", (-1.8, 9.6, 0.0), 0.0),
        ("offices", "off_financial_center_3x2", (3.6, 9.6, 0.0), 0.0),
        ("offices", "off_diagrid_needle_1x1", (8.0, 8.6, 0.0), 0.0),
        ("offices", "off_artdeco_spire_1x1", (10.2, 8.6, 0.0), 0.0),
        ("industrial", "ind_refinery_complex_3x2", (14.8, 9.6, 0.0), 0.0),
    ]
    for cat, mid, loc, rz in placements:
        _import_pack_glb(os.path.join(PACK_DIR, cat, f"{mid}.glb"), location=loc, rot_z=rz)

    _setup_studio_render(res_x=2000, res_y=1180, padding=1.02, cam_vec=(0.72, -1.0, 0.62), bg_rgb=(0.80, 0.88, 0.96))
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out_path = os.path.join(PREVIEW_DIR, filename)
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("SHOWCASE", out_path)


def main():
    manifest = {
        "pack_name": "CityBuilder Architectural Low-Poly Pack v1",
        "cell_size_m": CELL,
        "godot_conventions": {
            "palette_texture": "res://assets/models/kenney/suburban/Textures/colormap.png",
            "district_recolor_compatible": True,
            "front_in_blender": "-Y",
            "front_in_godot_with_turns_2": "-Z",
            "recommended_model_scale": 1.0,
            "recommended_model_turns": 2,
        },
        "models": [],
    }

    groups = [
        ("residential", RESIDENTIAL_SPECS),
        ("offices", OFFICE_SPECS),
        ("industrial", INDUSTRIAL_SPECS),
    ]

    by_category = {"residential": [], "offices": [], "industrial": []}

    for category, specs in groups:
        for model_id, display_name, zone, level, fn in specs:
            builder, cw, cd = fn()
            assert builder.name == model_id, f"Mismatch {builder.name} != {model_id}"
            meta = builder.export_pack_glb(category, cw, cd)
            meta["display_name"] = display_name
            meta["suggested_zone"] = zone
            meta["suggested_level"] = level
            manifest["models"].append(meta)
            by_category[category].append(meta)

    os.makedirs(PACK_DIR, exist_ok=True)
    manifest_path = os.path.join(PACK_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print("MANIFEST", manifest_path, "total_models=", len(manifest["models"]))

    render_category_sheet("pack_residential.png", by_category["residential"])
    render_category_sheet("pack_offices.png", by_category["offices"])
    render_category_sheet("pack_industrial.png", by_category["industrial"])
    render_showcase_diorama("pack_showcase.png")


if __name__ == "__main__":
    main()
