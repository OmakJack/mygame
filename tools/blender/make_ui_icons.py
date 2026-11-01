"""Генератор 3D-иконок интерфейса CityBuilder в Blender 5.2.

Рендерит изометрические 3D-миниатюры с прозрачным фоном (PNG) для:
- всех карточек инструментов (дороги, зоны, свет/вода, службы, парки, снос, слои карты);
- вкладок нижней панели;
- плашек верхней панели (город, казна, жители, звание, работа, свет, вода, трафик);
- герба главного меню.

Запуск:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/make_ui_icons.py
"""

import math
import os
import bpy
from mathutils import Vector, Euler

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS_DIR = os.path.join(ROOT, "assets", "models")
OUT_DIR = os.path.join(ROOT, "assets", "ui", "icons")


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)


def make_mat(name, color, roughness=0.45, metallic=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def add_box(center, size, mat, rot=(0.0, 0.0, 0.0), bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    obj.data.materials.append(mat)
    return obj


def add_cylinder(center, radius, depth, mat, rot=(0.0, 0.0, 0.0), vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=center, rotation=rot
    )
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    return obj


def add_sphere(center, radius, mat, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24, ring_count=16, radius=radius, location=center
    )
    obj = bpy.context.active_object
    obj.scale = scale
    obj.data.materials.append(mat)
    return obj


def add_cone(center, r1, r2, depth, mat, vertices=20):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=center
    )
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    return obj


def import_glb(rel_path, location=(0.0, 0.0, 0.0), scale=1.0, rot_z=0.0):
    full_path = os.path.join(MODELS_DIR, *rel_path.split("/")) + ".glb"
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=full_path)
    imported = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in imported if o.parent not in imported]
    parent = bpy.data.objects.new("glb_holder", None)
    bpy.context.collection.objects.link(parent)
    for r in roots:
        r.parent = parent
    parent.location = location
    parent.scale = (scale, scale, scale)
    parent.rotation_euler = (0.0, 0.0, rot_z)
    # Closest interpolation for Kenney pixel palettes so colors stay crisp
    for o in imported:
        if o.type == "MESH" and o.data:
            for mat in o.data.materials:
                if mat and mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type == "TEX_IMAGE":
                            node.interpolation = "Closest"
    return imported


def scene_bounds():
    min_v = Vector((1e9, 1e9, 1e9))
    max_v = Vector((-1e9, -1e9, -1e9))
    found = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = eval_obj.to_mesh()
        for v in mesh.vertices:
            w = obj.matrix_world @ v.co
            min_v.x = min(min_v.x, w.x)
            min_v.y = min(min_v.y, w.y)
            min_v.z = min(min_v.z, w.z)
            max_v.x = max(max_v.x, w.x)
            max_v.y = max(max_v.y, w.y)
            max_v.z = max(max_v.z, w.z)
            found = True
        eval_obj.to_mesh_clear()
    if not found:
        return Vector((0, 0, 0)), Vector((1, 1, 1))
    return (min_v + max_v) * 0.5, (max_v - min_v)


