"""Экспорт моделей служб (полиция, пожарное депо, поликлиника) и ветрогенераторов с glTF-анимацией.

Запуск (без окна, Blender 5.2):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/make_services_and_wind.py

Результат:
  - assets/models/blender/services/*.glb — 6 зданий служб (1×1 и 2×1) + 2 ветрогенератора с glTF-анимацией «spin-loop»
  - assets/models/blender/services/parts/*.glb — раздельные меши Base и Rotor для MultiMeshInstance3D (по желанию)
  - assets/models/blender/services/manifest.json — полный реестр моделей, габаритов и параметров вращения
  - assets/models/blender/services/previews/*.png — студийные превью служб, фаз анимации ветряков и диорама улицы
"""

import json
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arch_kit import CELL, ROOT, clear_scene, palette_material  # noqa: E402
from pack_services import CIVIC_SPECS, WIND_SPECS  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "models", "blender", "services")
PARTS_DIR = os.path.join(OUT_DIR, "parts")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
MANIFEST_PATH = os.path.join(OUT_DIR, "manifest.json")


def export_civic_model(model_id: str, display_name: str, service_kind: str, suggested_id: str, fn):
    builder, cw, cd = fn()
    dims = builder.fit_to_lot(cw, cd, margin=0.22)
    obj = builder.build_object()
    os.makedirs(OUT_DIR, exist_ok=True)
    filepath = os.path.join(OUT_DIR, f"{model_id}.glb")
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
    print(f"SERVICE [{service_kind}] {model_id} ({cw}x{cd}) -> dims={dims}m verts={verts} tris={tris}")
    return {
        "id": model_id,
        "kind": "service_static",
        "service": service_kind,
        "suggested_building_id": suggested_id,
        "display_name": display_name,
        "file": f"assets/models/blender/services/{model_id}.glb",
        "godot_kit_path": f"blender/services/{model_id}",
        "cells": [cw, cd],
        "area_cells": cw * cd,
        "dimensions_m": list(dims),
        "vertices": verts,
        "triangles": tris,
        "recommended_model_scale": 1.0,
        "recommended_model_turns": 2,
        "built_in_emblem": True,
    }


def _export_single_part(builder, shared_mat, filepath: str):
    """Экспортирует одиночный меш без сдвига координат (для Base или центрированного в (0,0,0) Rotor)."""
    builder.material = shared_mat
    obj = builder.build_object()
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
    )
    tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
    verts = len(obj.data.vertices)
    bpy.data.objects.remove(obj, do_unlink=True)
    return verts, tris


