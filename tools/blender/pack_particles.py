"""Генератор низкополигональных 3D-партиклов и визуальных эффектов (VFX) для CityBuilder.

Создаёт:
1) 20 готовых составных 3D-эффектов (шлейфы дыма из труб, пар градирен, аромат кофеен,
   огонь пожаров, газовый факел НПЗ, сварочные искры стройки, облака пыли при сносе бульдозером,
   строительная пыль, выхлоп машин, струи фонтанов, пожарный брандспойт, круги на воде,
   кружащаяся листва, стайка птиц, дождь, снегопад, праздничный салют конфетти и звёзд Level-Up).
2) 12 одиночных 3D-элементов (units/*.glb) для GPUParticles3D / CPUParticles3D / MultiMesh.

Конвенции для Godot 4:
- Начало координат (0, 0, 0) — точка эмиссии (верх трубы, форсунка фонтана, центр участка).
- В Blender ось высоты +Z -> при экспорте glTF (export_yup=True) превращается в +Y в Godot.
- Направление сноса ветром / струи по умолчанию: +X (или вдоль -Y Blender -> +Z/-Z Godot).
- В каждом составном эффекте в UV (TEXCOORD_0) каждого элемента записаны:
    UV.x = t (фаза 0.0..1.0 от точки выброса до верхушки/края эффекта),
    UV.y = seed (индивидуальное случайное зерно 0.0..1.0 элемента),
  а в UV2 (TEXCOORD_1):
    UV2.x, UV2.y = нормализованный вектор радиального смещения (dx, dy) от оси.
  Это позволяет анимировать весь шлейф дыма/фонтана/огня одним вызовом отрисовки в MultiMeshInstance3D
  через вершинный шейдер (подъём, покачивание по ветру и пульсация вдоль NORMAL).
"""

import math
import random
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# --- Палитра цветов эффектов (sRGB) ---
STEAM_PURE = (0.97, 0.98, 1.00)
SMOKE_WHITE = (0.91, 0.93, 0.96)
SMOKE_LIGHT = (0.78, 0.81, 0.85)
SMOKE_MID = (0.60, 0.63, 0.68)
SMOKE_DARK = (0.39, 0.41, 0.45)
SMOKE_SOOT = (0.25, 0.27, 0.30)
SMOKE_CHARCOAL = (0.17, 0.18, 0.21)

AROMA_CREAM = (0.99, 0.95, 0.87)
AROMA_GOLD = (0.96, 0.80, 0.46)
COFFEE_BEAN = (0.45, 0.28, 0.17)

FIRE_WHITE = (1.00, 0.97, 0.72)
FIRE_YELLOW = (1.00, 0.80, 0.14)
FIRE_ORANGE = (0.98, 0.46, 0.10)
FIRE_RED = (0.88, 0.21, 0.14)
ARC_CYAN = (0.52, 0.90, 1.00)

DUST_CREAM = (0.87, 0.81, 0.71)
DUST_SAND = (0.76, 0.68, 0.56)
DUST_EARTH = (0.62, 0.54, 0.44)
RUBBLE_BRICK = (0.78, 0.36, 0.25)
RUBBLE_CONCRETE = (0.64, 0.65, 0.63)
RUBBLE_WOOD = (0.76, 0.55, 0.32)

WATER_FOAM = (0.95, 0.99, 1.00)
WATER_LIGHT = (0.54, 0.86, 0.99)
WATER_AZURE = (0.22, 0.67, 0.95)
WATER_DEEP = (0.14, 0.49, 0.84)
RAIN_CLOUD = (0.46, 0.53, 0.64)

LEAF_LIME = (0.54, 0.82, 0.28)
LEAF_GREEN = (0.30, 0.65, 0.26)
LEAF_GOLD = (0.97, 0.76, 0.16)
LEAF_AUTUMN = (0.91, 0.43, 0.17)

BIRD_WHITE = (0.96, 0.97, 0.99)
BIRD_GREY = (0.55, 0.60, 0.66)
BIRD_DARK = (0.32, 0.36, 0.42)
BIRD_BEAK = (0.96, 0.68, 0.14)

SNOW_PURE = (0.96, 0.98, 1.00)
SNOW_ICE = (0.78, 0.91, 1.00)

STAR_GOLD = (1.00, 0.82, 0.12)
STAR_WARM = (1.00, 0.64, 0.14)
CONFETTI_RED = (0.94, 0.28, 0.34)
CONFETTI_PINK = (0.95, 0.36, 0.66)
CONFETTI_BLUE = (0.22, 0.72, 0.98)
CONFETTI_GREEN = (0.28, 0.82, 0.46)
CONFETTI_PURPLE = (0.66, 0.38, 0.94)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


