"""Сборка моделей пешеходов, велосипедистов и коммерческих зданий (магазины, кафешки, ТЦ) в Blender 5.2.

Запуск (без окна):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/make_people_and_commercial.py

Результат:
  - assets/models/blender/people/*.glb               (8 пешеходов + 4 велосипедиста)
  - assets/models/blender/people/manifest.json       (реестр фигурок и путей для PeopleVisualizer)
  - assets/models/blender/people/previews/*.png      (студийный лист всех 12 фигурок в двух ракурсах)
  - assets/models/blender/commercial/*.glb           (20 коммерческих зданий: 1×1..7×1, 2×2, 3×2)
  - assets/models/blender/commercial/manifest.json   (реестр в формате pack/manifest.json для generate_building_types.gd)
  - assets/models/blender/commercial/previews/*.png  (контакт-листы COMMERCIAL, COMMERCIAL_HIGH и живая улица)
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arch_kit import CELL, ROOT, clear_scene  # noqa: E402
from pack_commercial import COMMERCIAL_SPECS  # noqa: E402
from pack_people import PEOPLE_SPECS  # noqa: E402

PEOPLE_DIR = os.path.join(ROOT, "assets", "models", "blender", "people")
PEOPLE_PREVIEWS = os.path.join(PEOPLE_DIR, "previews")
COM_DIR = os.path.join(ROOT, "assets", "models", "blender", "commercial")
COM_PREVIEWS = os.path.join(COM_DIR, "previews")


def export_person_model(model_id: str, kind: str, display_name: str, legacy_alias: str | None, fn) -> dict:
    builder = fn()
    assert builder.name == model_id, f"Mismatch {builder.name} != {model_id}"
    xs = [v[0] for v in builder.verts]
    ys = [v[1] for v in builder.verts]
    zs = [v[2] for v in builder.verts]
    dims = (round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3))

    obj = builder.build_object()
    os.makedirs(PEOPLE_DIR, exist_ok=True)
    filepath = os.path.join(PEOPLE_DIR, f"{model_id}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
    )
    tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
    verts = len(obj.data.vertices)
    print(f"PERSON [{kind}] {model_id} -> dims={dims}m verts={verts} tris={tris}")
    return {
        "id": model_id,
        "kind": kind,
        "display_name": display_name,
        "legacy_replaces": legacy_alias,
        "file": f"assets/models/blender/people/{model_id}.glb",
        "godot_res_path": f"res://assets/models/blender/people/{model_id}.glb",
        "dimensions_m": list(dims),
        "scaled_height_in_game_m": round(dims[2] * 0.22, 3),
        "vertices": verts,
        "triangles": tris,
        "recommended_people_scale": 0.22,
        "recommended_turns": 2,
        "recolorable_via_instance_custom": True,
    }


def export_commercial_model(model_id: str, display_name: str, zone: str, level: int, fn) -> dict:
    builder, cw, cd = fn()
    assert builder.name == model_id, f"Mismatch {builder.name} != {model_id}"
    dims = builder.fit_to_lot(cw, cd, margin=0.22)
    obj = builder.build_object()
    os.makedirs(COM_DIR, exist_ok=True)
    filepath = os.path.join(COM_DIR, f"{model_id}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
    )
    tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
    verts = len(obj.data.vertices)
    print(f"COMMERCIAL [{zone} L{level}] {model_id} ({cw}x{cd}) -> dims={dims}m verts={verts} tris={tris}")
    return {
        "id": model_id,
        "category": "commercial",
        "display_name": display_name,
        "suggested_zone": zone,
        "suggested_level": level,
        "file": f"assets/models/blender/commercial/{model_id}.glb",
        "godot_kit_path": f"blender/commercial/{model_id}",
        "cells": [cw, cd],
        "area_cells": cw * cd,
        "dimensions_m": list(dims),
        "vertices": verts,
        "triangles": tris,
    }


# ---------------------------------------------------------------------------
# Студийный рендер превью-листов и городской диорамы (Blender EEVEE)
# ---------------------------------------------------------------------------

def _simple_mat(name, rgb, roughness=0.78):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    lin = tuple((c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in rgb)
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def _add_flat_box(center, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    return o


def _import_glb_at(glb_path: str, location=(0.0, 0.0, 0.0), rot_z: float = 0.0, scale: float = 1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    added = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in added if o.parent not in added]
    holder = bpy.data.objects.new("holder", None)
    bpy.context.collection.objects.link(holder)
    for r in roots:
        r.parent = holder
    holder.location = location
    holder.rotation_euler = (0.0, 0.0, rot_z)
    holder.scale = (scale, scale, scale)
    for o in added:
        if o.type == "MESH" and o.data:
            for mat in o.data.materials:
                if mat and mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type == "TEX_IMAGE":
                            node.interpolation = "Linear"
    return holder


def _setup_studio_render(res_x=2000, res_y=1280, padding=1.10, cam_vec=(0.74, -1.0, 0.68), bg_rgb=(0.85, 0.90, 0.95)):
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            scene.render.engine = eng
            break
        except Exception:
            continue

    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.film_transparent = False
    try:
        scene.eevee.taa_render_samples = 64
        scene.eevee.use_raytracing = True
    except Exception:
        pass
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "Medium High Contrast"
    except Exception:
        pass

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        lin = tuple((c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in bg_rgb)
        bg.inputs[0].default_value = (*lin, 1.0)
        bg.inputs[1].default_value = 0.95

    bpy.ops.object.light_add(type="SUN", location=(10, -12, 18))
    sun = bpy.context.active_object
    sun.data.energy = 3.6
    sun.data.color = (1.0, 0.97, 0.90)
    sun.data.angle = math.radians(4.0)
    sun.rotation_euler = (math.radians(48), math.radians(14), math.radians(34))

    bpy.ops.object.light_add(type="SUN", location=(-10, 8, 12))
    fill = bpy.context.active_object
    fill.data.energy = 1.15
    fill.data.color = (0.82, 0.90, 1.0)
    fill.rotation_euler = (math.radians(58), 0.0, math.radians(-142))
    try:
        fill.data.use_shadow = False
    except Exception:
        pass

    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    pts = []
    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(depsgraph)
        m = ev.to_mesh()
        for v in m.vertices:
            pts.append(obj.matrix_world @ v.co)
        ev.to_mesh_clear()

    center = sum(pts, Vector((0, 0, 0))) / max(1, len(pts))
    direction = Vector(cam_vec).normalized()
    bpy.ops.object.camera_add(location=center + direction * 75.0)
    cam = bpy.context.active_object
    cam.data.type = "ORTHO"
    cam.data.clip_start = 0.1
    cam.data.clip_end = 300.0
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    bpy.context.view_layer.update()

    inv = cam.matrix_world.inverted()
    aspect = res_x / res_y
    min_x = min_y = 1e9
    max_x = max_y = -1e9
    for p in pts:
        c_pt = inv @ p
        min_x, max_x = min(min_x, c_pt.x), max(max_x, c_pt.x)
        min_y, max_y = min(min_y, c_pt.y), max(max_y, c_pt.y)
    # Доворачиваем камеру точно в экранный центр ограничивающей рамки
    shift_cam = cam.matrix_world.to_3x3() @ Vector(((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, 0.0))
    cam.location += shift_cam
    span_x = max_x - min_x
    span_y = max_y - min_y
    cam.data.ortho_scale = max(span_x, span_y * aspect) * padding


def render_people_sheet(people_items: list[dict], filename: str):
    """Рендерит все 8 пешеходов и 4 велосипедиста на подиумах (спереди 3/4 + сбоку/сзади 3/4)."""
    clear_scene()
    pad_a = _simple_mat("pad_a", (0.76, 0.75, 0.72), roughness=0.82)
    pad_b = _simple_mat("pad_b", (0.34, 0.37, 0.42), roughness=0.80)
    rim_m = _simple_mat("rim_m", (0.52, 0.55, 0.60), roughness=0.75)

    walkers = [it for it in people_items if it["kind"] == "walker"]
    cyclists = [it for it in people_items if it["kind"] == "cyclist"]

    # Передний ряд: 8 пешеходов (по 2 экземпляра на подиуме — лицом 3/4 и со спины/бока 3/4, чтобы видны были рюкзаки и сумки)
    step_w = 1.65
    start_x = -step_w * (len(walkers) - 1) * 0.5
    for idx, it in enumerate(walkers):
        cx = start_x + idx * step_w
        cy = 0.0
        _add_flat_box((cx, cy, -0.045), (1.36, 1.16, 0.07), rim_m)
        _add_flat_box((cx, cy, -0.008), (1.24, 1.04, 0.016), pad_a)
        glb = os.path.join(ROOT, it["file"])
        _import_glb_at(glb, location=(cx - 0.26, cy - 0.08, 0.0), rot_z=math.radians(-18.0))
        _import_glb_at(glb, location=(cx + 0.28, cy + 0.12, 0.0), rot_z=math.radians(145.0))

    # Задний ряд: 4 велосипедиста (в профиль-3/4 и со стороны багажника/короба)
    step_c = 3.15
    start_cx = -step_c * (len(cyclists) - 1) * 0.5
    for idx, it in enumerate(cyclists):
        cx = start_cx + idx * step_c
        cy = 3.65
        _add_flat_box((cx, cy, -0.045), (2.46, 1.56, 0.07), rim_m)
        _add_flat_box((cx, cy, -0.008), (2.32, 1.42, 0.016), pad_b)
        glb = os.path.join(ROOT, it["file"])
        _import_glb_at(glb, location=(cx - 0.48, cy - 0.10, 0.0), rot_z=math.radians(-28.0))
        _import_glb_at(glb, location=(cx + 0.52, cy + 0.14, 0.0), rot_z=math.radians(135.0))

    _setup_studio_render(res_x=2000, res_y=1180, padding=1.08, cam_vec=(0.56, -1.0, 0.52))
    os.makedirs(PEOPLE_PREVIEWS, exist_ok=True)
    out = os.path.join(PEOPLE_PREVIEWS, filename)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def _add_lot_pad(cx, cy, cw, cd, grass_a, grass_b, rim_mat):
    w, d = cw * CELL, cd * CELL
    _add_flat_box((cx, cy, -0.05), (w + 0.16, d + 0.16, 0.08), rim_mat)
    for ix in range(cw):
        for iy in range(cd):
            px = cx - w * 0.5 + (ix + 0.5) * CELL
            py = cy - d * 0.5 + (iy + 0.5) * CELL
            m = grass_a if (ix + iy) % 2 == 0 else grass_b
            _add_flat_box((px, py, -0.008), (CELL - 0.04, CELL - 0.04, 0.016), m)


def render_commercial_sheet(entries: list[dict], filename: str):
    """Рендерит контакт-лист коммерческих зданий на клеточных подиумах."""
    clear_scene()
    grass_a = _simple_mat("grass_a", (0.44, 0.69, 0.36), roughness=0.85)
    grass_b = _simple_mat("grass_b", (0.37, 0.61, 0.30), roughness=0.85)
    rim_mat = _simple_mat("rim", (0.30, 0.34, 0.39), roughness=0.75)

    rows = []
    cur = []
    cur_span = 0.0
    max_row_span = 22.0
    for item in entries:
        w_m = item["cells"][0] * CELL + 2.0
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
        total_w = sum(it["cells"][0] * CELL for it in row) + 2.2 * max(0, len(row) - 1)
        x_cursor = -total_w * 0.5
        for it in row:
            cw, cd = it["cells"]
            w_m = cw * CELL
            cx = x_cursor + w_m * 0.5
            cy = y_cursor
            _add_lot_pad(cx, cy, cw, cd, grass_a, grass_b, rim_mat)
            _import_glb_at(os.path.join(ROOT, it["file"]), location=(cx, cy, 0.0))
            x_cursor += w_m + 2.2
        y_cursor += row_depth + 4.2

    _setup_studio_render(res_x=2000, res_y=1280, padding=1.08, cam_vec=(0.72, -1.0, 0.68))
    os.makedirs(COM_PREVIEWS, exist_ok=True)
    out = os.path.join(COM_PREVIEWS, filename)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def render_commercial_street_showcase(filename: str):
    """Рендерит живую торговую улицу: пекарни, кафешки, кинотеатр, пассаж, молл + пешеходы и велосипедисты."""
    clear_scene()
    ground = _simple_mat("ground", (0.43, 0.68, 0.35), roughness=0.88)
    road = _simple_mat("road", (0.28, 0.31, 0.36), roughness=0.80)
    walk = _simple_mat("walk", (0.78, 0.77, 0.74), roughness=0.78)
    stripe = _simple_mat("stripe", (0.95, 0.89, 0.66), roughness=0.6)

    _add_flat_box((0.0, 1.5, -0.08), (32.0, 20.0, 0.16), ground)
    for y_rd in (-4.4, 2.6):
        _add_flat_box((0.0, y_rd, 0.015), (32.0, 2.5, 0.03), walk)
        _add_flat_box((0.0, y_rd, 0.025), (32.0, 1.68, 0.03), road)
        for sx in range(-14, 15, 2):
            _add_flat_box((sx, y_rd, 0.042), (0.8, 0.07, 0.01), stripe)

    # Передняя улица (уютные магазинчики, кафешки, дайнер, траттория и рынок)
    front_buildings = [
        ("com_corner_bakery_1x1", (-12.6, -2.0, 0.0)),
        ("com_street_cafe_1x1", (-10.4, -2.0, 0.0)),
        ("com_retro_diner_2x1", (-7.1, -2.0, 0.0)),
        ("com_bistro_terrace_2x1", (-2.7, -2.0, 0.0)),
        ("com_strip_shops_3x1", (2.8, -2.0, 0.0)),
        ("com_artisan_row_4x1", (10.2, -2.0, 0.0)),
    ]
    # Верхний проспект (крупная коммерция: кинотеатр, пассаж, универмаг, супермаркет и молл)
    back_buildings = [
        ("com_farmers_bazaar_2x2", (-12.2, 6.0, 0.0)),
        ("com_cinema_palace_2x1", (-7.6, 5.0, 0.0)),
        ("com_glass_arcade_4x1", (-1.2, 5.0, 0.0)),
        ("com_atrium_department_2x2", (5.2, 6.0, 0.0)),
        ("com_metropolis_mall_3x2", (10.6, 6.0, 0.0)),
    ]
    for mid, loc in front_buildings + back_buildings:
        _import_glb_at(os.path.join(COM_DIR, f"{mid}.glb"), location=loc)

    # Расставляем пешеходов на тротуарах и велосипедистов у края проезжей части (масштаб 0.30 для выразительности на общем плане)
    ped_placements = [
        ("citizen_casual_m", (-11.5, -3.35, 0.03), 90.0),
        ("citizen_coffee_f", (-9.8, -3.30, 0.03), -85.0),
        ("citizen_shopper_f", (-6.2, -3.35, 0.03), 95.0),
        ("citizen_business_m", (-3.4, -3.32, 0.03), -90.0),
        ("citizen_dress_f", (-1.2, -3.35, 0.03), 85.0),
        ("citizen_student_m", (1.8, -3.32, 0.03), 90.0),
        ("citizen_coat_f", (4.6, -3.35, 0.03), -90.0),
        ("citizen_hiker_m", (8.2, -3.32, 0.03), 90.0),
        ("cyclist_road", (-8.4, -3.85, 0.03), 90.0),
        ("cyclist_courier", (-0.4, -3.85, 0.03), 90.0),
        ("cyclist_city_cruiser", (5.8, -4.95, 0.03), -90.0),
        ("cyclist_commuter", (-4.5, 2.05, 0.03), 90.0),
    ]
    for pid, loc, deg in ped_placements:
        _import_glb_at(os.path.join(PEOPLE_DIR, f"{pid}.glb"), location=loc, rot_z=math.radians(deg), scale=0.32)

    _setup_studio_render(res_x=2000, res_y=1180, padding=1.05, cam_vec=(0.68, -1.0, 0.60), bg_rgb=(0.80, 0.88, 0.96))
    os.makedirs(COM_PREVIEWS, exist_ok=True)
    out = os.path.join(COM_PREVIEWS, filename)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def main():
    people_items = []
    for mid, kind, dname, alias, fn in PEOPLE_SPECS:
        people_items.append(export_person_model(mid, kind, dname, alias, fn))

    people_manifest = {
        "pack_name": "CityBuilder Citizens & Cyclists Low-Poly Pack v1",
        "godot_conventions": {
            "palette_texture": "res://assets/models/kenney/suburban/Textures/colormap.png",
            "visualizer_script": "res://scripts/grid/people_visualizer.gd",
            "people_scale": 0.22,
            "car_model_turns": 2,
            "forward_in_blender": "-Y",
            "forward_in_godot_with_turns_2": "-Z",
            "recolorable_via_instance_custom": True,
        },
        "walker_paths": [it["godot_res_path"] for it in people_items if it["kind"] == "walker"],
        "cyclist_paths": [it["godot_res_path"] for it in people_items if it["kind"] == "cyclist"],
        "models": people_items,
    }
    os.makedirs(PEOPLE_DIR, exist_ok=True)
    p_manifest_path = os.path.join(PEOPLE_DIR, "manifest.json")
    with open(p_manifest_path, "w", encoding="utf-8") as f:
        json.dump(people_manifest, f, ensure_ascii=False, indent=2)
    print("PEOPLE MANIFEST", p_manifest_path, "total:", len(people_items))

    com_items = []
    for mid, dname, zone, level, fn in COMMERCIAL_SPECS:
        com_items.append(export_commercial_model(mid, dname, zone, level, fn))

    com_manifest = {
        "pack_name": "CityBuilder Commercial Low-Poly Pack v1 (Shops, Cafes, Restaurants & Malls)",
        "cell_size_m": CELL,
        "godot_conventions": {
            "palette_texture": "res://assets/models/kenney/suburban/Textures/colormap.png",
            "district_recolor_compatible": True,
            "front_in_blender": "-Y",
            "front_in_godot_with_turns_2": "-Z",
            "recommended_model_scale": 1.0,
            "recommended_model_turns": 2,
        },
        "models": com_items,
    }
    os.makedirs(COM_DIR, exist_ok=True)
    c_manifest_path = os.path.join(COM_DIR, "manifest.json")
    with open(c_manifest_path, "w", encoding="utf-8") as f:
        json.dump(com_manifest, f, ensure_ascii=False, indent=2)
    print("COMMERCIAL MANIFEST", c_manifest_path, "total:", len(com_items))

    render_people_sheet(people_items, "people_and_cyclists.png")
    render_commercial_sheet([it for it in com_items if it["suggested_zone"] == "COMMERCIAL"], "commercial_shops_cafes.png")
    render_commercial_sheet([it for it in com_items if it["suggested_zone"] == "COMMERCIAL_HIGH"], "commercial_high_malls.png")
    render_commercial_street_showcase("commercial_street_showcase.png")


if __name__ == "__main__":
    main()