def setup_camera_and_lights(size_px=96, padding=1.22):
    scene = bpy.context.scene
    for name in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = name
            break
        except Exception:
            pass
    scene.render.film_transparent = True
    scene.render.resolution_x = size_px
    scene.render.resolution_y = size_px
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    # Vibrant sRGB colors matching Godot UI palette
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:
        pass
    scene.view_settings.exposure = 0.15

    center, span = scene_bounds()
    # Isometric camera looking from (+X, -Y, +Z) toward center
    cam_dir = Vector((1.0, -1.0, 0.82)).normalized()
    cam_pos = center + cam_dir * 10.0

    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = "ORTHO"
    # Project bounding box onto camera plane to fit tightly
    forward = -cam_dir
    right = forward.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(forward).normalized()

    min_x, max_x = 1e9, -1e9
    min_y, max_y = 1e9, -1e9
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = eval_obj.to_mesh()
        for v in mesh.vertices:
            rel = (obj.matrix_world @ v.co) - center
            px = rel.dot(right)
            py = rel.dot(up)
            min_x, max_x = min(min_x, px), max(max_x, px)
            min_y, max_y = min(min_y, py), max(max_y, py)
        eval_obj.to_mesh_clear()

    shift_x = (min_x + max_x) * 0.5
    shift_y = (min_y + max_y) * 0.5
    target = center + right * shift_x + up * shift_y
    cam_pos = target + cam_dir * 10.0
    cam_data.ortho_scale = max(max_x - min_x, max_y - min_y, 0.2) * padding

    cam_obj = bpy.data.objects.new("IconCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = cam_pos
    cam_obj.rotation_euler = (target - cam_pos).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    # Warm sunlit key light
    key_data = bpy.data.lights.new("Key", type="SUN")
    key_data.energy = 4.2
    key_data.color = (1.0, 0.96, 0.88)
    key_obj = bpy.data.objects.new("Key", key_data)
    bpy.context.collection.objects.link(key_obj)
    key_obj.rotation_euler = (math.radians(48), math.radians(-18), math.radians(28))

    # Soft sky fill light
    fill_data = bpy.data.lights.new("Fill", type="SUN")
    fill_data.energy = 2.2
    fill_data.color = (0.78, 0.88, 1.0)
    fill_obj = bpy.data.objects.new("Fill", fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(65), math.radians(40), math.radians(-55))

    # Warm bottom bounce light so dark undersides read cleanly on UI cards
    bounce_data = bpy.data.lights.new("Bounce", type="SUN")
    bounce_data.energy = 1.1
    bounce_data.color = (0.98, 0.92, 0.82)
    bounce_obj = bpy.data.objects.new("Bounce", bounce_data)
    bpy.context.collection.objects.link(bounce_obj)
    bounce_obj.rotation_euler = (math.radians(125), math.radians(0), math.radians(35))


def render_icon(name, build_fn, size_px=96, padding=1.18):
    clear_scene()
    build_fn()
    setup_camera_and_lights(size_px=size_px, padding=padding)
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"{name}.png")
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("ICON", out_path)


def add_plinth(color, size=(1.15, 1.15, 0.14), z=-0.07):
    mat = make_mat("plinth", color, roughness=0.55)
    add_box((0.0, 0.0, z), size, mat, bevel=0.04)


# --- Сцены иконок ---

def icon_tool_road():
    add_plinth((0.42, 0.66, 0.36))
    import_glb("kenney/roads/road-straight", (0, 0, 0.0), scale=1.0)
    import_glb("kenney/cars/sedan", (0.0, 0.0, 0.04), scale=0.22, rot_z=math.radians(90))


def icon_tool_avenue():
    add_plinth((0.38, 0.62, 0.34))
    import_glb("kenney/roads/road-straight", (0, 0, 0.0), scale=1.05)
    # Зелёная разделительная полоса и фонарь
    grass = make_mat("median", (0.30, 0.72, 0.34), roughness=0.6)
    add_box((0.0, 0.0, 0.04), (0.92, 0.10, 0.03), grass, bevel=0.01)
    pole = make_mat("pole", (0.75, 0.78, 0.84), roughness=0.3, metallic=0.5)
    lamp = make_mat("lamp", (1.0, 0.92, 0.55), roughness=0.2, emission=1.5)
    add_cylinder((0.0, 0.0, 0.19), 0.02, 0.28, pole)
    add_box((0.0, 0.0, 0.33), (0.06, 0.16, 0.03), lamp, bevel=0.01)
    import_glb("kenney/cars/suv", (-0.1, -0.18, 0.04), scale=0.20, rot_z=math.radians(90))
    import_glb("kenney/cars/taxi", (0.12, 0.18, 0.04), scale=0.20, rot_z=math.radians(-90))


def icon_tool_highway():
    add_plinth((0.40, 0.45, 0.54))
    import_glb("kenney/roads/road-straight-barrier", (0, 0, 0.0), scale=1.05)
    import_glb("kenney/roads/sign-highway", (0.0, 0.0, 0.02), scale=1.0)
    import_glb("kenney/cars/sedan-sports", (0.0, -0.15, 0.04), scale=0.22, rot_z=math.radians(90))


def icon_zone_r():
    add_plinth((0.30, 0.74, 0.36), size=(1.2, 1.2, 0.16))
    import_glb("kenney/suburban/building-type-b", (-0.05, 0.05, 0.0), scale=1.15)
    import_glb("kenney/suburban/tree-large", (0.36, -0.32, 0.0), scale=1.1)