def export_animated_wind_model(model_id: str, display_name: str, wind_kind: str, fn):
    base_b, rotor_b, anim, cw, cd = fn()
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PARTS_DIR, exist_ok=True)

    # 1. Сохраняем раздельные части (parts/*_base.glb и parts/*_rotor.glb с центром вращения ровно в (0,0,0))
    clear_scene()
    mat_parts = palette_material(linear=True)
    part_prefix = anim["part_prefix"]
    base_part_rel = f"assets/models/blender/services/parts/{part_prefix}_base.glb"
    rotor_part_rel = f"assets/models/blender/services/parts/{part_prefix}_rotor.glb"
    b_verts, b_tris = _export_single_part(base_b, mat_parts, os.path.join(ROOT, base_part_rel))
    r_verts, r_tris = _export_single_part(rotor_b, mat_parts, os.path.join(ROOT, rotor_part_rel))

    # 2. Собираем единую анимированную сцену Base + Rotor с зацикленным glTF-клипом «spin-loop»
    clear_scene()
    shared_mat = palette_material(linear=True)
    base_b.material = shared_mat
    rotor_b.material = shared_mat

    base_obj = base_b.build_object()
    rotor_obj = rotor_b.build_object()

    px, py, pz = anim["pivot_blender"]
    rotor_obj.parent = base_obj
    rotor_obj.matrix_parent_inverse.identity()
    rotor_obj.location = (px, py, pz)
    rotor_obj.rotation_mode = "XYZ"

    scene = bpy.context.scene
    fps = anim["fps"]
    frames = anim["frames"]
    scene.render.fps = fps
    scene.frame_start = 0
    scene.frame_end = frames

    axis = anim["axis_blender"]
    sign = anim["axis_sign"]
    # Записываем точный равномерный ключ на каждом кадре 0..frames — даёт идеально линейное вращение 0→360°
    # в кватернионах glTF без замедления на стыке цикла и без зависимости от API F-кривых разных версий Blender!
    for f in range(frames + 1):
        ang = sign * (2.0 * math.pi * f / frames)
        if axis == "Y":
            rotor_obj.rotation_euler = (0.0, ang, 0.0)
        elif axis == "Z":
            rotor_obj.rotation_euler = (0.0, 0.0, ang)
        else:
            rotor_obj.rotation_euler = (ang, 0.0, 0.0)
        rotor_obj.keyframe_insert(data_path="rotation_euler", frame=f)

    if rotor_obj.animation_data and rotor_obj.animation_data.action:
        # Суффикс -loop автоматически включает Animation.LOOP_LINEAR при импорте .glb в Godot 4!
        rotor_obj.animation_data.action.name = anim["clip_name"]

    scene.frame_set(0)

    # Считаем габариты всей установки в стартовой позе + максимальный вылет вращения
    all_pts = list(base_b.verts) + [(vx + px, vy + py, vz + pz) for (vx, vy, vz) in rotor_b.verts]
    xs = [p[0] for p in all_pts]
    ys = [p[1] for p in all_pts]
    zs = [p[2] for p in all_pts]
    dims = (round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3))

    filepath = os.path.join(OUT_DIR, f"{model_id}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    base_obj.select_set(True)
    rotor_obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
    )

    # 3. Самопроверка экспортированного .glb: импортируем обратно и убеждаемся, что анимация крутит Rotor!
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=filepath)
    imp_rotor = next((o for o in bpy.data.objects if o.name.startswith("Rotor")), None)
    assert imp_rotor is not None, f"В {model_id}.glb не найден узел Rotor!"
    angles_deg = []
    for test_f in (0, frames // 4, frames // 2, (frames * 3) // 4):
        bpy.context.scene.frame_set(test_f)
        bpy.context.view_layer.update()
        q = imp_rotor.matrix_world.to_quaternion()
        angles_deg.append(round(math.degrees(q.angle), 1))
    print(
        f"WIND [{wind_kind}] {model_id} -> dims={dims}m verts={b_verts + r_verts} tris={b_tris + r_tris} "
        f"verified_anim_angles_deg={angles_deg}"
    )

    return {
        "id": model_id,
        "kind": "power_animated",
        "service": wind_kind,
        "display_name": display_name,
        "file": f"assets/models/blender/services/{model_id}.glb",
        "godot_kit_path": f"blender/services/{model_id}",
        "cells": [cw, cd],
        "area_cells": cw * cd,
        "dimensions_m": list(dims),
        "vertices": b_verts + r_verts,
        "triangles": b_tris + r_tris,
        "recommended_model_scale": 1.0,
        "recommended_model_turns": 2,
        "animation": {
            "clip_name": anim["clip_name"],
            "auto_loops_in_godot": True,
            "fps": fps,
            "frames": frames,
            "duration_sec": round(frames / fps, 3),
            "base_node": "Base",
            "rotor_node": "Rotor",
            "rotor_axis_godot": anim["axis_godot"],
            "rotor_pivot_godot_scene": anim["pivot_godot_scene"],
            "rotor_pivot_godot_with_turns_2": anim["pivot_godot_turns_2"],
            "split_parts": {
                "base_file": base_part_rel,
                "base_godot_kit_path": f"blender/services/parts/{part_prefix}_base",
                "rotor_file": rotor_part_rel,
                "rotor_godot_kit_path": f"blender/services/parts/{part_prefix}_rotor",
            },
        },
    }


# ---------------------------------------------------------------------------
# Студийный рендер превью-листов и диорамы (Blender EEVEE)
# ---------------------------------------------------------------------------

def _simple_mat(name, rgb, roughness=0.85):
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


def _add_lot_pad(cx, cy, cw, cd, grass_a, grass_b, rim_mat):
    w, d = cw * CELL, cd * CELL
    _add_flat_box((cx, cy, -0.045), (w + 0.14, d + 0.14, 0.07), rim_mat)
    for ix in range(cw):
        for iy in range(cd):
            px = cx - w * 0.5 + (ix + 0.5) * CELL
            py = cy - d * 0.5 + (iy + 0.5) * CELL
            m = grass_a if (ix + iy) % 2 == 0 else grass_b
            _add_flat_box((px, py, -0.008), (CELL - 0.03, CELL - 0.03, 0.016), m)


def _import_glb_at(glb_path: str, location=(0.0, 0.0, 0.0), rot_z: float = 0.0, eval_frame: int | None = None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    added = [o for o in bpy.data.objects if o not in before]
    # Если задан кадр eval_frame, вычисляем реальную импортированную из .glb glTF-анимацию на этом кадре
    # и фиксируем полученную матрицу ротора, чтобы на одном рендере показать разные кадры анимации!
    if eval_frame is not None:
        bpy.context.scene.frame_set(eval_frame)
        bpy.context.view_layer.update()
        for o in added:
            if o.animation_data:
                baked_basis = o.matrix_basis.copy()
                o.animation_data_clear()
                o.matrix_basis = baked_basis
    roots = [o for o in added if o.parent is None]
    for r in roots:
        r.rotation_mode = "XYZ"
        r.rotation_euler = (r.rotation_euler.x, r.rotation_euler.y, r.rotation_euler.z + rot_z)
        r.location = (r.location.x + location[0], r.location.y + location[1], r.location.z + location[2])
    return added


def _setup_studio_render(res_x=2000, res_y=1250, padding=1.10, cam_vec=(0.74, -1.0, 0.68), bg_rgb=(0.86, 0.90, 0.94)):
    scene = bpy.context.scene
    for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            scene.render.engine = name
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
    sun.data.color = (1.0, 0.97, 0.91)
    sun.data.angle = math.radians(4.0)
    sun.rotation_euler = (math.radians(48), math.radians(14), math.radians(34))

    bpy.ops.object.light_add(type="SUN", location=(-10, 8, 12))
    fill = bpy.context.active_object
    fill.data.energy = 1.05
    fill.data.color = (0.82, 0.90, 1.0)
    fill.rotation_euler = (math.radians(58), 0.0, math.radians(-142))
    try:
        fill.data.use_shadow = False
    except Exception:
        pass

    bpy.context.view_layer.update()
    inf = 1e9
    lo = Vector((inf, inf, inf))
    hi = Vector((-inf, -inf, -inf))
    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo.x, lo.y, lo.z = min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)
            hi.x, hi.y, hi.z = max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)

    center = (lo + hi) * 0.5
    direction = Vector(cam_vec).normalized()
    bpy.ops.object.camera_add(location=center + direction * 65.0)
    cam = bpy.context.active_object
    cam.data.type = "ORTHO"
    cam.data.clip_start = 0.1
    cam.data.clip_end = 300.0
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    bpy.context.view_layer.update()

    inv = cam.matrix_world.inverted()
    aspect = res_x / res_y
    half_x = half_y = 0.0
    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            p = inv @ (obj.matrix_world @ Vector(corner))
            half_x = max(half_x, abs(p.x))
            half_y = max(half_y, abs(p.y))
    cam.data.ortho_scale = max(half_x * 2.0, half_y * 2.0 * aspect) * padding