class ParticleBuilder:
    """Процедурный построитель лоу-поли геометрии партиклов с записью фазы и зерна в UV/UV2."""

    def __init__(self, name: str):
        self.name = name
        self._mats = {}
        self._parts = []  # Список кортежей (bm, mat_key, mat_obj)

    def mat(self, key: str, srgb, roughness=0.65, metallic=0.0, emission_strength=0.0):
        if key not in self._mats:
            m = bpy.data.materials.new(f"{self.name}_{key}")
            m.use_nodes = True
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            lin = srgb_to_linear(srgb)
            bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
            bsdf.inputs["Roughness"].default_value = roughness
            bsdf.inputs["Metallic"].default_value = metallic
            if emission_strength > 0.0:
                if "Emission Color" in bsdf.inputs:
                    bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
                if "Emission Strength" in bsdf.inputs:
                    bsdf.inputs["Emission Strength"].default_value = emission_strength
            self._mats[key] = m
        return self._mats[key]

    def _tag_bm(self, bm: bmesh.types.BMesh, t_phase: float, seed: float, dir_xy=(0.0, 0.0)):
        uv_lay = bm.loops.layers.uv.new("UVMap")
        uv2_lay = bm.loops.layers.uv.new("UV2")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        u1 = (max(0.0, min(1.0, float(t_phase))), max(0.0, min(1.0, float(seed))))
        u2 = (float(dir_xy[0]), float(dir_xy[1]))
        for f in bm.faces:
            f.smooth = False
            for loop in f.loops:
                loop[uv_lay].uv = u1
                loop[uv2_lay].uv = u2

    def _add_bm(self, bm: bmesh.types.BMesh, mat_key: str, srgb, roughness=0.65,
                metallic=0.0, emission=0.0, t_phase=0.0, seed=0.0, dir_xy=(0.0, 0.0)):
        self._tag_bm(bm, t_phase, seed, dir_xy)
        mat_obj = self.mat(mat_key, srgb, roughness=roughness, metallic=metallic, emission_strength=emission)
        self._parts.append((bm, mat_key, mat_obj))

    def icosphere_puff(self, center, radius, scale_xyz=(1.0, 1.0, 0.85), subdivisions=1,
                       jitter=0.08, rot_euler=(0.0, 0.0, 0.0), mat_key="puff", srgb=SMOKE_LIGHT,
                       roughness=0.82, emission=0.0, t_phase=0.5, seed=0.1, dir_xy=(0.0, 0.0)):
        """Одиночный гранёный клуб дыма/пара/пыли на базе икосаэдра с органической деформацией."""
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
        rng = random.Random(int(seed * 100000) + 17)
        sx, sy, sz = scale_xyz
        rot_m = Euler(rot_euler, "XYZ").to_matrix()
        cx, cy, cz = center
        for v in bm.verts:
            nx, ny, nz = v.co.normalized()
            jag = 1.0 + (rng.random() - 0.5) * 2.0 * jitter
            p = Vector((v.co.x * sx * jag, v.co.y * sy * jag, v.co.z * sz * jag))
            p = rot_m @ p
            v.co = Vector((cx + p.x, cy + p.y, cz + p.z))
        self._add_bm(bm, mat_key, srgb, roughness=roughness, emission=emission,
                     t_phase=t_phase, seed=seed, dir_xy=dir_xy)

    def compound_puff(self, center, radius, lobes=3, scale_z=0.82, subdivisions=1,
                      mat_key="puff", srgb=SMOKE_LIGHT, roughness=0.82, emission=0.0,
                      t_phase=0.5, seed=0.1, dir_xy=(0.0, 0.0)):
        """Пышный кучевой клуб из центральной сферы и нескольких боковых долей под общим seed/t_phase."""
        rng = random.Random(int(seed * 100000) + 53)
        cx, cy, cz = center
        # Главная доля
        self.icosphere_puff(
            (cx, cy, cz), radius,
            scale_xyz=(1.05, 0.98, scale_z),
            subdivisions=subdivisions, jitter=0.07,
            rot_euler=(rng.uniform(0, 3.14), rng.uniform(0, 3.14), rng.uniform(0, 3.14)),
            mat_key=mat_key, srgb=srgb, roughness=roughness, emission=emission,
            t_phase=t_phase, seed=seed, dir_xy=dir_xy
        )
        # Боковые доли (с тем же t_phase и seed, чтобы в шейдере двигались как единый кучевой клуб)
        base_ang = rng.uniform(0.0, math.tau)
        for i in range(lobes):
            ang = base_ang + i * (math.tau / max(1, lobes)) + rng.uniform(-0.35, 0.35)
            dist = radius * rng.uniform(0.45, 0.66)
            lr = radius * rng.uniform(0.56, 0.74)
            dz = radius * rng.uniform(-0.16, 0.20)
            self.icosphere_puff(
                (cx + math.cos(ang) * dist, cy + math.sin(ang) * dist, cz + dz),
                lr,
                scale_xyz=(1.0, 1.0, scale_z * 0.95),
                subdivisions=subdivisions, jitter=0.06,
                rot_euler=(rng.uniform(0, 3.14), rng.uniform(0, 3.14), rng.uniform(0, 3.14)),
                mat_key=mat_key, srgb=srgb, roughness=roughness, emission=emission,
                t_phase=t_phase, seed=seed, dir_xy=dir_xy
            )

    def flame_tongue(self, base_xyz, height, r_base, lean_xy=(0.0, 0.0), twist=0.5, sides=6,
                     mat_key="flame", srgb=FIRE_ORANGE, emission=0.45, t_phase=0.3, seed=0.2):
        """Гранёный изогнутый язык пламени от base_xyz вверх на height."""
        bm = bmesh.new()
        bx, by, bz = base_xyz
        lx, ly = lean_xy
        rings = 4
        ring_verts = []
        for r_idx in range(rings):
            u = r_idx / float(rings)
            # Профиль пламени: расширяется чуть выше базы и сужается к острию
            rad = r_base * math.sin((1.0 - u * 0.88) * math.pi * 0.68)
            z = bz + height * u
            ox = lx * (u ** 1.4)
            oy = ly * (u ** 1.4)
            ang0 = twist * u + seed * math.tau
            verts = []
            for s in range(sides):
                a = ang0 + s * (math.tau / sides)
                # Лёгкая гранёная асимметрия
                r_mod = rad * (1.0 + 0.14 * math.sin(s * 2.0 + r_idx))
                verts.append(bm.verts.new((bx + ox + math.cos(a) * r_mod,
                                           by + oy + math.sin(a) * r_mod, z)))
            ring_verts.append(verts)
        # Нижняя крышка
        bm.faces.new(list(reversed(ring_verts[0])))
        # Боковые грани между кольцами
        for r_idx in range(rings - 1):
            r0 = ring_verts[r_idx]
            r1 = ring_verts[r_idx + 1]
            for s in range(sides):
                sn = (s + 1) % sides
                bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))
        # Острая вершина языка пламени
        tip = bm.verts.new((bx + lx, by + ly, bz + height))
        top_ring = ring_verts[-1]
        for s in range(sides):
            sn = (s + 1) % sides
            bm.faces.new((top_ring[s], top_ring[sn], tip))
        self._add_bm(bm, mat_key, srgb, roughness=0.35, emission=emission,
                     t_phase=t_phase, seed=seed, dir_xy=lean_xy)

    def spark_crystal(self, center, direction, length, radius, mat_key="spark",
                      srgb=FIRE_YELLOW, emission=0.7, t_phase=0.5, seed=0.1):
        """Октаэдрическая вытянутая вдоль direction искра / дождевой штрих."""
        bm = bmesh.new()
        d = Vector(direction)
        if d.length < 1e-5:
            d = Vector((0.0, 0.0, 1.0))
        d.normalize()
        up = Vector((0.0, 1.0, 0.0)) if abs(d.z) > 0.9 else Vector((0.0, 0.0, 1.0))
        side1 = d.cross(up).normalized() * radius
        side2 = d.cross(side1).normalized() * radius
        c = Vector(center)
        tail = c - d * (length * 0.55)
        head = c + d * (length * 0.45)
        mid = c + d * (length * 0.08)
        v_tail = bm.verts.new(tail)
        v_head = bm.verts.new(head)
        ring = [
            bm.verts.new(mid + side1),
            bm.verts.new(mid + side2),
            bm.verts.new(mid - side1),
            bm.verts.new(mid - side2),
        ]
        for i in range(4):
            jn = (i + 1) % 4
            bm.faces.new((v_tail, ring[jn], ring[i]))
            bm.faces.new((ring[i], ring[jn], v_head))
        self._add_bm(bm, mat_key, srgb, roughness=0.25, emission=emission,
                     t_phase=t_phase, seed=seed, dir_xy=(d.x, d.y))

    def water_drop(self, center, direction, length, radius, mat_key="water",
                   srgb=WATER_AZURE, roughness=0.22, t_phase=0.5, seed=0.1):
        """Объёмная гранёная капля воды (округлая головка по направлению полёта и острый хвостик)."""
        bm = bmesh.new()
        d = Vector(direction)
        if d.length < 1e-5:
            d = Vector((0.0, 0.0, 1.0))
        d.normalize()
        up = Vector((0.0, 1.0, 0.0)) if abs(d.z) > 0.9 else Vector((0.0, 0.0, 1.0))
        u_ax = d.cross(up).normalized()
        v_ax = d.cross(u_ax).normalized()
        c = Vector(center)
        sides = 6
        # Хвостик (-0.55*L), широкое кольцо (+0.10*L), скруглённый носик (+0.32*L), вершина (+0.45*L)
        v_tail = bm.verts.new(c - d * (length * 0.55))
        v_nose = bm.verts.new(c + d * (length * 0.45))
        r_mid = []
        r_front = []
        for s in range(sides):
            a = s * (math.tau / sides)
            radial = u_ax * math.cos(a) + v_ax * math.sin(a)
            r_mid.append(bm.verts.new(c + d * (length * 0.06) + radial * radius))
            r_front.append(bm.verts.new(c + d * (length * 0.30) + radial * (radius * 0.65)))
        for s in range(sides):
            sn = (s + 1) % sides
            bm.faces.new((v_tail, r_mid[sn], r_mid[s]))
            bm.faces.new((r_mid[s], r_mid[sn], r_front[sn], r_front[s]))
            bm.faces.new((r_front[s], r_front[sn], v_nose))
        self._add_bm(bm, mat_key, srgb, roughness=roughness,
                     t_phase=t_phase, seed=seed, dir_xy=(d.x, d.y))

    def ripple_ring(self, center_xyz, r_inner, r_outer, height=0.035, segments=16,
                    mat_key="ripple", srgb=WATER_FOAM, roughness=0.25, t_phase=0.5, seed=0.1):
        """Концентрическое гранёное кольцо волны на воде."""
        bm = bmesh.new()
        cx, cy, cz = center_xyz
        r_mid = (r_inner + r_outer) * 0.5
        ring_in = []
        ring_top = []
        ring_out = []
        for i in range(segments):
            a = i * (math.tau / segments)
            ca, sa = math.cos(a), math.sin(a)
            ring_in.append(bm.verts.new((cx + ca * r_inner, cy + sa * r_inner, cz)))
            ring_top.append(bm.verts.new((cx + ca * r_mid, cy + sa * r_mid, cz + height)))
            ring_out.append(bm.verts.new((cx + ca * r_outer, cy + sa * r_outer, cz)))
        for i in range(segments):
            jn = (i + 1) % segments
            bm.faces.new((ring_in[i], ring_top[i], ring_top[jn], ring_in[jn]))
            bm.faces.new((ring_top[i], ring_out[i], ring_out[jn], ring_top[jn]))
            bm.faces.new((ring_out[i], ring_in[i], ring_in[jn], ring_out[jn]))
        self._add_bm(bm, mat_key, srgb, roughness=roughness,
                     t_phase=t_phase, seed=seed, dir_xy=(0.0, 0.0))

    def rubble_chunk(self, center, size_xyz, rot_euler, bevel_jitter=0.12,
                     mat_key="rubble", srgb=RUBBLE_BRICK, roughness=0.88, t_phase=0.5, seed=0.1, dir_xy=(0.0, 0.0)):
        """Гранёный обломок кирпича / бетона / доски при сносе здания."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        rng = random.Random(int(seed * 100000) + 99)
        sx, sy, sz = size_xyz
        rot_m = Euler(rot_euler, "XYZ").to_matrix()
        cx, cy, cz = center
        for v in bm.verts:
            jx = 1.0 + (rng.random() - 0.5) * bevel_jitter
            jy = 1.0 + (rng.random() - 0.5) * bevel_jitter
            jz = 1.0 + (rng.random() - 0.5) * bevel_jitter
            p = Vector((v.co.x * sx * jx, v.co.y * sy * jy, v.co.z * sz * jz))
            p = rot_m @ p
            v.co = Vector((cx + p.x, cy + p.y, cz + p.z))
        self._add_bm(bm, mat_key, srgb, roughness=roughness,
                     t_phase=t_phase, seed=seed, dir_xy=dir_xy)

    def leaf_3d(self, center, length, width, thickness, rot_euler,
                mat_key="leaf", srgb=LEAF_GREEN, t_phase=0.5, seed=0.1, dir_xy=(0.0, 0.0)):
        """Объёмный лоу-поли древесный листок с V-образным изгибом по прожилке."""
        bm = bmesh.new()
        hl = length * 0.5
        hw = width * 0.5
        ht = thickness * 0.5
        fold = width * 0.14
        # Контур ромбовидно-миндалевидного листа
        pts_top = [
            Vector((0.0, -hl, ht)),                     # черешок
            Vector((-hw * 0.75, -hl * 0.25, ht + fold)),
            Vector((-hw, hl * 0.15, ht + fold)),
            Vector((-hw * 0.55, hl * 0.65, ht + fold * 0.6)),
            Vector((0.0, hl, ht)),                      # кончик листа
            Vector((hw * 0.55, hl * 0.65, ht + fold * 0.6)),
            Vector((hw, hl * 0.15, ht + fold)),
            Vector((hw * 0.75, -hl * 0.25, ht + fold)),
            Vector((0.0, 0.0, ht * 1.3)),               # центр жилки сверху
        ]
        pts_bot = [Vector((p.x, p.y, p.z - thickness)) for p in pts_top]
        rot_m = Euler(rot_euler, "XYZ").to_matrix()
        c = Vector(center)
        v_top = [bm.verts.new(c + (rot_m @ p)) for p in pts_top]
        v_bot = [bm.verts.new(c + (rot_m @ p)) for p in pts_bot]
        c_top = v_top[8]
        c_bot = v_bot[8]
        for i in range(8):
            jn = (i + 1) % 8
            bm.faces.new((c_top, v_top[i], v_top[jn]))
            bm.faces.new((c_bot, v_bot[jn], v_bot[i]))
            bm.faces.new((v_top[i], v_bot[i], v_bot[jn], v_top[jn]))
        self._add_bm(bm, mat_key, srgb, roughness=0.62,
                     t_phase=t_phase, seed=seed, dir_xy=dir_xy)

    def bird_3d(self, center, wingspan=0.45, flap_angle=0.28, yaw=0.0, pitch=0.08, bank=0.15,
                mat_body="bird_body", srgb_body=BIRD_WHITE,
                mat_wing="bird_wing", srgb_wing=BIRD_GREY,
                t_phase=0.5, seed=0.1):
        """Лоу-поли птица в полёте (корпус с хвостом + два крыла с изгибом чайки)."""
        rot_m = Euler((pitch, bank, yaw), "XYZ").to_matrix()
        c = Vector(center)

        def tr(pt):
            return c + (rot_m @ Vector(pt))

        # 1) Корпус и хвост
        bm_b = bmesh.new()
        bl = wingspan * 0.48
        bw = wingspan * 0.09
        bh = wingspan * 0.075
        v_beak = bm_b.verts.new(tr((0.0, -bl * 0.62, 0.0)))
        v_tail_l = bm_b.verts.new(tr((-bw * 0.85, bl * 0.58, bh * 0.2)))
        v_tail_r = bm_b.verts.new(tr((bw * 0.85, bl * 0.58, bh * 0.2)))
        v_top = bm_b.verts.new(tr((0.0, -bl * 0.05, bh)))
        v_bot = bm_b.verts.new(tr((0.0, -bl * 0.05, -bh)))
        v_l = bm_b.verts.new(tr((-bw, -bl * 0.08, 0.0)))
        v_r = bm_b.verts.new(tr((bw, -bl * 0.08, 0.0)))
        bm_b.faces.new((v_beak, v_r, v_top))
        bm_b.faces.new((v_beak, v_top, v_l))
        bm_b.faces.new((v_beak, v_bot, v_r))
        bm_b.faces.new((v_beak, v_l, v_bot))
        bm_b.faces.new((v_top, v_r, v_tail_r, v_tail_l, v_l))
        bm_b.faces.new((v_bot, v_l, v_tail_l, v_tail_r, v_r))
        self._add_bm(bm_b, mat_body, srgb_body, roughness=0.55,
                     t_phase=t_phase, seed=seed, dir_xy=(math.sin(yaw), -math.cos(yaw)))

        # 2) Объёмные крылья с взмахом flap_angle (верхняя и нижняя грань с толщиной thick)
        bm_w = bmesh.new()
        half_w = wingspan * 0.5
        mid_w = half_w * 0.52
        z_mid = math.sin(flap_angle) * mid_w
        z_tip = math.sin(flap_angle * 1.25) * half_w
        thick = wingspan * 0.032
        for sign in (-1.0, 1.0):
            rf_t = bm_w.verts.new(tr((sign * bw * 0.55, -bl * 0.22, thick * 0.6)))
            rf_b = bm_w.verts.new(tr((sign * bw * 0.55, -bl * 0.22, -thick * 0.6)))
            rb_t = bm_w.verts.new(tr((sign * bw * 0.55, bl * 0.14, thick * 0.4)))
            rb_b = bm_w.verts.new(tr((sign * bw * 0.55, bl * 0.14, -thick * 0.4)))
            ef_t = bm_w.verts.new(tr((sign * mid_w, -bl * 0.16, z_mid + thick * 0.5)))
            ef_b = bm_w.verts.new(tr((sign * mid_w, -bl * 0.16, z_mid - thick * 0.5)))
            eb_t = bm_w.verts.new(tr((sign * mid_w, bl * 0.12, z_mid + thick * 0.3)))
            eb_b = bm_w.verts.new(tr((sign * mid_w, bl * 0.12, z_mid - thick * 0.3)))
            tip = bm_w.verts.new(tr((sign * half_w, bl * 0.08, z_tip)))
            if sign > 0:
                bm_w.faces.new((rf_t, ef_t, eb_t, rb_t))
                bm_w.faces.new((rb_b, eb_b, ef_b, rf_b))
                bm_w.faces.new((ef_t, tip, eb_t))
                bm_w.faces.new((eb_b, tip, ef_b))
            else:
                bm_w.faces.new((rb_t, eb_t, ef_t, rf_t))
                bm_w.faces.new((rf_b, ef_b, eb_b, rb_b))
                bm_w.faces.new((eb_t, tip, ef_t))
                bm_w.faces.new((ef_b, tip, eb_b))
        self._add_bm(bm_w, mat_wing, srgb_wing, roughness=0.60,
                     t_phase=t_phase, seed=seed, dir_xy=(math.sin(yaw), -math.cos(yaw)))

    def star_3d(self, center, r_outer, r_inner, thickness, rot_euler=(0.0, 0.0, 0.0),
                points=5, mat_key="star", srgb=STAR_GOLD, emission=0.35, t_phase=0.5, seed=0.1):
        """Объёмная гранёная 5-конечная звезда (для Level-Up и эмоций счастья)."""
        bm = bmesh.new()
        rot_m = Euler(rot_euler, "XYZ").to_matrix()
        c = Vector(center)
        v_front = bm.verts.new(c + (rot_m @ Vector((0.0, 0.0, thickness * 0.5))))
        v_back = bm.verts.new(c + (rot_m @ Vector((0.0, 0.0, -thickness * 0.5))))
        ring = []
        total = points * 2
        for i in range(total):
            a = i * (math.tau / total) + math.pi * 0.5
            r = r_outer if (i % 2 == 0) else r_inner
            p = Vector((math.cos(a) * r, 0.0, math.sin(a) * r))
            # Повернём звезду вертикально лицом к -Y, затем применим rot_euler
            p_local = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
            ring.append(bm.verts.new(c + (rot_m @ p_local)))
        for i in range(total):
            jn = (i + 1) % total
            bm.faces.new((v_front, ring[i], ring[jn]))
            bm.faces.new((v_back, ring[jn], ring[i]))
        self._add_bm(bm, mat_key, srgb, roughness=0.28, metallic=0.15, emission=emission,
                     t_phase=t_phase, seed=seed)

    def snowflake_3d(self, center, radius, thickness, rot_euler=(0.0, 0.0, 0.0),
                     mat_key="snow", srgb=SNOW_PURE, t_phase=0.5, seed=0.1):
        """Объёмная шестилучевая снежинка из 3 пересекающихся кристаллов-лучей."""
        rot_m = Euler(rot_euler, "XYZ").to_matrix()
        c = Vector(center)
        bm = bmesh.new()
        for arm in range(3):
            ang = arm * (math.pi / 3.0)
            arm_m = rot_m @ Euler((0.0, 0.0, ang), "XYZ").to_matrix()
            b_tmp = bmesh.new()
            bmesh.ops.create_cube(b_tmp, size=1.0)
            for v in b_tmp.verts:
                p = Vector((v.co.x * radius * 2.0, v.co.y * (radius * 0.22), v.co.z * thickness))
                v.co = c + (arm_m @ p)
            # Переносим в общий bm
            v_map = [bm.verts.new(v.co) for v in b_tmp.verts]
            for f in b_tmp.faces:
                bm.faces.new([v_map[v.index] for v in f.verts])
            b_tmp.free()
        self._add_bm(bm, mat_key, srgb, roughness=0.35, t_phase=t_phase, seed=seed)

    def confetti_tile(self, center, width, length, thickness, rot_euler,
                      mat_key="confetti", srgb=CONFETTI_RED, t_phase=0.5, seed=0.1):
        """Праздничная пластинка конфетти."""
        self.rubble_chunk(center, (width, length, thickness), rot_euler, bevel_jitter=0.04,
                          mat_key=mat_key, srgb=srgb, roughness=0.35, t_phase=t_phase, seed=seed)

    def spiral_ribbon(self, z0, z1, r0, r1, turns=1.4, phase0=0.0, width=0.075, thick=0.025,
                      steps=14, mat_key="aroma", srgb=AROMA_CREAM, seed=0.2):
        """Изящная спиральная 3D-лента горячего пара/аромата кофе."""
        for i in range(steps):
            u0 = i / float(steps)
            u1 = (i + 1) / float(steps)
            um = (u0 + u1) * 0.5
            bm = bmesh.new()
            ring_pair = []
            for u in (u0, u1):
                ang = phase0 + u * turns * math.tau
                rad = r0 + (r1 - r0) * u
                w = width * math.sin(max(0.08, min(0.95, u)) * math.pi)
                cx = math.cos(ang) * rad
                cy = math.sin(ang) * rad
                cz = z0 + (z1 - z0) * u
                nx, ny = math.cos(ang), math.sin(ang)
                ring_pair_verts = [
                    bm.verts.new((cx - nx * w * 0.5, cy - ny * w * 0.5, cz - thick * 0.5)),
                    bm.verts.new((cx + nx * w * 0.5, cy + ny * w * 0.5, cz - thick * 0.5)),
                    bm.verts.new((cx + nx * w * 0.5, cy + ny * w * 0.5, cz + thick * 0.5)),
                    bm.verts.new((cx - nx * w * 0.5, cy - ny * w * 0.5, cz + thick * 0.5)),
                ]
                ring_pair.append(ring_pair_verts)
            r_a, r_b = ring_pair[0], ring_pair[1]
            bm.faces.new(list(reversed(r_a)))
            bm.faces.new(r_b)
            for k in range(4):
                kn = (k + 1) % 4
                bm.faces.new((r_a[k], r_a[kn], r_b[kn], r_b[k]))
            self._add_bm(bm, mat_key, srgb, roughness=0.65,
                         t_phase=um, seed=(seed + i * 0.07) % 1.0,
                         dir_xy=(math.cos(phase0 + um * turns * math.tau), math.sin(phase0 + um * turns * math.tau)))

    def finalize(self):
        """Собирает все части по материалам в чистые Mesh-объекты Blender."""
        by_mat = {}
        for bm, mat_key, mat_obj in self._parts:
            by_mat.setdefault(mat_key, [mat_obj, []])[1].append(bm)

        created = []
        for mat_key, (mat_obj, bms) in by_mat.items():
            merged = bmesh.new()
            uv_lay = merged.loops.layers.uv.new("UVMap")
            uv2_lay = merged.loops.layers.uv.new("UV2")
            for src in bms:
                src_uv = src.loops.layers.uv.get("UVMap")
                src_uv2 = src.loops.layers.uv.get("UV2")
                v_map = [merged.verts.new(v.co) for v in src.verts]
                for f in src.faces:
                    nf = merged.faces.new([v_map[v.index] for v in f.verts])
                    nf.smooth = False
                    for dst_l, src_l in zip(nf.loops, f.loops):
                        if src_uv is not None:
                            dst_l[uv_lay].uv = src_l[src_uv].uv
                        if src_uv2 is not None:
                            dst_l[uv2_lay].uv = src_l[src_uv2].uv
                src.free()
            bmesh.ops.recalc_face_normals(merged, faces=merged.faces)
            mesh = bpy.data.meshes.new(f"{self.name}_{mat_key}")
            merged.to_mesh(mesh)
            merged.free()
            for poly in mesh.polygons:
                poly.use_smooth = False
            obj = bpy.data.objects.new(f"{self.name}_{mat_key}", mesh)
            bpy.context.collection.objects.link(obj)
            obj.data.materials.append(mat_obj)
            created.append(obj)
        self._parts.clear()
        return created


# ===========================================================================
# 1. СОСТАВНЫЕ 3D-ЭФФЕКТЫ И ШЛЕЙФЫ (20 МОДЕЛЕЙ В assets/models/blender/particles/)
# ===========================================================================

def build_fx_smoke_chimney_light():
    """1. Лёгкий белый/светло-серый печной дым для жилых домов, пекарен и пиццерий."""
    clear_scene()
    b = ParticleBuilder("fx_smoke_chimney_light")
    steps = 9
    for i in range(steps):
        t = (i + 0.5) / steps
        seed = (i * 0.37 + 0.13) % 1.0
        # Струя поднимается вверх до 1.45 м и плавно сносится ветром по +X
        drift_x = 0.48 * (t ** 1.35) + math.sin(i * 1.4) * 0.05
        drift_y = math.cos(i * 1.2) * 0.05 * t
        z = 0.06 + t * 1.38
        rad = 0.085 + 0.14 * math.sin(t * math.pi * 0.85)
        if t < 0.34:
            mk, col = "smoke_warm", SMOKE_LIGHT
        elif t < 0.72:
            mk, col = "smoke_white", SMOKE_WHITE
        else:
            mk, col = "smoke_pure", STEAM_PURE
        b.compound_puff((drift_x, drift_y, z), rad, lobes=2, scale_z=0.84,
                        mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(1.0, 0.0))
    b.finalize()
    return b


def build_fx_smoke_factory_heavy():
    """2. Густой тёмный заводской дым и смог для труб промзоны и ТЭЦ."""
    clear_scene()
    b = ParticleBuilder("fx_smoke_factory_heavy")
    # Отблеск жара у самого устья трубы
    b.icosphere_puff((0.0, 0.0, 0.07), 0.13, scale_xyz=(1.1, 1.1, 0.75),
                     mat_key="ember_base", srgb=FIRE_ORANGE, emission=0.35, t_phase=0.04, seed=0.05)
    steps = 13
    for i in range(steps):
        t = (i + 0.6) / steps
        seed = (i * 0.41 + 0.19) % 1.0
        ang = i * 1.65
        spread = 0.14 * t
        drift_x = 1.25 * (t ** 1.38) + math.cos(ang) * spread * 0.5
        drift_y = math.sin(ang) * spread
        z = 0.12 + (t ** 0.88) * 2.25
        rad = 0.14 + 0.25 * math.sin(t * math.pi * 0.82)
        if t < 0.25:
            mk, col = "soot_core", SMOKE_CHARCOAL
        elif t < 0.58:
            mk, col = "smoke_soot", SMOKE_SOOT
        elif t < 0.84:
            mk, col = "smoke_dark", SMOKE_DARK
        else:
            mk, col = "smoke_mid", SMOKE_MID
        b.compound_puff((drift_x, drift_y, z), rad, lobes=3, scale_z=0.80,
                        mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(1.0, math.sin(ang) * 0.4))
    b.finalize()
    return b


def build_fx_smoke_twin_stacks():
    """3. Двойной шлейф заводских труб для крупных заводов и комбинатов."""
    clear_scene()
    b = ParticleBuilder("fx_smoke_twin_stacks")
    offsets = [(-0.28, -0.10, 0.0), (0.28, 0.10, 0.35)]
    for s_idx, (ox, oy, s_off) in enumerate(offsets):
        steps = 10
        for i in range(steps):
            t = (i + 0.5) / steps
            seed = (i * 0.33 + s_off) % 1.0
            # Два потока постепенно сближаются по мере подъёма
            merge_k = max(0.25, 1.0 - t * 0.65)
            x = ox * merge_k + 1.15 * (t ** 1.35)
            y = oy * merge_k + math.sin(i * 1.5 + s_idx * 2.0) * 0.10 * t
            z = 0.10 + (t ** 0.90) * 2.15
            rad = 0.12 + 0.21 * math.sin(t * math.pi * 0.84)
            if t < 0.30:
                mk, col = "soot", SMOKE_CHARCOAL
            elif t < 0.68:
                mk, col = "dark", SMOKE_SOOT
            else:
                mk, col = "mid", SMOKE_DARK
            b.compound_puff((x, y, z), rad, lobes=2, scale_z=0.82,
                            mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(1.0, 0.0))
    b.finalize()
    return b


def build_fx_steam_cooling_tower():
    """4. Широкий густой столб белоснежного пара градирни и котельной."""
    clear_scene()
    b = ParticleBuilder("fx_steam_cooling_tower")
    rings = [
        (0.12, 0.24, 5, 0.18),
        (0.42, 0.30, 5, 0.22),
        (0.78, 0.36, 5, 0.25),
        (1.18, 0.40, 4, 0.27),
        (1.60, 0.34, 3, 0.24),
        (1.96, 0.22, 2, 0.19),
    ]
    idx = 0
    for z, ring_r, count, puff_r in rings:
        t = min(1.0, z / 2.05)
        for k in range(count):
            idx += 1
            seed = (idx * 0.29 + 0.11) % 1.0
            a = k * (math.tau / count) + z * 1.4
            px = math.cos(a) * ring_r + 0.28 * (t ** 1.4)
            py = math.sin(a) * ring_r
            mk = "steam_pure" if t > 0.35 else "steam_base"
            col = STEAM_PURE if t > 0.35 else SMOKE_WHITE
            b.compound_puff((px, py, z), puff_r, lobes=2, scale_z=0.86,
                            mat_key=mk, srgb=col, roughness=0.75,
                            t_phase=t, seed=seed, dir_xy=(math.cos(a), math.sin(a)))
    b.finalize()
    return b


def build_fx_steam_vent_puff():
    """5. Компактная струйка пара из крышных вентиляций HVAC, прачечных и кухонь."""
    clear_scene()
    b = ParticleBuilder("fx_steam_vent_puff")
    steps = 7
    for i in range(steps):
        t = (i + 0.5) / steps
        seed = (i * 0.43 + 0.07) % 1.0
        x = 0.34 * (t ** 1.1)
        y = math.sin(i * 1.7) * 0.04 * t
        z = 0.05 + (t ** 0.85) * 0.88
        rad = 0.075 + 0.11 * math.sin(t * math.pi * 0.85)
        col = STEAM_PURE if t > 0.4 else SMOKE_WHITE
        mk = "steam_hi" if t > 0.4 else "steam_lo"
        b.compound_puff((x, y, z), rad, lobes=2, scale_z=0.82,
                        mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(1.0, 0.0))
    b.finalize()
    return b


def build_fx_cafe_aroma_swirl():
    """6. Спиральные завитки ароматного пара над чашками кофе на крышах кофеен и пекарен."""
    clear_scene()
    b = ParticleBuilder("fx_cafe_aroma_swirl")
    # Три изящные спиральные ленты пара
    b.spiral_ribbon(0.04, 1.02, 0.06, 0.20, turns=1.15, phase0=0.0, width=0.068,
                    mat_key="aroma_cream", srgb=AROMA_CREAM, seed=0.12)
    b.spiral_ribbon(0.08, 0.94, 0.05, 0.18, turns=1.10, phase0=2.09, width=0.058,
                    mat_key="aroma_white", srgb=STEAM_PURE, seed=0.45)
    b.spiral_ribbon(0.06, 0.86, 0.05, 0.16, turns=1.05, phase0=4.18, width=0.052,
                    mat_key="aroma_gold", srgb=AROMA_GOLD, seed=0.78)
    # Небольшие пушистые облачка и золотистые искорки аромата вдоль спирали
    for i in range(6):
        t = (i + 0.6) / 6.0
        ang = i * 1.35
        r = 0.08 + 0.12 * t
        b.icosphere_puff((math.cos(ang) * r, math.sin(ang) * r, 0.12 + t * 0.88),
                         0.065 * (1.1 - 0.3 * t), scale_xyz=(1.0, 1.0, 0.85),
                         mat_key="aroma_cream", srgb=AROMA_CREAM, t_phase=t, seed=(i * 0.27) % 1.0)
    b.finalize()
    return b


def build_fx_fire_building_blaze():
    """7. Пожар здания: языки пламени, разлетающиеся искры и густой чёрный дым сверху."""
    clear_scene()
    b = ParticleBuilder("fx_fire_building_blaze")
    # Центральное бело-жёлтое ядро пламени
    b.flame_tongue((0.0, 0.0, 0.0), 0.78, 0.22, lean_xy=(0.06, 0.0), twist=0.6,
                   mat_key="fire_core", srgb=FIRE_WHITE, emission=0.85, t_phase=0.18, seed=0.11)
    # Кольцо жёлто-оранжевых и алых языков пламени
    tongues = [
        ((-0.18, -0.10, 0.0), 0.92, 0.18, (0.10, -0.05), "fire_yellow", FIRE_YELLOW, 0.65, 0.25, 0.23),
        ((0.16, -0.12, 0.0), 0.86, 0.17, (0.14, -0.04), "fire_orange", FIRE_ORANGE, 0.55, 0.28, 0.37),
        ((0.04, 0.18, 0.0), 0.96, 0.19, (0.12, 0.06), "fire_yellow", FIRE_YELLOW, 0.65, 0.26, 0.51),
        ((-0.15, 0.14, 0.0), 0.76, 0.16, (0.04, 0.08), "fire_red", FIRE_RED, 0.45, 0.32, 0.64),
        ((0.22, 0.08, 0.0), 0.72, 0.15, (0.16, 0.04), "fire_red", FIRE_RED, 0.45, 0.34, 0.79),
    ]
    for pos, h, rb, lean, mk, col, em, tp, sd in tongues:
        b.flame_tongue(pos, h, rb, lean_xy=lean, twist=0.7, mat_key=mk, srgb=col, emission=em, t_phase=tp, seed=sd)
    # Клубы густого чёрно-бурого дыма над пламенем
    for i in range(8):
        t = 0.38 + (i / 8.0) * 0.62
        seed = (i * 0.31 + 0.15) % 1.0
        ang = i * 1.5
        px = 0.10 + (t - 0.35) * 0.65 + math.cos(ang) * 0.12
        py = math.sin(ang) * 0.14
        pz = 0.68 + (t - 0.35) * 2.25
        rad = 0.18 + 0.16 * math.sin((t - 0.35) * 1.5 * math.pi)
        mk = "fire_soot" if i < 5 else "fire_smoke"
        col = SMOKE_CHARCOAL if i < 5 else SMOKE_SOOT
        b.compound_puff((px, py, pz), rad, lobes=2, scale_z=0.82,
                        mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(1.0, 0.0))
    # Яркие угольки-искры вокруг пламени
    for i in range(8):
        a = i * (math.tau / 8.0) + 0.3
        r = 0.24 + (i % 3) * 0.08
        z = 0.35 + i * 0.14
        b.spark_crystal((math.cos(a) * r, math.sin(a) * r, z),
                        (math.cos(a) * 0.4, math.sin(a) * 0.4, 1.0),
                        0.16, 0.028, mat_key="fire_yellow", srgb=FIRE_YELLOW,
                        emission=0.8, t_phase=min(0.95, z / 1.8), seed=(i * 0.19) % 1.0)
    b.finalize()
    return b


def build_fx_fire_refinery_flare():
    """8. Газовый факел нефтеперерабатывающего завода / химпрома (Refinery Gas Flare)."""
    clear_scene()
    b = ParticleBuilder("fx_fire_refinery_flare")
    # Голубое газовое кольцо у сопла горелки
    b.icosphere_puff((0.0, 0.0, 0.06), 0.09, scale_xyz=(1.0, 1.0, 1.2),
                     mat_key="flare_blue", srgb=ARC_CYAN, emission=0.8, t_phase=0.05, seed=0.08)
    # Высокий факел пламени
    b.flame_tongue((0.0, 0.0, 0.04), 0.96, 0.16, lean_xy=(0.14, 0.0), twist=0.8,
                   mat_key="flare_core", srgb=FIRE_WHITE, emission=0.9, t_phase=0.35, seed=0.22)
    b.flame_tongue((-0.04, 0.03, 0.08), 1.08, 0.19, lean_xy=(0.20, 0.03), twist=-0.6,
                   mat_key="flare_orange", srgb=FIRE_ORANGE, emission=0.65, t_phase=0.50, seed=0.48)
    b.flame_tongue((0.05, -0.03, 0.12), 0.88, 0.15, lean_xy=(0.18, -0.04), twist=0.5,
                   mat_key="flare_red", srgb=FIRE_RED, emission=0.50, t_phase=0.62, seed=0.71)
    # Два небольших клуба тёмного дыма на самой верхушке факела
    for i, (z, r) in enumerate(((1.10, 0.11), (1.26, 0.09))):
        b.icosphere_puff((0.24 + i * 0.08, 0.0, z), r, scale_xyz=(1.1, 1.0, 0.8),
                         mat_key="flare_soot", srgb=SMOKE_CHARCOAL, t_phase=0.82 + i * 0.12, seed=0.3 + i * 0.3)
    b.finalize()
    return b


def build_fx_sparks_welding_burst():
    """9. Снопы сварочных искр и вспышка электродуги для стройплощадок и цехов."""
    clear_scene()
    b = ParticleBuilder("fx_sparks_welding_burst")
    # Яркая бело-голубая вспышка сварки в центре
    b.star_3d((0.0, 0.0, 0.06), 0.16, 0.06, 0.07, rot_euler=(0.2, 0.3, 0.0),
              points=6, mat_key="weld_arc", srgb=ARC_CYAN, emission=0.95, t_phase=0.05, seed=0.05)
    b.icosphere_puff((0.0, 0.0, 0.06), 0.08, mat_key="weld_white", srgb=FIRE_WHITE,
                     emission=1.0, t_phase=0.02, seed=0.12)
    # 18 разлетающихся по параболическим дугам искр
    num_arcs = 9
    for i in range(num_arcs):
        ang = i * (math.tau / num_arcs) + 0.25
        ca, sa = math.cos(ang), math.sin(ang)
        reach = 0.38 + (i % 3) * 0.12
        peak_z = 0.22 + (i % 2) * 0.12
        for step, u in enumerate((0.45, 0.85)):
            r = reach * u
            # Парабола: сначала вверх, затем дугой вниз
            z = 0.06 + peak_z * 4.0 * u * (1.0 - u * 0.85)
            dx = ca * reach
            dy = sa * reach
            dz = peak_z * 4.0 * (1.0 - 1.7 * u)
            mk = "spark_gold" if step == 0 else "spark_orange"
            col = FIRE_YELLOW if step == 0 else FIRE_ORANGE
            b.spark_crystal((ca * r, sa * r, z), (dx, dy, dz),
                            0.18 if step == 0 else 0.14, 0.026,
                            mat_key=mk, srgb=col, emission=0.85,
                            t_phase=u, seed=((i * 2 + step) * 0.17) % 1.0)
    b.finalize()
    return b


def build_fx_dust_bulldoze_burst():
    """10. Облако пыли и разлетающихся обломков при сносе здания бульдозером."""
    clear_scene()
    b = ParticleBuilder("fx_dust_bulldoze_burst")
    # Кольцо из 12 клубов цементно-песочной пыли у земли
    ring_count = 12
    for i in range(ring_count):
        ang = i * (math.tau / ring_count)
        ca, sa = math.cos(ang), math.sin(ang)
        t = 0.35 + (i % 3) * 0.22
        seed = (i * 0.29 + 0.09) % 1.0
        dist = 0.42 + (i % 3) * 0.16
        rad = 0.19 + (i % 2) * 0.06
        z = 0.14 + (i % 3) * 0.09
        if i % 3 == 0:
            mk, col = "dust_cream", DUST_CREAM
        elif i % 3 == 1:
            mk, col = "dust_sand", DUST_SAND
        else:
            mk, col = "dust_earth", DUST_EARTH
        b.compound_puff((ca * dist, sa * dist, z), rad, lobes=2, scale_z=0.72,
                        mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(ca, sa))
    # Центральное поднимающееся облако пыли
    b.compound_puff((0.0, 0.0, 0.34), 0.28, lobes=3, scale_z=0.78,
                    mat_key="dust_cream", srgb=DUST_CREAM, t_phase=0.55, seed=0.44, dir_xy=(0.0, 0.0))
    # Разлетающиеся кирпичики, куски бетона и досок
    debris = [
        ((0.46, -0.22, 0.42), (0.16, 0.08, 0.06), (0.5, 0.8, 0.3), "rubble_brick", RUBBLE_BRICK, 0.72),
        ((-0.44, 0.26, 0.46), (0.15, 0.08, 0.06), (1.1, 0.4, 1.2), "rubble_brick", RUBBLE_BRICK, 0.78),
        ((0.18, 0.48, 0.38), (0.14, 0.12, 0.10), (0.8, 1.3, 0.6), "rubble_conc", RUBBLE_CONCRETE, 0.68),
        ((-0.24, -0.45, 0.40), (0.13, 0.11, 0.09), (0.3, 0.9, 1.5), "rubble_conc", RUBBLE_CONCRETE, 0.74),
        ((0.35, 0.32, 0.52), (0.24, 0.06, 0.03), (0.7, 0.5, 0.9), "rubble_wood", RUBBLE_WOOD, 0.84),
        ((-0.36, -0.18, 0.50), (0.22, 0.06, 0.03), (1.2, 0.7, 0.2), "rubble_wood", RUBBLE_WOOD, 0.88),
    ]
    for idx, (pos, sz, rot, mk, col, tp) in enumerate(debris):
        v = Vector(pos)
        b.rubble_chunk(pos, sz, rot, mat_key=mk, srgb=col, t_phase=tp,
                       seed=(idx * 0.23 + 0.15) % 1.0, dir_xy=(v.x, v.y))
    b.finalize()
    return b


def build_fx_dust_construction_site():
    """11. Строительная пыль у фундамента и на стройплощадке."""
    clear_scene()
    b = ParticleBuilder("fx_dust_construction_site")
    pts = [
        (-0.52, -0.18, 0.12, 0.18, 0.25),
        (-0.24, 0.16, 0.16, 0.21, 0.42),
        (0.05, -0.12, 0.20, 0.23, 0.58),
        (0.32, 0.14, 0.15, 0.19, 0.72),
        (0.56, -0.08, 0.11, 0.16, 0.86),
        (-0.10, 0.02, 0.32, 0.18, 0.92),
    ]
    for i, (x, y, z, r, tp) in enumerate(pts):
        mk = "dust_cream" if i % 2 == 0 else "dust_sand"
        col = DUST_CREAM if i % 2 == 0 else DUST_SAND
        b.compound_puff((x, y, z), r, lobes=2, scale_z=0.68,
                        mat_key=mk, srgb=col, t_phase=tp, seed=(i * 0.31 + 0.1) % 1.0,
                        dir_xy=(1.0 if x >= 0 else -1.0, 0.0))
    b.finalize()
    return b


def build_fx_car_exhaust_puff():
    """12. Горизонтальная струйка выхлопного дыма машин и грузовиков в пробках."""
    clear_scene()
    b = ParticleBuilder("fx_car_exhaust_puff")
    steps = 6
    for i in range(steps):
        t = (i + 0.5) / steps
        seed = (i * 0.37 + 0.11) % 1.0
        # Направлена назад по +Y Blender (в Godot с turns=2 уходит позади бампера) и чуть вверх
        y = 0.06 + t * 0.62
        x = math.sin(i * 1.6) * 0.04 * t
        z = 0.04 + (t ** 1.2) * 0.24
        rad = 0.055 + 0.075 * math.sin(t * math.pi * 0.85)
        mk = "exhaust_dark" if t < 0.45 else "exhaust_light"
        col = SMOKE_DARK if t < 0.45 else SMOKE_LIGHT
        b.icosphere_puff((x, y, z), rad, scale_xyz=(1.0, 1.15, 0.82),
                         mat_key=mk, srgb=col, t_phase=t, seed=seed, dir_xy=(0.0, 1.0))
    b.finalize()
    return b


def build_fx_fountain_park_jets():
    """13. Городской фонтан со струями воды, пенным гейзером и кругами в чаше."""
    clear_scene()
    b = ParticleBuilder("fx_fountain_park_jets")
    # Водное зеркало и два пенных кольца на воде
    b.ripple_ring((0.0, 0.0, 0.02), 0.24, 0.32, height=0.03, segments=16,
                  mat_key="water_foam", srgb=WATER_FOAM, t_phase=0.45, seed=0.15)
    b.ripple_ring((0.0, 0.0, 0.02), 0.48, 0.58, height=0.035, segments=18,
                  mat_key="water_light", srgb=WATER_LIGHT, t_phase=0.82, seed=0.55)
    # Центральный вертикальный пенный гейзер
    for i in range(6):
        t = (i + 0.4) / 6.0
        z = 0.08 + t * 1.22
        r = 0.11 * (1.15 - 0.45 * t)
        mk = "water_foam" if i >= 3 else "water_light"
        col = WATER_FOAM if i >= 3 else WATER_LIGHT
        b.icosphere_puff((0.0, 0.0, z), r, scale_xyz=(0.85, 0.85, 1.35),
                         mat_key=mk, srgb=col, roughness=0.20, t_phase=t, seed=(i * 0.23) % 1.0)
    # 6 параболических боковых струй из капель воды
    jets = 6
    drops_per_jet = 5
    for j in range(jets):
        ang = j * (math.tau / jets)
        ca, sa = math.cos(ang), math.sin(ang)
        for d_idx in range(drops_per_jet):
            u = (d_idx + 0.5) / drops_per_jet
            rad = 0.06 + u * 0.54
            # Парабола струи фонтана: вверх до 0.95 м и дугой вниз к чаше
            z = 0.10 + 0.92 * 4.0 * u * (1.0 - u * 0.92)
            dx = ca * 0.54
            dy = sa * 0.54
            dz = 0.92 * 4.0 * (1.0 - 1.84 * u)
            mk = "water_azure" if u < 0.7 else "water_foam"
            col = WATER_AZURE if u < 0.7 else WATER_FOAM
            b.water_drop((ca * rad, sa * rad, z), (dx, dy, dz),
                         0.16, 0.052, mat_key=mk, srgb=col,
                         t_phase=u, seed=((j * drops_per_jet + d_idx) * 0.13) % 1.0)
    b.finalize()
    return b


def build_fx_water_fire_hose():
    """14. Направленная струя воды пожарного брандспойта / поливалки / прорыва трубы."""
    clear_scene()
    b = ParticleBuilder("fx_water_fire_hose")
    steps = 12
    for i in range(steps):
        u = (i + 0.4) / steps
        seed = (i * 0.31 + 0.07) % 1.0
        # Струя бьёт вперёд вдоль -Y (в Godot с turns=2 вдоль +Z/-Z) по параболе
        y = -u * 1.65
        x = math.sin(i * 1.9) * 0.04 * u
        z = 0.08 + 0.85 * 4.0 * u * (1.0 - u * 0.82)
        dy = -1.65
        dz = 0.85 * 4.0 * (1.0 - 1.64 * u)
        mk = "water_azure" if u < 0.65 else "water_light"
        col = WATER_AZURE if u < 0.65 else WATER_LIGHT
        b.water_drop((x, y, z), (0.0, dy, dz), 0.22, 0.055 + 0.03 * u,
                     mat_key=mk, srgb=col, t_phase=u, seed=seed)
    # Веер белых пенных брызг на конце струи
    for k in range(6):
        a = k * (math.tau / 6.0)
        b.icosphere_puff((math.cos(a) * 0.18, -1.62 + math.sin(a) * 0.14, 0.22 + (k % 2) * 0.10),
                         0.085, mat_key="water_foam", srgb=WATER_FOAM, roughness=0.2,
                         t_phase=0.92, seed=(k * 0.19) % 1.0)
    b.finalize()
    return b


def build_fx_water_ripples_splash():
    """15. Концентрические круги на воде и пенные брызги для водозаборов и берегов."""
    clear_scene()
    b = ParticleBuilder("fx_water_ripples_splash")
    rings = [
        (0.14, 0.21, 0.035, "water_foam", WATER_FOAM, 0.25, 0.12),
        (0.34, 0.42, 0.030, "water_light", WATER_LIGHT, 0.58, 0.44),
        (0.58, 0.66, 0.024, "water_azure", WATER_AZURE, 0.90, 0.78),
    ]
    for r_in, r_out, h, mk, col, tp, sd in rings:
        b.ripple_ring((0.0, 0.0, 0.015), r_in, r_out, height=h, segments=18,
                      mat_key=mk, srgb=col, t_phase=tp, seed=sd)
    # Подпрыгивающие капли в центре всплеска
    for k in range(5):
        a = k * (math.tau / 5.0)
        r = 0.08 if k > 0 else 0.0
        z = 0.28 if k == 0 else 0.16 + (k % 2) * 0.06
        b.water_drop((math.cos(a) * r, math.sin(a) * r, z),
                     (math.cos(a) * 0.3, math.sin(a) * 0.3, 1.0),
                     0.14, 0.045, mat_key="water_foam", srgb=WATER_FOAM,
                     t_phase=0.35, seed=(k * 0.21) % 1.0)
    b.finalize()
    return b


def build_fx_nature_falling_leaves():
    """16. Кружащийся вихрь зелёных и золотисто-осенних листьев для парков и скверов."""
    clear_scene()
    b = ParticleBuilder("fx_nature_falling_leaves")
    palette = [
        ("leaf_green", LEAF_GREEN),
        ("leaf_lime", LEAF_LIME),
        ("leaf_gold", LEAF_GOLD),
        ("leaf_autumn", LEAF_AUTUMN),
    ]
    count = 18
    for i in range(count):
        t = (i + 0.5) / count
        seed = (i * 0.37 + 0.15) % 1.0
        ang = i * 1.45
        rad = 0.22 + 0.42 * math.sin(t * math.pi * 0.9)
        x = math.cos(ang) * rad
        y = math.sin(ang) * rad
        z = 0.12 + (1.0 - t) * 1.32
        mk, col = palette[i % len(palette)]
        rot = (0.5 * math.sin(i * 1.3), 0.6 * math.cos(i * 1.1), ang + 0.8)
        b.leaf_3d((x, y, z), 0.20, 0.13, 0.022, rot,
                  mat_key=mk, srgb=col, t_phase=t, seed=seed,
                  dir_xy=(math.cos(ang), math.sin(ang)))
    b.finalize()
    return b


def build_fx_nature_flock_birds():
    """17. Стайка кружащих городских птиц (чайки и голуби с разным углом взмаха крыльев)."""
    clear_scene()
    b = ParticleBuilder("fx_nature_flock_birds")
    birds = [
        # (pos, wingspan, flap, yaw, pitch, bank, is_seagull)
        ((0.0, -0.42, 0.88), 0.44, 0.32, 0.15, 0.08, -0.18, True),
        ((-0.46, -0.14, 0.72), 0.40, -0.22, 0.55, 0.05, -0.22, True),
        ((0.48, -0.08, 0.96), 0.42, 0.42, -0.35, 0.10, 0.20, False),
        ((-0.28, 0.38, 0.64), 0.38, 0.15, 1.10, -0.04, -0.25, False),
        ((0.34, 0.44, 1.08), 0.44, -0.28, -0.95, 0.06, 0.24, True),
        ((0.04, 0.12, 1.22), 0.40, 0.38, 0.05, 0.12, -0.12, False),
        ((-0.58, 0.22, 0.84), 0.38, -0.18, 0.82, 0.04, -0.20, True),
    ]
    for i, (pos, span, flap, yaw, pitch, bank, gull) in enumerate(birds):
        t = (i + 0.5) / len(birds)
        seed = (i * 0.29 + 0.11) % 1.0
        if gull:
            b.bird_3d(pos, wingspan=span, flap_angle=flap, yaw=yaw, pitch=pitch, bank=bank,
                      mat_body="gull_white", srgb_body=BIRD_WHITE,
                      mat_wing="gull_grey", srgb_wing=BIRD_GREY, t_phase=t, seed=seed)
        else:
            b.bird_3d(pos, wingspan=span, flap_angle=flap, yaw=yaw, pitch=pitch, bank=bank,
                      mat_body="dove_grey", srgb_body=BIRD_GREY,
                      mat_wing="dove_dark", srgb_wing=BIRD_DARK, t_phase=t, seed=seed)
    b.finalize()
    return b


def build_fx_weather_rain_cloud():
    """18. Дождевая тучка с косыми струями дождя и кругами брызг внизу."""
    clear_scene()
    b = ParticleBuilder("fx_weather_rain_cloud")
    # Грозовая тучка сверху (на высоте ~1.45..1.70 м)
    cloud_blobs = [
        ((0.0, 0.0, 1.54), 0.30, "cloud_mid", RAIN_CLOUD),
        ((-0.28, 0.06, 1.48), 0.24, "cloud_dark", SMOKE_DARK),
        ((0.28, -0.05, 1.50), 0.25, "cloud_mid", RAIN_CLOUD),
        ((0.08, 0.16, 1.62), 0.22, "cloud_light", SMOKE_LIGHT),
    ]
    for idx, (pos, r, mk, col) in enumerate(cloud_blobs):
        b.compound_puff(pos, r, lobes=2, scale_z=0.72, mat_key=mk, srgb=col,
                        t_phase=0.10, seed=(idx * 0.25) % 1.0)
    # 14 наклонных штрихов дождя
    for i in range(14):
        t = 0.22 + (i / 14.0) * 0.72
        ang = i * 2.1
        rad = 0.10 + (i % 4) * 0.11
        x = math.cos(ang) * rad - (t - 0.2) * 0.18
        y = math.sin(ang) * rad
        z = 1.32 - (t - 0.2) * 1.45
        b.spark_crystal((x, y, max(0.14, z)), (-0.18, 0.0, -1.0), 0.24, 0.022,
                        mat_key="rain_drop", srgb=WATER_LIGHT, emission=0.15,
                        t_phase=t, seed=(i * 0.19) % 1.0)
    # Круги от капель внизу
    for x, y, r in ((-0.22, -0.10, 0.12), (0.16, 0.14, 0.14), (-0.04, 0.20, 0.10)):
        b.ripple_ring((x, y, 0.015), r * 0.65, r, height=0.02, segments=12,
                      mat_key="rain_splash", srgb=WATER_FOAM, t_phase=0.95, seed=0.7)
    b.finalize()
    return b


def build_fx_weather_snow_swirl():
    """19. Снежный вихрь из объёмных шестилучевых снежинок и пушистых снежков."""
    clear_scene()
    b = ParticleBuilder("fx_weather_snow_swirl")
    for i in range(10):
        t = (i + 0.4) / 10.0
        seed = (i * 0.31 + 0.09) % 1.0
        ang = i * 1.55
        rad = 0.18 + 0.38 * math.sin(t * math.pi * 0.9)
        x = math.cos(ang) * rad
        y = math.sin(ang) * rad
        z = 0.14 + (1.0 - t) * 1.36
        rot = (i * 0.5, i * 0.7, ang)
        mk = "snow_pure" if i % 2 == 0 else "snow_ice"
        col = SNOW_PURE if i % 2 == 0 else SNOW_ICE
        b.snowflake_3d((x, y, z), 0.11, 0.024, rot_euler=rot, mat_key=mk, srgb=col, t_phase=t, seed=seed)
    # 8 маленьких пушистых снежных комочков между кристаллами
    for i in range(8):
        t = (i + 0.6) / 8.0
        ang = i * 1.9 + 0.8
        rad = 0.14 + (i % 3) * 0.15
        b.icosphere_puff((math.cos(ang) * rad, math.sin(ang) * rad, 0.18 + i * 0.16),
                         0.055, mat_key="snow_pure", srgb=SNOW_PURE, t_phase=t, seed=(i * 0.23) % 1.0)
    b.finalize()
    return b


def build_fx_celebrate_levelup_confetti():
    """20. Праздничный салют Level-Up: золотые 3D-звёзды и разноцветное конфетти над выросшим зданием."""
    clear_scene()
    b = ParticleBuilder("fx_celebrate_levelup_confetti")
    # 6 золотых пятиконечных звёзд
    for i in range(6):
        ang = i * (math.tau / 6.0)
        t = 0.25 + (i % 3) * 0.25
        rad = 0.24 + (i % 2) * 0.18
        z = 0.38 + i * 0.18
        b.star_3d((math.cos(ang) * rad, math.sin(ang) * rad, z),
                  0.15, 0.065, 0.055, rot_euler=(0.25 * math.sin(i), 0.2 * math.cos(i), ang),
                  points=5, mat_key="star_gold", srgb=STAR_GOLD, emission=0.45,
                  t_phase=t, seed=(i * 0.27) % 1.0)
    # Центральная крупная звезда на вершине
    b.star_3d((0.0, 0.0, 1.48), 0.22, 0.095, 0.075, rot_euler=(0.0, 0.0, 0.0),
              points=5, mat_key="star_gold", srgb=STAR_GOLD, emission=0.60, t_phase=0.92, seed=0.88)
    # 20 разноцветных пластинок конфетти
    confetti_cols = [
        ("conf_red", CONFETTI_RED),
        ("conf_blue", CONFETTI_BLUE),
        ("conf_green", CONFETTI_GREEN),
        ("conf_pink", CONFETTI_PINK),
        ("conf_purple", CONFETTI_PURPLE),
    ]
    for i in range(20):
        t = (i + 0.5) / 20.0
        ang = i * 1.618 * math.tau
        rad = 0.16 + 0.48 * math.sin(t * math.pi * 0.92)
        z = 0.14 + t * 1.32
        mk, col = confetti_cols[i % len(confetti_cols)]
        b.confetti_tile((math.cos(ang) * rad, math.sin(ang) * rad, z),
                        0.11, 0.065, 0.016, rot_euler=(i * 0.7, i * 0.9, ang),
                        mat_key=mk, srgb=col, t_phase=t, seed=(i * 0.17) % 1.0)
    b.finalize()
    return b


# ===========================================================================
# 2. ОДИНОЧНЫЕ 3D-МЕШИ ЧАСТИЦ (12 МОДЕЛЕЙ В assets/models/blender/particles/units/)
# ===========================================================================

def build_unit_smoke_puff_soft():
    clear_scene()
    b = ParticleBuilder("unit_smoke_puff_soft")
    b.compound_puff((0.0, 0.0, 0.0), 0.36, lobes=3, scale_z=0.85,
                    mat_key="smoke", srgb=SMOKE_WHITE, t_phase=0.5, seed=0.25)
    b.finalize()
    return b


def build_unit_smoke_puff_faceted():
    clear_scene()
    b = ParticleBuilder("unit_smoke_puff_faceted")
    b.icosphere_puff((0.0, 0.0, 0.0), 0.45, scale_xyz=(1.05, 0.98, 0.84), subdivisions=1,
                     jitter=0.08, mat_key="smoke", srgb=SMOKE_LIGHT, t_phase=0.5, seed=0.35)
    b.finalize()
    return b


def build_unit_flame_shard():
    clear_scene()
    b = ParticleBuilder("unit_flame_shard")
    b.flame_tongue((0.0, 0.0, 0.0), 1.0, 0.26, lean_xy=(0.06, 0.0), twist=0.65,
                   mat_key="flame", srgb=FIRE_ORANGE, emission=0.6, t_phase=0.5, seed=0.2)
    b.finalize()
    return b


def build_unit_spark_crystal():
    clear_scene()
    b = ParticleBuilder("unit_spark_crystal")
    b.spark_crystal((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.85, 0.12,
                    mat_key="spark", srgb=FIRE_YELLOW, emission=0.85, t_phase=0.5, seed=0.1)
    b.finalize()
    return b


def build_unit_water_drop():
    clear_scene()
    b = ParticleBuilder("unit_water_drop")
    b.water_drop((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.80, 0.24,
                 mat_key="water", srgb=WATER_AZURE, t_phase=0.5, seed=0.1)
    b.finalize()
    return b


def build_unit_water_ripple_ring():
    clear_scene()
    b = ParticleBuilder("unit_water_ripple_ring")
    b.ripple_ring((0.0, 0.0, 0.0), 0.36, 0.50, height=0.05, segments=18,
                  mat_key="ripple", srgb=WATER_FOAM, t_phase=0.5, seed=0.1)
    b.finalize()
    return b


def build_unit_rubble_chunk():
    clear_scene()
    b = ParticleBuilder("unit_rubble_chunk")
    b.rubble_chunk((0.0, 0.0, 0.0), (0.55, 0.32, 0.24), (0.15, 0.25, 0.10),
                   mat_key="rubble", srgb=RUBBLE_BRICK, t_phase=0.5, seed=0.3)
    b.finalize()
    return b


def build_unit_leaf():
    clear_scene()
    b = ParticleBuilder("unit_leaf")
    b.leaf_3d((0.0, 0.0, 0.0), 0.75, 0.48, 0.06, (0.0, 0.0, 0.0),
              mat_key="leaf", srgb=LEAF_GREEN, t_phase=0.5, seed=0.2)
    b.finalize()
    return b


def build_unit_bird_glide():
    clear_scene()
    b = ParticleBuilder("unit_bird_glide")
    b.bird_3d((0.0, 0.0, 0.0), wingspan=0.90, flap_angle=0.26, yaw=0.0, pitch=0.05, bank=0.0,
              mat_body="bird_white", srgb_body=BIRD_WHITE,
              mat_wing="bird_grey", srgb_wing=BIRD_GREY, t_phase=0.5, seed=0.2)
    b.finalize()
    return b


def build_unit_snowflake_hex():
    clear_scene()
    b = ParticleBuilder("unit_snowflake_hex")
    b.snowflake_3d((0.0, 0.0, 0.0), 0.45, 0.08, rot_euler=(0.0, 0.0, 0.0),
                   mat_key="snow", srgb=SNOW_PURE, t_phase=0.5, seed=0.2)
    b.finalize()
    return b


def build_unit_star_gold():
    clear_scene()
    b = ParticleBuilder("unit_star_gold")
    b.star_3d((0.0, 0.0, 0.0), 0.48, 0.21, 0.16, rot_euler=(0.0, 0.0, 0.0),
              points=5, mat_key="star", srgb=STAR_GOLD, emission=0.5, t_phase=0.5, seed=0.2)
    b.finalize()
    return b


def build_unit_confetti_tile():
    clear_scene()
    b = ParticleBuilder("unit_confetti_tile")
    b.confetti_tile((0.0, 0.0, 0.0), 0.55, 0.34, 0.05, (0.1, 0.15, 0.0),
                    mat_key="confetti", srgb=CONFETTI_BLUE, t_phase=0.5, seed=0.2)
    b.finalize()
    return b


# ===========================================================================
# РЕЕСТРЫ ЭФФЕКТОВ И ЕДИНИЧНЫХ ЧАСТИЦ
# ===========================================================================

PARTICLE_PLUMES = [
    # (id, category, display_name, target_usage, recommended_scale, anim_mode, build_fn)
    ("fx_smoke_chimney_light", "smoke_steam", "Лёгкий печной/каминный дым",
     "Жилые дома (RESIDENTIAL 1x1..3x2), пекарни (com_corner_bakery_1x1), пиццерии (com_bistro_terrace_2x1)",
     1.0, "plume_rise_sway", build_fx_smoke_chimney_light),

    ("fx_smoke_factory_heavy", "smoke_steam", "Густой тёмный заводской дым и смог",
     "Трубы заводов (INDUSTRIAL smokestack) и угольная ТЭЦ (power_plant)",
     1.0, "plume_rise_sway", build_fx_smoke_factory_heavy),

    ("fx_smoke_twin_stacks", "smoke_steam", "Двойной шлейф заводских труб",
     "Крупные заводы и комбинаты (2x1..7x1, 3x2) с парными трубами",
     1.0, "plume_rise_sway", build_fx_smoke_twin_stacks),

    ("fx_steam_cooling_tower", "smoke_steam", "Густой белый пар градирни / котельной",
     "Градирни, котельные (ind_boiler_house_1x1), геотермальные и тепловые станции",
     1.0, "plume_rise_sway", build_fx_steam_cooling_tower),

    ("fx_steam_vent_puff", "smoke_steam", "Клубы пара крышной вентиляции и кухонь",
     "Крышные блоки HVAC офисов, ТРЦ, больниц и ресторанов",
     1.0, "plume_rise_sway", build_fx_steam_vent_puff),

    ("fx_cafe_aroma_swirl", "smoke_steam", "Спиральный пар и аромат горячего кофе",
     "Гигантские 3D-чашки эспрессо на крышах кофеен, фудкортов и пекарен (COMMERCIAL)",
     1.0, "spiral_swirl", build_fx_cafe_aroma_swirl),

    ("fx_fire_building_blaze", "fire_sparks", "Пожар здания: пламя, искры и чёрный дым",
     "Горящие здания и выезды пожарных машин (fire_station / fire_depot_2x1)",
     1.0, "fire_flicker", build_fx_fire_building_blaze),

    ("fx_fire_refinery_flare", "fire_sparks", "Газовый факел нефтезавода (Refinery Flare)",
     "Факельные башни нефтехимии, НПЗ и сталелитейных цехов (INDUSTRIAL)",
     1.0, "fire_flicker", build_fx_fire_refinery_flare),

    ("fx_sparks_welding_burst", "fire_sparks", "Снопы сварочных искр и вспышка дуги",
     "Стройплощадки (ConstructionVisualizer — у крюка крана или верхнего яруса лесов) и цеха",
     1.0, "burst_radial", build_fx_sparks_welding_burst),

    ("fx_dust_bulldoze_burst", "dust_traffic", "Облако пыли и обломков при сносе бульдозером",
     "Момент сноса здания, дороги или модуля станции бульдозером (BuildTool)",
     1.0, "burst_expand", build_fx_dust_bulldoze_burst),

    ("fx_dust_construction_site", "dust_traffic", "Строительная пыль у фундамента",
     "Основание строящихся зданий (ConstructionVisualizer) и грузовые дворы заводов",
     1.0, "ground_billow", build_fx_dust_construction_site),

    ("fx_car_exhaust_puff", "dust_traffic", "Выхлопной дымок машин и грузовиков",
     "Грузовики, автобусы и плотные очереди машин на загруженных дорогах (TrafficVisualizer)",
     1.0, "trail_puff", build_fx_car_exhaust_puff),

    ("fx_fountain_park_jets", "water", "Городской фонтан со струями и каскадом брызг",
     "Парки и площади (Park.PLAZA, Park.SQUARE, скверы у многоэтажек и ТРЦ)",
     1.0, "fountain_pulse", build_fx_fountain_park_jets),

    ("fx_water_fire_hose", "water", "Водяная струя пожарного брандспойта / прорыва трубы",
     "Тушение пожаров пожарными машинами, полив парков или авария водопровода",
     1.0, "jet_arc", build_fx_water_fire_hose),

    ("fx_water_ripples_splash", "water", "Круги на воде и пенные брызги",
     "У водозаборных станций (water_station), насосов (water_pump), мостов и берегов",
     1.0, "ripple_expand", build_fx_water_ripples_splash),

    ("fx_nature_falling_leaves", "nature_weather", "Кружащаяся листва в парках и скверах",
     "Кроны деревьев (TreeVisualizer), парки (SQUARE, GARDEN) и зелёные дворы (YardVisualizer)",
     1.0, "swirl_fall", build_fx_nature_falling_leaves),

    ("fx_nature_flock_birds", "nature_weather", "Стайка кружащих птиц (чайки и голуби)",
     "Небо над парками, площадями, рынками и береговой линией",
     1.0, "orbit_flock", build_fx_nature_flock_birds),

    ("fx_weather_rain_cloud", "nature_weather", "Дождевая тучка с косыми струями дождя",
     "Погодный эффект дождя или локальный ливень",
     1.0, "rain_streak", build_fx_weather_rain_cloud),

    ("fx_weather_snow_swirl", "nature_weather", "Снежный вихрь с объёмными снежинками",
     "Зимняя погода и снегопад",
     1.0, "swirl_fall", build_fx_weather_snow_swirl),

    ("fx_celebrate_levelup_confetti", "celebrate", "Праздничный салют: конфетти и золотые звёзды Level-Up",
     "Повышение уровня здания (ур. 1 -> 2 -> 3) или получение городом нового звания",
     1.0, "burst_celebrate", build_fx_celebrate_levelup_confetti),
]

PARTICLE_UNITS = [
    # (id, display_name, description, build_fn)
    ("unit_smoke_puff_soft", "Кучевой клуб дыма/пара", "Одиночный объёмный клуб из 4 долей для GPUParticles3D / MultiMesh", build_unit_smoke_puff_soft),
    ("unit_smoke_puff_faceted", "Гранёный икосаэдрический клуб дыма", "Одиночный лёгкий гранёный клуб дыма/пыли (80 треугольников)", build_unit_smoke_puff_faceted),
    ("unit_flame_shard", "Язык пламени", "Одиночный изогнутый гранёный язык огня (основание в нуле)", build_unit_flame_shard),
    ("unit_spark_crystal", "Кристалл искры", "Одиночная вытянутая октаэдрическая искра / дождевой штрих", build_unit_spark_crystal),
    ("unit_water_drop", "Капля воды", "Одиночная объёмная капля воды для струй фонтанов и брызг", build_unit_water_drop),
    ("unit_water_ripple_ring", "Кольцо волны на воде", "Одиночное горизонтальное кольцо кругов на воде", build_unit_water_ripple_ring),
    ("unit_rubble_chunk", "Обломок кирпича/бетона", "Одиночный обломок для эффекта сноса здания бульдозером", build_unit_rubble_chunk),
    ("unit_leaf", "Древесный листок", "Одиночный резной лоу-поли листок с V-прожилкой", build_unit_leaf),
    ("unit_bird_glide", "Птица в полёте", "Одиночная лоу-поли птица с раскрытыми крыльями (смотрит на -Y)", build_unit_bird_glide),
    ("unit_snowflake_hex", "Шестилучевая снежинка", "Одиночный объёмный кристалл снежинки", build_unit_snowflake_hex),
    ("unit_star_gold", "Пятиконечная золотая звезда", "Одиночная объёмная звезда для повышения уровня и счастья", build_unit_star_gold),
    ("unit_confetti_tile", "Пластинка конфетти", "Одиночная пластинка праздничного конфетти", build_unit_confetti_tile),
]