def icon_zone_c():
    add_plinth((0.26, 0.54, 0.94), size=(1.2, 1.2, 0.16))
    import_glb("kenney/commercial/building-d", (0.0, 0.0, 0.0), scale=1.25)


def icon_zone_i():
    add_plinth((0.94, 0.72, 0.18), size=(1.2, 1.2, 0.16))
    import_glb("kenney/industrial/building-c", (0.0, 0.0, 0.0), scale=1.05)


def icon_dezone():
    add_plinth((0.72, 0.68, 0.62), size=(1.1, 1.1, 0.14))
    red = make_mat("red_x", (0.88, 0.28, 0.22), roughness=0.35)
    add_box((0, 0, 0.18), (0.85, 0.22, 0.18), red, rot=(0, 0, math.radians(45)), bevel=0.04)
    add_box((0, 0, 0.18), (0.85, 0.22, 0.18), red, rot=(0, 0, math.radians(-45)), bevel=0.04)


def icon_zone_r_high():
    add_plinth((0.20, 0.62, 0.34), size=(1.25, 1.25, 0.16))
    import_glb("blender/panel-b", (0.0, 0.0, 0.0), scale=0.85)


def icon_zone_c_high():
    add_plinth((0.20, 0.42, 0.86), size=(1.25, 1.25, 0.16))
    import_glb("kenney/commercial/building-j", (0.0, 0.0, 0.0), scale=1.15)


def icon_zone_o():
    add_plinth((0.22, 0.64, 0.78), size=(1.25, 1.25, 0.16))
    import_glb("kenney/commercial/building-skyscraper-b", (0.0, 0.0, 0.0), scale=1.05)


def icon_power_plant():
    add_plinth((0.94, 0.72, 0.18), size=(1.2, 1.2, 0.16))
    import_glb("kenney/industrial/chimney-large", (-0.08, 0.08, 0.0), scale=1.05)
    # 3D молния спереди
    gold = make_mat("bolt", (1.0, 0.82, 0.12), roughness=0.25, emission=0.6)
    add_box((0.32, -0.32, 0.42), (0.14, 0.08, 0.36), gold, rot=(0, math.radians(22), math.radians(-20)), bevel=0.02)
    add_box((0.36, -0.34, 0.24), (0.14, 0.08, 0.34), gold, rot=(0, math.radians(22), math.radians(-20)), bevel=0.02)


def _bolt():
    """3D молния спереди — как у ТЭЦ: станция даёт свет."""
    gold = make_mat("bolt", (1.0, 0.82, 0.12), roughness=0.25, emission=0.6)
    add_box((0.36, -0.36, 0.40), (0.13, 0.08, 0.33), gold, rot=(0, math.radians(22), math.radians(-20)), bevel=0.02)
    add_box((0.40, -0.38, 0.23), (0.13, 0.08, 0.31), gold, rot=(0, math.radians(22), math.radians(-20)), bevel=0.02)


def icon_wind_small():
    add_plinth((0.46, 0.80, 0.52), size=(1.2, 1.2, 0.16))
    import_glb("blender/services/wind_turbine_hawt_1x1", (-0.04, 0.04, 0.0), scale=0.42)
    _bolt()


def icon_wind_large():
    add_plinth((0.46, 0.80, 0.52), size=(1.2, 1.2, 0.16))
    import_glb("blender/services/wind_turbine_vawt_1x1", (-0.04, 0.04, 0.0), scale=0.5)
    _bolt()


def icon_water_tower():
    add_plinth((0.24, 0.64, 0.94), size=(1.2, 1.2, 0.16))
    import_glb("kenney/industrial/water-tower", (-0.06, 0.06, 0.0), scale=1.05)
    # 3D капля воды спереди
    aqua = make_mat("aqua", (0.18, 0.68, 0.98), roughness=0.2, emission=0.3)
    add_sphere((0.32, -0.32, 0.24), 0.16, aqua)
    add_cone((0.32, -0.32, 0.40), 0.14, 0.0, 0.24, aqua)