def render_civic_sheet(civic_items, filename: str):
    clear_scene()
    grass_a = _simple_mat("grass_a", (0.44, 0.70, 0.36))
    grass_b = _simple_mat("grass_b", (0.38, 0.64, 0.31))
    rim_mat = _simple_mat("rim", (0.72, 0.74, 0.77))

    row_1x1 = [it for it in civic_items if it["cells"] == [1, 1]]
    row_2x1 = [it for it in civic_items if it["cells"] == [2, 1]]

    for row_idx, row in enumerate((row_1x1, row_2x1)):
        gap = 1.8
        total_w = sum(it["cells"][0] * CELL for it in row) + gap * (len(row) - 1)
        x_cur = -total_w * 0.5
        y_pos = row_idx * 4.4
        for it in row:
            cw, cd = it["cells"]
            wm = cw * CELL
            cx = x_cur + wm * 0.5
            _add_lot_pad(cx, y_pos, cw, cd, grass_a, grass_b, rim_mat)
            _import_glb_at(os.path.join(ROOT, it["file"]), location=(cx, y_pos, 0.0))
            x_cur += wm + gap

    _setup_studio_render(res_x=2000, res_y=1220, padding=1.12, cam_vec=(0.68, -1.0, 0.66))
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out = os.path.join(PREVIEW_DIR, filename)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def render_wind_animation_sheet(wind_items, filename: str):
    """Рендерит оба ветрогенератора в 4 последовательных фазах вращения (0°, 30°, 60°, 90°)."""
    clear_scene()
    grass_a = _simple_mat("grass_a", (0.44, 0.70, 0.36))
    grass_b = _simple_mat("grass_b", (0.38, 0.64, 0.31))
    rim_mat = _simple_mat("rim", (0.72, 0.74, 0.77))

    # Показываем 4 реальных кадра glTF-анимации вращения (0°, 30°, 60°, 90° оборота):
    fracs = (0.0, 1.0 / 12.0, 2.0 / 12.0, 3.0 / 12.0)
    for r_idx, it in enumerate(wind_items):
        y_pos = r_idx * 6.4
        total_f = it["animation"]["frames"]
        for c_idx, frac in enumerate(fracs):
            cx = (c_idx - 1.5) * 3.4
            _add_lot_pad(cx, y_pos, 1, 1, grass_a, grass_b, rim_mat)
            _import_glb_at(
                os.path.join(ROOT, it["file"]),
                location=(cx, y_pos, 0.0),
                eval_frame=int(round(total_f * frac)),
            )

    _setup_studio_render(res_x=2000, res_y=1280, padding=1.10, cam_vec=(0.64, -1.0, 0.54))
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out = os.path.join(PREVIEW_DIR, filename)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def render_services_showcase(filename: str):
    """Диорама городского квартала служб (полиция, пожарная часть, медцентр) и ветропарка."""
    clear_scene()
    ground = _simple_mat("ground", (0.43, 0.68, 0.35), roughness=0.88)
    road = _simple_mat("road", (0.29, 0.32, 0.37), roughness=0.80)
    walk = _simple_mat("walk", (0.77, 0.76, 0.73), roughness=0.78)
    stripe = _simple_mat("stripe", (0.95, 0.89, 0.66), roughness=0.6)

    _add_flat_box((0.0, 0.8, -0.08), (22.0, 15.0, 0.16), ground)
    for y_rd in (-3.6, 2.2):
        _add_flat_box((0.0, y_rd, 0.015), (22.0, 2.2, 0.03), walk)
        _add_flat_box((0.0, y_rd, 0.025), (22.0, 1.58, 0.03), road)
        for sx in range(-9, 10, 2):
            _add_flat_box((sx, y_rd, 0.042), (0.8, 0.07, 0.01), stripe)

    # Передняя улица (крупные городские службы 2×1 и компактные 1×1)
    front_row = [
        ("police_precinct_2x1", (-7.4, -1.3, 0.0), None),
        ("fire_depot_2x1", (-2.6, -1.3, 0.0), None),
        ("clinic_center_2x1", (2.2, -1.3, 0.0), None),
        ("police_station_1x1", (5.8, -1.3, 0.0), None),
        ("fire_station_1x1", (8.0, -1.3, 0.0), None),
    ]
    # Верхняя терраса (поликлиника 1×1 + зелёный ветропарк из 3 HAWT и 3 VAWT на разных кадрах анимации)
    back_row = [
        ("clinic_1x1", (-8.6, 4.5, 0.0), None),
        ("wind_turbine_hawt_1x1", (-5.8, 4.5, 0.0), 8),
        ("wind_turbine_hawt_1x1", (-3.4, 4.5, 0.0), 22),
        ("wind_turbine_hawt_1x1", (-1.0, 4.5, 0.0), 35),
        ("wind_turbine_vawt_1x1", (2.0, 4.5, 0.0), 0),
        ("wind_turbine_vawt_1x1", (4.4, 4.5, 0.0), 12),
        ("wind_turbine_vawt_1x1", (6.8, 4.5, 0.0), 24),
    ]
    for mid, loc, ef in front_row + back_row:
        _import_glb_at(os.path.join(OUT_DIR, f"{mid}.glb"), location=loc, eval_frame=ef)

    _setup_studio_render(res_x=2000, res_y=1180, padding=1.06, cam_vec=(0.66, -1.0, 0.58), bg_rgb=(0.80, 0.88, 0.96))
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out = os.path.join(PREVIEW_DIR, filename)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def main():
    civic_items = []
    for mid, dname, skind, sug_id, fn in CIVIC_SPECS:
        civic_items.append(export_civic_model(mid, dname, skind, sug_id, fn))

    wind_items = []
    for mid, dname, wkind, fn in WIND_SPECS:
        wind_items.append(export_animated_wind_model(mid, dname, wkind, fn))

    manifest = {
        "pack_name": "CityBuilder Services & Animated Wind Power Pack v1",
        "cell_size_m": CELL,
        "godot_conventions": {
            "palette_texture": "res://assets/models/kenney/suburban/Textures/colormap.png",
            "service_zone_none_preserves_exact_colors": True,
            "front_in_blender": "-Y",
            "front_in_godot_with_turns_2": "-Z",
            "recommended_model_scale": 1.0,
            "recommended_model_turns": 2,
            "recommended_sign_color": "Color(0, 0, 0, 0) — 3D-эмблемы уже встроены в модели",
        },
        "models": civic_items + wind_items,
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print("MANIFEST", MANIFEST_PATH, "total:", len(manifest["models"]))

    render_civic_sheet(civic_items, "services_civic.png")
    render_wind_animation_sheet(wind_items, "services_wind_animation.png")
    render_services_showcase("services_showcase.png")


if __name__ == "__main__":
    main()