def icon_school():
    add_plinth((0.95, 0.76, 0.22), size=(1.35, 1.35, 0.16))
    import_glb("kenney/commercial/building-c", (-0.08, 0.08, 0.0), scale=1.15, rot_z=math.radians(90))
    gold = make_mat("sign", (0.98, 0.78, 0.12), roughness=0.3)
    add_box((0.08, -0.08, 0.72), (0.32, 0.32, 0.10), gold, bevel=0.02)
    import_glb("kenney/suburban/tree-small", (0.38, -0.36, 0.0), scale=1.05)


# Службы — модели Argon (blender/services): 1×1 на квадратной плите, 2×1 — на длинной (здание крупнее).
SERVICE_PLINTHS = {"health": (0.90, 0.26, 0.24), "fire": (0.92, 0.38, 0.16), "police": (0.24, 0.46, 0.92)}


def _service_icon(kind, model, large):
    if large:
        add_plinth(SERVICE_PLINTHS[kind], size=(1.75, 1.0, 0.16))
        import_glb("blender/services/" + model, (0.0, 0.0, 0.0), scale=0.44)
    else:
        add_plinth(SERVICE_PLINTHS[kind], size=(1.3, 1.3, 0.16))
        import_glb("blender/services/" + model, (0.0, 0.0, 0.0), scale=0.66)


def icon_health():
    _service_icon("health", "clinic_1x1", False)


def icon_health_large():
    _service_icon("health", "clinic_center_2x1", True)


def icon_fire():
    _service_icon("fire", "fire_station_1x1", False)


def icon_fire_large():
    _service_icon("fire", "fire_depot_2x1", True)


def icon_police():
    _service_icon("police", "police_station_1x1", False)


def icon_police_large():
    _service_icon("police", "police_precinct_2x1", True)


def icon_park_square():
    add_plinth((0.28, 0.70, 0.42), size=(1.2, 1.2, 0.16))
    stone = make_mat("stone", (0.82, 0.78, 0.70), roughness=0.6)
    add_box((0, 0, 0.02), (1.05, 0.24, 0.03), stone, bevel=0.01)
    add_box((0, 0, 0.02), (0.24, 1.05, 0.03), stone, bevel=0.01)
    import_glb("kenney/suburban/tree-large", (-0.30, 0.30, 0.0), scale=1.15)
    import_glb("kenney/suburban/tree-small", (0.32, 0.28, 0.0), scale=1.15)
    import_glb("kenney/suburban/tree-small", (-0.28, -0.32, 0.0), scale=1.1)
    import_glb("kenney/suburban/tree-large", (0.28, -0.28, 0.0), scale=1.05)


def icon_park_garden():
    add_plinth((0.22, 0.66, 0.48), size=(1.2, 1.2, 0.16))
    stone = make_mat("stone", (0.84, 0.80, 0.72), roughness=0.6)
    add_cylinder((0, 0, 0.02), 0.38, 0.03, stone)
    pink = make_mat("pink", (0.95, 0.42, 0.62), roughness=0.4)
    gold = make_mat("gold", (0.98, 0.78, 0.22), roughness=0.4)
    for angle, mat in ((0, pink), (90, gold), (180, pink), (270, gold)):
        rad = math.radians(angle + 45)
        add_box((math.cos(rad) * 0.34, math.sin(rad) * 0.34, 0.06), (0.24, 0.24, 0.08), mat, bevel=0.03)
    import_glb("kenney/suburban/tree-large", (0.0, 0.0, 0.02), scale=1.25)
    import_glb("kenney/suburban/tree-small", (-0.36, 0.0, 0.0), scale=1.05)
    import_glb("kenney/suburban/tree-small", (0.36, 0.0, 0.0), scale=1.05)


def icon_park_plaza():
    add_plinth((0.80, 0.76, 0.68), size=(1.2, 1.2, 0.16))
    marble = make_mat("marble", (0.92, 0.90, 0.86), roughness=0.35)
    water = make_mat("water", (0.22, 0.68, 0.96), roughness=0.15, emission=0.35)
    add_cylinder((0, 0, 0.08), 0.38, 0.14, marble)
    add_cylinder((0, 0, 0.13), 0.31, 0.06, water)
    add_cylinder((0, 0, 0.24), 0.09, 0.26, marble)
    add_cylinder((0, 0, 0.36), 0.20, 0.06, marble)
    add_sphere((0, 0, 0.46), 0.10, water)
    import_glb("kenney/suburban/tree-small", (-0.40, 0.40, 0.0), scale=1.0)
    import_glb("kenney/suburban/tree-small", (0.40, 0.40, 0.0), scale=1.0)


def icon_bulldoze():
    add_plinth((0.76, 0.38, 0.26), size=(1.2, 1.2, 0.16))
    import_glb("kenney/cars/tractor-shovel", (-0.04, 0.04, 0.02), scale=0.34, rot_z=math.radians(-35))
    brick = make_mat("brick", (0.85, 0.46, 0.30), roughness=0.5)
    add_box((0.30, -0.28, 0.08), (0.16, 0.16, 0.14), brick, rot=(0.2, 0.1, 0.4), bevel=0.02)
    add_box((0.16, -0.36, 0.06), (0.13, 0.13, 0.12), brick, rot=(-0.1, 0.3, 0.1), bevel=0.02)


def icon_overlay():
    m1 = make_mat("l1", (0.30, 0.74, 0.38), roughness=0.35)
    m2 = make_mat("l2", (0.26, 0.62, 0.95), roughness=0.35)
    m3 = make_mat("l3", (0.96, 0.74, 0.20), roughness=0.35)
    add_box((0, 0, 0.0), (0.95, 0.95, 0.10), m1, bevel=0.03)
    add_box((0, 0, 0.24), (0.95, 0.95, 0.10), m2, bevel=0.03)
    add_box((0, 0, 0.48), (0.95, 0.95, 0.10), m3, bevel=0.03)


# --- Статусные 3D-иконки верхней панели и меню ---

def icon_stat_money():
    gold = make_mat("gold", (0.98, 0.78, 0.18), roughness=0.25, metallic=0.35, emission=0.2)
    rim = make_mat("rim", (0.88, 0.62, 0.10), roughness=0.35, metallic=0.3)
    for i, (x, y, z) in enumerate(((-0.18, 0.12, 0.0), (0.18, -0.10, 0.0))):
        for h in range(4 if i == 0 else 3):
            zc = z + h * 0.14
            add_cylinder((x, y, zc), 0.32, 0.11, gold)
            add_cylinder((x, y, zc + 0.01), 0.25, 0.115, rim)


def icon_stat_pop():
    wall = make_mat("wall", (0.98, 0.94, 0.86), roughness=0.45)
    roof = make_mat("roof", (0.88, 0.32, 0.24), roughness=0.4)
    green = make_mat("base", (0.32, 0.74, 0.38), roughness=0.5)
    add_box((0, 0, -0.06), (0.95, 0.95, 0.12), green, bevel=0.04)
    add_box((0, 0, 0.22), (0.64, 0.60, 0.44), wall, bevel=0.03)
    add_cone((0, 0, 0.60), 0.56, 0.04, 0.36, roof, vertices=4)
    bpy.context.active_object.rotation_euler = (0, 0, math.radians(45))


def icon_stat_rank():
    gold = make_mat("star", (1.0, 0.80, 0.16), roughness=0.22, metallic=0.3, emission=0.35)
    base = make_mat("shield", (0.86, 0.36, 0.22), roughness=0.4)
    add_cylinder((0, 0, 0.0), 0.48, 0.14, base, vertices=6)
    add_cylinder((0, 0, 0.12), 0.36, 0.16, gold, vertices=5)
    add_sphere((0, 0, 0.22), 0.18, gold)


def icon_stat_jobs():
    case_mat = make_mat("case", (0.76, 0.44, 0.22), roughness=0.4)
    brass = make_mat("brass", (0.98, 0.80, 0.24), roughness=0.25, metallic=0.4)
    add_box((0, 0, 0.24), (0.82, 0.32, 0.54), case_mat, bevel=0.05)
    add_box((0, 0, 0.56), (0.34, 0.10, 0.14), case_mat, bevel=0.02)
    add_box((-0.20, -0.17, 0.28), (0.10, 0.06, 0.14), brass, bevel=0.01)
    add_box((0.20, -0.17, 0.28), (0.10, 0.06, 0.14), brass, bevel=0.01)


def icon_stat_power():
    amber = make_mat("bg", (0.96, 0.72, 0.14), roughness=0.3, emission=0.4)
    add_box((-0.06, 0.0, 0.38), (0.28, 0.18, 0.54), amber, rot=(0, math.radians(24), 0), bevel=0.03)
    add_box((0.08, 0.0, 0.12), (0.28, 0.18, 0.54), amber, rot=(0, math.radians(24), 0), bevel=0.03)


def icon_stat_water():
    aqua = make_mat("drop", (0.18, 0.68, 0.98), roughness=0.18, emission=0.35)
    add_sphere((0, 0, 0.18), 0.34, aqua)
    add_cone((0, 0, 0.50), 0.30, 0.0, 0.46, aqua)


def icon_stat_traffic():
    add_plinth((0.46, 0.50, 0.58), size=(1.05, 1.05, 0.12))
    import_glb("kenney/cars/sedan-sports", (0.0, 0.0, 0.02), scale=0.38, rot_z=math.radians(-35))


def icon_menu_crest():
    add_plinth((0.32, 0.70, 0.38), size=(1.55, 1.55, 0.18))
    import_glb("kenney/commercial/building-skyscraper-b", (-0.18, 0.18, 0.0), scale=0.85)
    import_glb("blender/panel-b", (0.26, 0.18, 0.0), scale=0.62)
    import_glb("kenney/suburban/building-type-b", (-0.24, -0.26, 0.0), scale=0.95)
    import_glb("kenney/suburban/tree-large", (0.30, -0.28, 0.0), scale=1.05)


ICONS = [
    ("tool_road", icon_tool_road, 96, 1.15),
    ("tool_avenue", icon_tool_avenue, 96, 1.15),
    ("tool_highway", icon_tool_highway, 96, 1.15),
    ("tool_zone_r", icon_zone_r, 96, 1.15),
    ("tool_zone_c", icon_zone_c, 96, 1.15),
    ("tool_zone_i", icon_zone_i, 96, 1.15),
    ("tool_dezone", icon_dezone, 96, 1.18),
    ("tool_zone_r_high", icon_zone_r_high, 96, 1.12),
    ("tool_zone_c_high", icon_zone_c_high, 96, 1.12),
    ("tool_zone_o", icon_zone_o, 96, 1.12),
    ("power_plant_01", icon_power_plant, 96, 1.14),
    ("water_tower_01", icon_water_tower, 96, 1.14),
    ("wind_turbine_01", icon_wind_small, 96, 1.10),
    ("wind_turbine_02", icon_wind_large, 96, 1.12),
    ("school_01", icon_school, 96, 1.15),
    ("health_01", icon_health, 96, 1.14),
    ("health_02", icon_health_large, 96, 1.10),
    ("fire_01", icon_fire, 96, 1.14),
    ("fire_02", icon_fire_large, 96, 1.10),
    ("police_01", icon_police, 96, 1.14),
    ("police_02", icon_police_large, 96, 1.10),
    ("park_square", icon_park_square, 96, 1.15),
    ("park_garden", icon_park_garden, 96, 1.15),
    ("park_plaza", icon_park_plaza, 96, 1.15),
    ("tool_bulldoze", icon_bulldoze, 96, 1.15),
    ("tool_overlay", icon_overlay, 96, 1.18),
    ("stat_money", icon_stat_money, 64, 1.18),
    ("stat_pop", icon_stat_pop, 64, 1.15),
    ("stat_rank", icon_stat_rank, 64, 1.18),
    ("stat_jobs", icon_stat_jobs, 64, 1.18),
    ("stat_power", icon_stat_power, 64, 1.18),
    ("stat_water", icon_stat_water, 64, 1.18),
    ("stat_traffic", icon_stat_traffic, 64, 1.15),
    ("menu_crest", icon_menu_crest, 144, 1.12),
]

# Только некоторые иконки: ICONS_ONLY="wind_turbine_01,wind_turbine_02" (остальные не перерисовываются).
ONLY = set(filter(None, os.environ.get("ICONS_ONLY", "").split(",")))
for icon_name, fn, px, pad in ICONS:
    if not ONLY or icon_name in ONLY:
        render_icon(icon_name, fn, size_px=px, padding=pad)
