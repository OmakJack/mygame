"""Архитектурный low-poly конструктор для Blender 5.2 (CityBuilder Building Pack).

Создаёт единый меш с одним материалом на палитре Kenney (colormap.png, сетка 8×4):
- Плавный вертикальный градиент внутри правой половины каждого образца палитры (как у оригинальных
  моделей Kenney) придаёт стенам, скатам, трубам и башням мягкий объём и затенение у земли.
- Строгое попадание UV внутрь ячейки (col, row) сохраняет 100 % совместимость с шейдером
  BuildingPalette в Godot (перекраска стен WALL/CREAM и акцентов ROOF по районам).
- Автопроверка внешних нормалей гарантирует отсутствие вывернутых граней.
"""

import math
import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PALETTE_PATH = os.path.join(ROOT, "assets", "models", "kenney", "suburban", "Textures", "colormap.png")
PACK_DIR = os.path.join(ROOT, "assets", "models", "blender", "pack")

CELL = 2.0

# --- Образцы палитры Kenney 8×4 (col, row) ---
# Перекрашиваемые стены (BuildingPalette мягко тонирует по району):
WALL = (3, 2)        # чисто-белая штукатурка / бетонная панель
CREAM = (7, 2)       # тёплый известняк / кремовый фасад

# Перекрашиваемые акценты крыш и козырьков (BuildingPalette задаёт цвет крыши дома):
ROOF = (0, 1)        # основной акцент крыши
ROOF_LITE = (1, 1)   # светлый акцент (конёк, козырьки, пояса)
ROOF_WARM = (2, 1)   # насыщенный тёплый акцент
ROOF_DEEP = (3, 1)   # глубокий черепичный акцент

# Стекло (не перекрашивается):
GLASS_DARK = (4, 1)  # глубокое сапфировое стекло витражей
GLASS_LITE = (5, 1)  # светлое небесно-голубое стекло / блики / фонари

# Фиксированные тёплые материалы: кирпич, терракота, песчаник, дерево, медь (не перекрашиваются):
TERRACOTTA = (4, 2)  # терракотовый кирпич / сигнальные полосы труб / кортен
BRICK = (5, 2)       # тёмно-красный старый кирпич / тёмный брус
SANDSTONE = (6, 2)   # тёплый песчаник / деревянные ламели / травертин
CLAY = (2, 3)        # приглушённый глиняный кирпич / сурик
COPPER = (3, 3)      # медь / светлый тёплый камень

# Фиксированные холодные материалы: металл, бетон, камень, сланец, асфальт (не перекрашиваются):
STEEL = (0, 2)       # стальной профиль / трубы / импосты
SLATE = (1, 2)       # тёмный сланец / оконные рамы / плоская кровля
ALUM = (2, 2)        # светлый серебристо-голубой алюминий / силосы / хай-тек панели
IRON = (0, 3)        # почти чёрный чугун / глубокие ниши / ворота
GUNMETAL = (4, 3)    # тёмный индустриальный металл / цоколь
CONCRETE = (5, 3)    # серый конструкционный бетон / стилобаты
STONE = (6, 3)       # светлый гранит / карнизы / подоконники / мощение
CHARCOAL = (7, 3)    # антрацит / гудрон / вентрешётки


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)


def palette_material(linear=True):
    mat = bpy.data.materials.new("colormap")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(PALETTE_PATH, check_existing=True)
    tex.interpolation = "Linear" if linear else "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.76
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.35
    return mat


def _newell_normal(pts):
    nx = ny = nz = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1, z1 = pts[i]
        x2, y2, z2 = pts[(i + 1) % n]
        nx += (y1 - y2) * (z1 + z2)
        ny += (z1 - z2) * (x1 + x2)
        nz += (x1 - x2) * (y1 + y2)
    return (nx, ny, nz)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _rot_z(x, y, cx, cy, angle):
    if abs(angle) < 1e-7:
        return x, y
    dx, dy = x - cx, y - cy
    ca, sa = math.cos(angle), math.sin(angle)
    return cx + dx * ca - dy * sa, cy + dx * sa + dy * ca


class ArchBuilder:
    """Низкополигональный архитектурный построитель одной модели."""

    def __init__(self, name, material=None):
        self.name = name
        self.material = material or palette_material()
        self.verts = []
        self.faces = []
        self.loop_uvs = []

    def add_poly(self, pts, swatch, outward=None, grad=True):
        """Добавляет грань по точкам pts, проверяет нормаль по outward и считает UV с градиентом."""
        if len(pts) < 3:
            return
        n = _newell_normal(pts)
        n_len = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        if n_len < 1e-9:
            return
        if outward is not None and _dot(n, outward) < 0.0:
            pts = list(reversed(pts))
            n = (-n[0], -n[1], -n[2])

        base = len(self.verts)
        for p in pts:
            self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        self.faces.append(tuple(base + i for i in range(len(pts))))

        col, row = swatch
        zs = [p[2] for p in pts]
        z_min, z_max = min(zs), max(zs)
        dz = z_max - z_min

        if not grad:
            u = (col + 0.25) / 8.0
            v = 1.0 - (row + 0.45) / 4.0
            self.loop_uvs.append([(u, v)] * len(pts))
            return

        if dz > 0.035:
            # Вертикальная или наклонная грань: плавный градиент Kenney сверху вниз
            u = (col + 0.75) / 8.0
            span_lo, span_hi = (0.76, 0.22) if dz >= 0.22 else (0.64, 0.30)
            uvs = []
            for p in pts:
                t = (p[2] - z_min) / dz
                r_off = span_lo + (span_hi - span_lo) * t
                uvs.append((u, 1.0 - (row + r_off) / 4.0))
            self.loop_uvs.append(uvs)
        else:
            # Горизонтальная грань: верх светлый, подшивка снизу затенённая
            if n[2] >= 0.0:
                u, v = (col + 0.25) / 8.0, 1.0 - (row + 0.24) / 4.0
            else:
                u, v = (col + 0.75) / 8.0, 1.0 - (row + 0.80) / 4.0
            self.loop_uvs.append([(u, v)] * len(pts))

    # --- Базовые объёмы ---

    def box(self, center, size, swatch, grad=True, angle_z=0.0, skip_bottom=False):
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        if hx <= 1e-5 or hy <= 1e-5 or hz <= 1e-5:
            return
        local = [
            (-hx, -hy, -hz), (hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz),
            (-hx, -hy, hz), (hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz),
        ]
        ca, sa = math.cos(angle_z), math.sin(angle_z)
        pts = []
        for dx, dy, dz in local:
            rx = dx * ca - dy * sa
            ry = dx * sa + dy * ca
            pts.append((cx + rx, cy + ry, cz + dz))

        def rot_n(nx, ny, nz):
            return (nx * ca - ny * sa, nx * sa + ny * ca, nz)

        if not skip_bottom:
            self.add_poly([pts[0], pts[2], pts[3], pts[1]], swatch, (0, 0, -1), grad=grad)
        self.add_poly([pts[4], pts[5], pts[7], pts[6]], swatch, (0, 0, 1), grad=grad)
        self.add_poly([pts[0], pts[1], pts[5], pts[4]], swatch, rot_n(0, -1, 0), grad=grad)
        self.add_poly([pts[3], pts[2], pts[6], pts[7]], swatch, rot_n(0, 1, 0), grad=grad)
        self.add_poly([pts[2], pts[0], pts[4], pts[6]], swatch, rot_n(-1, 0, 0), grad=grad)
        self.add_poly([pts[1], pts[3], pts[7], pts[5]], swatch, rot_n(1, 0, 0), grad=grad)

    def tilted_box(self, center, size, swatch, pitch_x=0.0, roll_y=0.0, yaw_z=0.0, grad=True):
        """Коробка с произвольным наклоном (солнечные панели, укосины, скаты, стрелы кранов)."""
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        cxr, sxr = math.cos(pitch_x), math.sin(pitch_x)
        cyr, syr = math.cos(roll_y), math.sin(roll_y)
        czr, szr = math.cos(yaw_z), math.sin(yaw_z)

        def tf(vx, vy, vz, translate=True):
            # X -> Y -> Z
            y1, z1 = vy * cxr - vz * sxr, vy * sxr + vz * cxr
            x2, z2 = vx * cyr + z1 * syr, -vx * syr + z1 * cyr
            x3, y3 = x2 * czr - y1 * szr, x2 * szr + y1 * czr
            return (cx + x3, cy + y3, cz + z2) if translate else (x3, y3, z2)

        local = [
            (-hx, -hy, -hz), (hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz),
            (-hx, -hy, hz), (hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz),
        ]
        pts = [tf(*p, True) for p in local]
        quads = [
            ((0, 2, 3, 1), (0, 0, -1)),
            ((4, 5, 7, 6), (0, 0, 1)),
            ((0, 1, 5, 4), (0, -1, 0)),
            ((3, 2, 6, 7), (0, 1, 0)),
            ((2, 0, 4, 6), (-1, 0, 0)),
            ((1, 3, 7, 5), (1, 0, 0)),
        ]
        for idxs, n_loc in quads:
            self.add_poly([pts[i] for i in idxs], swatch, tf(*n_loc, False), grad=grad)

    def chamfer_prism(self, cx, cy, z0, width, depth, height, chamfer, swatch, grad=True, cap=True):
        """Восьмигранная призма (прямоугольник со скошенными под 45° углами)."""
        hx, hy = width * 0.5, depth * 0.5
        c = min(chamfer, hx * 0.85, hy * 0.85)
        ring = [
            (cx - hx + c, cy - hy),
            (cx + hx - c, cy - hy),
            (cx + hx, cy - hy + c),
            (cx + hx, cy + hy - c),
            (cx + hx - c, cy + hy),
            (cx - hx + c, cy + hy),
            (cx - hx, cy + hy - c),
            (cx - hx, cy - hy + c),
        ]
        n = len(ring)
        for i in range(n):
            x1, y1 = ring[i]
            x2, y2 = ring[(i + 1) % n]
            mx, my = (x1 + x2) * 0.5 - cx, (y1 + y2) * 0.5 - cy
            self.add_poly(
                [(x1, y1, z0), (x2, y2, z0), (x2, y2, z0 + height), (x1, y1, z0 + height)],
                swatch,
                (mx, my, 0.0),
                grad=grad,
            )
        if cap:
            self.add_poly([(x, y, z0 + height) for (x, y) in ring], swatch, (0, 0, 1), grad=grad)
            self.add_poly([(x, y, z0) for (x, y) in reversed(ring)], swatch, (0, 0, -1), grad=grad)

    def cylinder(self, center, r_bot, r_top, length, swatch, axis="z", segments=14, grad=True, caps=True):
        """Цилиндр или усечённый конус (трубы, силосы, колонны, цистерны)."""
        cx, cy, cz = center
        half = length * 0.5
        ring_lo = []
        ring_hi = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            ca, sa = math.cos(a), math.sin(a)
            if axis == "z":
                ring_lo.append((cx + r_bot * ca, cy + r_bot * sa, cz - half))
                ring_hi.append((cx + r_top * ca, cy + r_top * sa, cz + half))
            elif axis == "x":
                ring_lo.append((cx - half, cy + r_bot * ca, cz + r_bot * sa))
                ring_hi.append((cx + half, cy + r_top * ca, cz + r_top * sa))
            else:
                ring_lo.append((cx + r_bot * ca, cy - half, cz + r_bot * sa))
                ring_hi.append((cx + r_top * ca, cy + half, cz + r_top * sa))

        for i in range(segments):
            j = (i + 1) % segments
            p0, p1, p2, p3 = ring_lo[i], ring_lo[j], ring_hi[j], ring_hi[i]
            mx = (p0[0] + p1[0] + p2[0] + p3[0]) * 0.25 - cx
            my = (p0[1] + p1[1] + p2[1] + p3[1]) * 0.25 - cy
            mz = (p0[2] + p1[2] + p2[2] + p3[2]) * 0.25 - cz
            if axis == "z":
                out = (mx, my, 0.0)
            elif axis == "x":
                out = (0.0, my, mz)
            else:
                out = (mx, 0.0, mz)
            self.add_poly([p0, p1, p2, p3], swatch, out, grad=grad)

        if caps:
            n_axis = {"z": (0, 0, 1), "x": (1, 0, 0), "y": (0, 1, 0)}[axis]
            if r_top > 1e-4:
                self.add_poly(ring_hi, swatch, n_axis, grad=grad)
            if r_bot > 1e-4:
                self.add_poly(list(reversed(ring_lo)), swatch, (-n_axis[0], -n_axis[1], -n_axis[2]), grad=grad)

    def hyperboloid_tower(self, cx, cy, z0, r_base, r_throat, r_top, height, swatch, rim_swatch=STONE, segments=16):
        """Гиперболоидная градирня ТЭЦ/комбината на бетонных V-опорах."""
        leg_h = height * 0.12
        # Чаша бассейна внизу
        self.cylinder((cx, cy, z0 + leg_h * 0.35), r_base * 1.04, r_base * 1.04, leg_h * 0.7, CONCRETE, segments=segments)
        self.cylinder((cx, cy, z0 + leg_h * 0.72), r_base * 0.96, r_base * 0.96, 0.05, GLASS_DARK, segments=segments)
        # Колонны воздухозабора
        for i in range(segments // 2):
            a = 2.0 * math.pi * i / (segments // 2)
            px = cx + (r_base * 0.95) * math.cos(a)
            py = cy + (r_base * 0.95) * math.sin(a)
            self.box((px, py, z0 + leg_h * 0.65), (0.07, 0.07, leg_h * 0.9), STONE, angle_z=a)

        bands = 6
        z_start = z0 + leg_h
        shell_h = height - leg_h
        throat_t = 0.68

        def radius_at(t):
            if t <= throat_t:
                u = (throat_t - t) / throat_t
                return r_throat + (r_base - r_throat) * (u * u)
            u = (t - throat_t) / (1.0 - throat_t)
            return r_throat + (r_top - r_throat) * (u * u)

        rings = []
        for k in range(bands + 1):
            t = k / bands
            rk = radius_at(t)
            zk = z_start + shell_h * t
            rings.append([(cx + rk * math.cos(2 * math.pi * i / segments),
                           cy + rk * math.sin(2 * math.pi * i / segments), zk) for i in range(segments)])

        for k in range(bands):
            sw = TERRACOTTA if k == bands - 1 else swatch
            for i in range(segments):
                j = (i + 1) % segments
                p0, p1 = rings[k][i], rings[k][j]
                p2, p3 = rings[k + 1][j], rings[k + 1][i]
                mx = (p0[0] + p2[0]) * 0.5 - cx
                my = (p0[1] + p2[1]) * 0.5 - cy
                self.add_poly([p0, p1, p2, p3], sw, (mx, my, 0.0), grad=True)

        # Верхнее кольцо жёсткости и тёмное жерло градирни
        z_top = z0 + height
        self.cylinder((cx, cy, z_top + 0.03), r_top * 1.05, r_top * 1.05, 0.06, rim_swatch, segments=segments)
        self.cylinder((cx, cy, z_top - 0.04), r_top * 0.92, r_top * 0.92, 0.04, IRON, segments=segments)

    # --- Крыши ---

    def gable_roof(self, cx, cy, z0, width, depth, roof_h, roof_swatch=ROOF, gable_swatch=WALL,
                   trim_swatch=STONE, overhang=0.09, axis="x"):
        """Двускатная крыша с фронтонами, карнизными свесами, ветровой доской и коньком."""
        thick = 0.055
        if axis == "x":
            # Конёк идёт вдоль оси X, треугольные фронтоны слева/справа (±X)
            hw, hd = width * 0.5, depth * 0.5
            # Фронтоны
            for sign in (-1, 1):
                gx = cx + sign * hw
                self.add_poly(
                    [(gx, cy - hd, z0), (gx, cy + hd, z0), (gx, cy, z0 + roof_h)],
                    gable_swatch,
                    (sign, 0, 0),
                )
            # Два объёмных ската со свесом
            slope_len = math.hypot(hd + overhang, roof_h)
            angle = math.atan2(roof_h, hd)
            span_x = width + overhang * 2.0
            for sign in (-1, 1):
                sy = cy + sign * (hd + overhang) * 0.5
                sz = z0 + (roof_h - (overhang * roof_h / max(hd, 0.05))) * 0.5 + thick * 0.45
                self.tilted_box((cx, sy, sz), (span_x, slope_len, thick), roof_swatch, pitch_x=-sign * angle)
            # Коньковая планка
            self.box((cx, cy, z0 + roof_h + thick * 0.55), (span_x + 0.02, 0.09, 0.06), trim_swatch)
        else:
            # Конёк вдоль Y, треугольные фронтоны на фасаде (−Y) и сзади (+Y)
            hw, hd = width * 0.5, depth * 0.5
            for sign in (-1, 1):
                gy = cy + sign * hd
                self.add_poly(
                    [(cx - hw, gy, z0), (cx + hw, gy, z0), (cx, gy, z0 + roof_h)],
                    gable_swatch,
                    (0, sign, 0),
                )
            slope_len = math.hypot(hw + overhang, roof_h)
            angle = math.atan2(roof_h, hw)
            span_y = depth + overhang * 2.0
            for sign in (-1, 1):
                sx = cx + sign * (hw + overhang) * 0.5
                sz = z0 + (roof_h - (overhang * roof_h / max(hw, 0.05))) * 0.5 + thick * 0.45
                self.tilted_box((sx, cy, sz), (slope_len, span_y, thick), roof_swatch, roll_y=sign * angle)
            self.box((cx, cy, z0 + roof_h + thick * 0.55), (0.09, span_y + 0.02, 0.06), trim_swatch)

    def hip_roof(self, cx, cy, z0, width, depth, roof_h, roof_swatch=ROOF, fascia_swatch=STONE,
                 overhang=0.09, ridge_frac=0.45):
        """Вальмовая четырёхскатная (или шатровая при ridge_frac=0) крыша с карнизной плитой."""
        ow, od = width + overhang * 2.0, depth + overhang * 2.0
        fascia_h = 0.055
        self.box((cx, cy, z0 + fascia_h * 0.5), (ow, od, fascia_h), fascia_swatch)
        zb = z0 + fascia_h
        zt = zb + roof_h
        hw, hd = ow * 0.5, od * 0.5

        c0 = (cx - hw, cy - hd, zb)
        c1 = (cx + hw, cy - hd, zb)
        c2 = (cx + hw, cy + hd, zb)
        c3 = (cx - hw, cy + hd, zb)

        if width >= depth and ridge_frac > 0.02:
            rx = max(0.02, (hw - hd * 0.65) * ridge_frac + hw * ridge_frac * 0.5)
            rx = min(rx, hw * 0.72)
            r0, r1 = (cx - rx, cy, zt), (cx + rx, cy, zt)
            self.add_poly([c0, c1, r1, r0], roof_swatch, (0, -1, 0.6))
            self.add_poly([c2, c3, r0, r1], roof_swatch, (0, 1, 0.6))
            self.add_poly([c1, c2, r1], roof_swatch, (1, 0, 0.6))
            self.add_poly([c3, c0, r0], roof_swatch, (-1, 0, 0.6))
            self.box((cx, cy, zt + 0.02), (rx * 2.0 + 0.06, 0.08, 0.05), fascia_swatch)
        elif depth > width and ridge_frac > 0.02:
            ry = min(hd * 0.72, hd * ridge_frac)
            r0, r1 = (cx, cy - ry, zt), (cx, cy + ry, zt)
            self.add_poly([c0, c1, r0], roof_swatch, (0, -1, 0.6))
            self.add_poly([c2, c3, r1], roof_swatch, (0, 1, 0.6))
            self.add_poly([c1, c2, r1, r0], roof_swatch, (1, 0, 0.6))
            self.add_poly([c3, c0, r0, r1], roof_swatch, (-1, 0, 0.6))
            self.box((cx, cy, zt + 0.02), (0.08, ry * 2.0 + 0.06, 0.05), fascia_swatch)
        else:
            apex = (cx, cy, zt)
            self.add_poly([c0, c1, apex], roof_swatch, (0, -1, 0.6))
            self.add_poly([c1, c2, apex], roof_swatch, (1, 0, 0.6))
            self.add_poly([c2, c3, apex], roof_swatch, (0, 1, 0.6))
            self.add_poly([c3, c0, apex], roof_swatch, (-1, 0, 0.6))

    def mansard_roof(self, cx, cy, z0, width, depth, steep_h, cap_h=0.10, inset=0.22,
                     steep_swatch=ROOF, cap_swatch=SLATE, cornice_swatch=STONE, overhang=0.07):
        """Французская мансардная крыша с карнизным поясом, крутым нижним ярусом и верхней шапкой."""
        ch = 0.06
        ow, od = width + overhang * 2.0, depth + overhang * 2.0
        self.box((cx, cy, z0 + ch * 0.5), (ow, od, ch), cornice_swatch)
        zb = z0 + ch
        zt = zb + steep_h
        hw0, hd0 = ow * 0.5, od * 0.5
        hw1, hd1 = max(0.15, hw0 - inset), max(0.15, hd0 - inset)

        b0 = [(cx - hw0, cy - hd0, zb), (cx + hw0, cy - hd0, zb),
              (cx + hw0, cy + hd0, zb), (cx - hw0, cy + hd0, zb)]
        b1 = [(cx - hw1, cy - hd1, zt), (cx + hw1, cy - hd1, zt),
              (cx + hw1, cy + hd1, zt), (cx - hw1, cy + hd1, zt)]
        outs = [(0, -1, 0.35), (1, 0, 0.35), (0, 1, 0.35), (-1, 0, 0.35)]
        for i in range(4):
            j = (i + 1) % 4
            self.add_poly([b0[i], b0[j], b1[j], b1[i]], steep_swatch, outs[i])

        self.box((cx, cy, zt + 0.025), (hw1 * 2.0 + 0.05, hd1 * 2.0 + 0.05, 0.05), cornice_swatch)
        if cap_h > 0.02:
            self.hip_roof(cx, cy, zt + 0.05, hw1 * 2.0 - 0.04, hd1 * 2.0 - 0.04, cap_h,
                          roof_swatch=cap_swatch, fascia_swatch=SLATE, overhang=0.02, ridge_frac=0.55)

    def dormer(self, x, y, z0, dir_xy=(0, -1), w=0.28, d=0.26, h=0.28, wall_swatch=WALL, roof_swatch=ROOF_LITE):
        """Мансардное слуховое окошко с двускатным козырьком и остеклением."""
        dx, dy = dir_xy
        angle = math.atan2(dx, -dy)
        self.box((x, y, z0 + h * 0.45), (w, d, h * 0.9), wall_swatch, angle_z=angle)
        # Стекло спереди
        fx = x + dx * (d * 0.5 + 0.008)
        fy = y + dy * (d * 0.5 + 0.008)
        self.box((fx, fy, z0 + h * 0.46), (w * 0.68, 0.025, h * 0.56), SLATE, angle_z=angle)
        self.box((fx + dx * 0.006, fy + dy * 0.006, z0 + h * 0.46), (w * 0.52, 0.02, h * 0.42), GLASS_LITE, angle_z=angle)
        # Маленькая двускатная шапка
        if abs(dy) > 0.5:
            self.gable_roof(x, y, z0 + h * 0.9, w + 0.04, d + 0.05, 0.11,
                            roof_swatch=roof_swatch, gable_swatch=wall_swatch, trim_swatch=STONE, overhang=0.03, axis="y")
        else:
            self.gable_roof(x, y, z0 + h * 0.9, d + 0.05, w + 0.04, 0.11,
                            roof_swatch=roof_swatch, gable_swatch=wall_swatch, trim_swatch=STONE, overhang=0.03, axis="x")

    def sawtooth_roof(self, cx, cy, z0, width, depth, teeth, tooth_h,
                      roof_swatch=SLATE, wall_swatch=WALL, axis="y"):
        """Шедовая (зубчатая) крыша заводского цеха с вертикальным остеклением каждого зуба."""
        if axis == "y":
            # Зубья идут вдоль глубины Y; вертикальные световые окна смотрят на фасад −Y
            step = depth / teeth
            hw = width * 0.5
            for i in range(teeth):
                y_front = cy - depth * 0.5 + i * step
                y_back = y_front + step
                # Торцевые треугольники слева и справа
                for sign in (-1, 1):
                    xw = cx + sign * hw
                    self.add_poly(
                        [(xw, y_front, z0), (xw, y_back, z0), (xw, y_front, z0 + tooth_h)],
                        wall_swatch,
                        (sign, 0, 0),
                    )
                # Вертикальный витраж зуба (смотрит на −Y)
                self.box((cx, y_front + 0.02, z0 + tooth_h * 0.5), (width, 0.04, tooth_h), SLATE)
                panes = max(2, int(width / 0.48))
                pw = (width - 0.14) / panes
                for p in range(panes):
                    px = cx - (width - 0.14) * 0.5 + (p + 0.5) * pw
                    self.box((px, y_front - 0.004, z0 + tooth_h * 0.52), (pw * 0.78, 0.02, tooth_h * 0.68), GLASS_LITE)
                # Пологий скат от верха витража к низу следующего зуба
                slope_len = math.hypot(step, tooth_h) + 0.05
                ang = math.atan2(tooth_h, step)
                self.tilted_box(
                    (cx, (y_front + y_back) * 0.5, z0 + tooth_h * 0.5 + 0.02),
                    (width + 0.08, slope_len, 0.045),
                    roof_swatch,
                    pitch_x=-ang,
                )
        else:
            # Зубья вдоль ширины X
            step = width / teeth
            hd = depth * 0.5
            for i in range(teeth):
                x_left = cx - width * 0.5 + i * step
                x_right = x_left + step
                for sign in (-1, 1):
                    yw = cy + sign * hd
                    self.add_poly(
                        [(x_left, yw, z0), (x_right, yw, z0), (x_left, yw, z0 + tooth_h)],
                        wall_swatch,
                        (0, sign, 0),
                    )
                self.box((x_left + 0.02, cy, z0 + tooth_h * 0.5), (0.04, depth, tooth_h), SLATE)
                panes = max(2, int(depth / 0.48))
                pw = (depth - 0.14) / panes
                for p in range(panes):
                    py = cy - (depth - 0.14) * 0.5 + (p + 0.5) * pw
                    self.box((x_left - 0.004, py, z0 + tooth_h * 0.52), (0.02, pw * 0.78, tooth_h * 0.68), GLASS_LITE)
                slope_len = math.hypot(step, tooth_h) + 0.05
                ang = math.atan2(tooth_h, step)
                self.tilted_box(
                    ((x_left + x_right) * 0.5, cy, z0 + tooth_h * 0.5 + 0.02),
                    (slope_len, depth + 0.08, 0.045),
                    roof_swatch,
                    roll_y=ang,
                )

    def barrel_roof(self, cx, cy, z0, width, depth, arch_h, roof_swatch=ALUM, end_swatch=WALL,
                    rib_swatch=STEEL, segments=10, ribs=4):
        """Полукруглый арочный свод ангара/цеха вдоль глубины Y с внешними стальными рёбрами."""
        hw, hd = width * 0.5, depth * 0.5 + 0.05
        arc = []
        for i in range(segments + 1):
            t = math.pi * i / segments
            # от +hw (i=0) через верх (i=segments/2) к -hw (i=segments)
            x = cx + hw * math.cos(t)
            z = z0 + arch_h * math.sin(t)
            arc.append((x, z))

        # Сводчатая оболочка
        for i in range(segments):
            x0, z_a = arc[i]
            x1, z_b = arc[i + 1]
            mx = (x0 + x1) * 0.5 - cx
            mz = (z_a + z_b) * 0.5 - z0
            self.add_poly(
                [(x0, cy - hd, z_a), (x1, cy - hd, z_b), (x1, cy + hd, z_b), (x0, cy + hd, z_a)],
                roof_swatch,
                (mx, 0.0, max(0.1, mz)),
            )

        # Торцевые люнеты (±Y)
        for sign in (-1, 1):
            yw = cy + sign * (depth * 0.5)
            poly = [(x, yw, z) for (x, z) in arc]
            self.add_poly(poly, end_swatch, (0, sign, 0))

        # Внешние арочные дуги-рёбра
        if ribs >= 2:
            for r in range(ribs):
                ry = cy - depth * 0.46 + (depth * 0.92) * (r / (ribs - 1))
                for i in range(segments):
                    x0, z_a = arc[i]
                    x1, z_b = arc[i + 1]
                    seg_len = math.hypot(x1 - x0, z_b - z_a) + 0.015
                    ang = math.atan2(z_b - z_a, x1 - x0)
                    mx, mz = (x0 + x1) * 0.5, (z_a + z_b) * 0.5
                    nx, nz = -(z_b - z_a), (x1 - x0)
                    nl = max(1e-5, math.hypot(nx, nz))
                    if nz < 0:
                        nx, nz = -nx, -nz
                    self.tilted_box(
                        (mx + nx / nl * 0.025, ry, mz + nz / nl * 0.025),
                        (seg_len, 0.06, 0.05),
                        rib_swatch,
                        roll_y=-ang,
                    )

    # --- Фасады, окна, витрины, балконы и детали ---

    def facade_box(self, center, size, swatch, out_xy, grad=False):
        """Настенная рельефная деталь без невидимой задней грани (экономит полигоны)."""
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        if hx <= 1e-5 or hy <= 1e-5 or hz <= 1e-5:
            return
        ox, oy = out_xy
        pts = [
            (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
            (cx - hx, cy + hy, cz - hz), (cx + hx, cy + hy, cz - hz),
            (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
            (cx - hx, cy + hy, cz + hz), (cx + hx, cy + hy, cz + hz),
        ]
        self.add_poly([pts[0], pts[2], pts[3], pts[1]], swatch, (0, 0, -1), grad=grad)
        self.add_poly([pts[4], pts[5], pts[7], pts[6]], swatch, (0, 0, 1), grad=grad)
        if oy <= 0.5:
            self.add_poly([pts[0], pts[1], pts[5], pts[4]], swatch, (0, -1, 0), grad=grad)
        if oy >= -0.5:
            self.add_poly([pts[3], pts[2], pts[6], pts[7]], swatch, (0, 1, 0), grad=grad)
        if ox <= 0.5:
            self.add_poly([pts[2], pts[0], pts[4], pts[6]], swatch, (-1, 0, 0), grad=grad)
        if ox >= -0.5:
            self.add_poly([pts[1], pts[3], pts[7], pts[5]], swatch, (1, 0, 0), grad=grad)

    def facade_quad(self, x, y, z, out_xy, along, height, swatch, grad=False):
        """Плоская фасадная вставка (стекло внутри рамы) — всего 1 квад (2 треугольника)."""
        ox, oy = out_xy
        hw, hh = along * 0.5, height * 0.5
        if abs(oy) > 0.5:
            pts = [(x - hw, y, z - hh), (x + hw, y, z - hh), (x + hw, y, z + hh), (x - hw, y, z + hh)]
        else:
            pts = [(x, y - hw, z - hh), (x, y + hw, z - hh), (x, y + hw, z + hh), (x, y - hw, z + hh)]
        self.add_poly(pts, swatch, (ox, oy, 0.0), grad=grad)

    def window_unit(self, x, y, z, out_xy, w, h, frame_swatch=SLATE, sill_swatch=STONE,
                    glass_swatch=GLASS_DARK, mullion=True, balcony=False, shutters=False):
        """Объёмное окно с рамой, двухтоновым стеклом, подоконником и опциональным балконом/ставнями."""
        ox, oy = out_xy
        along_x = abs(oy) > 0.5

        def span(along, thick, height):
            return (along, thick, height) if along_x else (thick, along, height)

        self.facade_box((x + ox * 0.012, y + oy * 0.012, z), span(w, 0.028, h), frame_swatch, out_xy)
        gx, gy = x + ox * 0.028, y + oy * 0.028
        self.facade_quad(gx, gy, z - h * 0.09, out_xy, w * 0.80, h * 0.64, glass_swatch)
        self.facade_quad(gx, gy, z + h * 0.25, out_xy, w * 0.80, h * 0.20, GLASS_LITE)
        if mullion and w >= 0.20:
            self.facade_quad(x + ox * 0.031, y + oy * 0.031, z, out_xy, 0.022, h * 0.84, frame_swatch)

        self.facade_box((x + ox * 0.030, y + oy * 0.030, z - h * 0.52), span(w + 0.05, 0.052, 0.032), sill_swatch, out_xy)

        if shutters:
            sw = w * 0.24
            for sign in (-1, 1):
                sx = x + (sign * (w * 0.5 + sw * 0.55) if along_x else ox * 0.016)
                sy = y + (oy * 0.016 if along_x else sign * (w * 0.5 + sw * 0.55))
                self.facade_box((sx, sy, z), span(sw, 0.024, h * 0.94), ROOF_DEEP, out_xy)

        if balcony:
            bw, bd = w * 1.28, 0.18
            bz = z - h * 0.54
            self.facade_box((x + ox * (bd * 0.5), y + oy * (bd * 0.5), bz), span(bw, bd, 0.045), STONE, out_xy)
            rh = 0.14
            self.box((x + ox * (bd - 0.015), y + oy * (bd - 0.015), bz + rh * 0.5 + 0.02),
                     span(bw, 0.022, rh), IRON, skip_bottom=True)
            self.box((x + ox * (bd - 0.015), y + oy * (bd - 0.015), bz + rh + 0.025),
                     span(bw + 0.02, 0.032, 0.024), STEEL)
            for sign in (-1, 1):
                cx_s = x + (sign * (bw * 0.5 - 0.012) if along_x else ox * bd * 0.5)
                cy_s = y + (oy * bd * 0.5 if along_x else sign * (bw * 0.5 - 0.012))
                self.box((cx_s, cy_s, bz + rh * 0.5 + 0.02),
                         (0.022, bd, rh) if along_x else (bd, 0.022, rh), IRON, skip_bottom=True)

    def window_grid_wall(self, cx, cy, z0, length, floors, floor_h, out_xy,
                         win_w=0.24, win_h=0.25, step=0.44, start_floor=1,
                         frame_swatch=SLATE, sill_swatch=STONE, belt_swatch=STONE,
                         balconies="none", shutters=False, margin=0.16):
        """Регулярная сетка окон на одной стене с межэтажными поясами и балконами."""
        usable = length - margin * 2.0
        if usable < win_w:
            return
        cols = max(1, int(usable / step))
        ox, oy = out_xy
        along_x = abs(oy) > 0.5

        for fl in range(start_floor, floors):
            zf = z0 + fl * floor_h
            if belt_swatch is not None and fl > 0:
                self.facade_box(
                    (cx + ox * 0.012, cy + oy * 0.012, zf),
                    (length + 0.02, 0.028, 0.032) if along_x else (0.028, length + 0.02, 0.032),
                    belt_swatch,
                    out_xy,
                )
            zw = zf + floor_h * 0.54
            for i in range(cols):
                t = ((i + 0.5) / cols - 0.5) * usable
                wx = cx + (t if along_x else 0.0)
                wy = cy + (0.0 if along_x else t)
                has_bal = (
                    (balconies == "checker" and (fl + i) % 2 == 1)
                    or (balconies == "alt_floors" and fl % 2 == 1 and i % 2 == 0)
                    or (balconies == "all" and fl >= 1)
                    or (balconies == "center" and abs(i - (cols - 1) * 0.5) < 0.6 and fl >= 1)
                )
                self.window_unit(
                    wx, wy, zw, out_xy, win_w, win_h,
                    frame_swatch=frame_swatch, sill_swatch=sill_swatch,
                    balcony=has_bal, shutters=shutters,
                )

    def box_windows_4sides(self, cx, cy, z0, width, depth, floors, floor_h,
                           win_w=0.24, win_h=0.25, step=0.44, start_floor=1,
                           frame_swatch=SLATE, sill_swatch=STONE, belt_swatch=STONE,
                           front_balconies="none", back_balconies="none"):
        """Окна на всех четырёх фасадах прямоугольного объёма."""
        self.window_grid_wall(cx, cy - depth * 0.5, z0, width, floors, floor_h, (0, -1),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch, front_balconies)
        self.window_grid_wall(cx, cy + depth * 0.5, z0, width, floors, floor_h, (0, 1),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch, back_balconies)
        self.window_grid_wall(cx - width * 0.5, cy, z0, depth, floors, floor_h, (-1, 0),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch, "none")
        self.window_grid_wall(cx + width * 0.5, cy, z0, depth, floors, floor_h, (1, 0),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch, "none")

    def chamfer_windows_4sides(self, cx, cy, z0, width, depth, chamfer, floors, floor_h,
                               win_w=0.23, win_h=0.25, step=0.42, start_floor=1,
                               frame_swatch=SLATE, sill_swatch=STONE, belt_swatch=STONE,
                               front_balconies="none", back_balconies="none"):
        """Окна точно на наружных гранях восьмигранной призмы chamfer_prism."""
        c = min(chamfer, width * 0.425, depth * 0.425)
        flat_w = max(0.30, width - c * 2.0)
        flat_d = max(0.30, depth - c * 2.0)
        self.window_grid_wall(cx, cy - depth * 0.5, z0, flat_w, floors, floor_h, (0, -1),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch,
                              front_balconies, margin=0.06)
        self.window_grid_wall(cx, cy + depth * 0.5, z0, flat_w, floors, floor_h, (0, 1),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch,
                              back_balconies, margin=0.06)
        self.window_grid_wall(cx - width * 0.5, cy, z0, flat_d, floors, floor_h, (-1, 0),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch,
                              "none", margin=0.06)
        self.window_grid_wall(cx + width * 0.5, cy, z0, flat_d, floors, floor_h, (1, 0),
                              win_w, win_h, step, start_floor, frame_swatch, sill_swatch, belt_swatch,
                              "none", margin=0.06)

    def _curtain_side(self, sx, sy, z0, span_len, out_xy, floors, floor_h, mullion_step, frame_swatch, spandrel_swatch):
        total_h = floors * floor_h
        ox, oy = out_xy
        along_x = abs(oy) > 0.5
        usable = max(0.22, span_len)
        bays = max(1, int(usable / mullion_step))
        bay_w = usable / bays

        for k in range(bays + 1):
            t = -usable * 0.5 + k * bay_w
            mx = sx + (t if along_x else ox * 0.018)
            my = sy + (oy * 0.018 if along_x else t)
            self.facade_box((mx, my, z0 + total_h * 0.5),
                            (0.028, 0.032, total_h) if along_x else (0.032, 0.028, total_h),
                            frame_swatch, out_xy)

        for fl in range(floors):
            zf = z0 + fl * floor_h
            self.facade_box(
                (sx + ox * 0.014, sy + oy * 0.014, zf + 0.034),
                (usable + 0.01, 0.026, 0.064) if along_x else (0.026, usable + 0.01, 0.064),
                spandrel_swatch,
                out_xy,
            )
            pane_h = floor_h - 0.072
            zp = zf + 0.068 + pane_h * 0.5
            for k in range(bays):
                t = -usable * 0.5 + (k + 0.5) * bay_w
                px = sx + (t if along_x else ox * 0.015)
                py = sy + (oy * 0.015 if along_x else t)
                gl = GLASS_LITE if (fl + k) % 3 == 0 else GLASS_DARK
                self.facade_quad(px, py, zp, out_xy, bay_w - 0.024, pane_h, gl, grad=True)

    def curtain_wall_4sides(self, cx, cy, z0, width, depth, floors, floor_h,
                            mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=SLATE, corner_pilasters=True,
                            pilaster_swatch=WALL):
        """Офисный стеклянный витраж (curtain wall) на прямоугольном объёме width × depth."""
        total_h = floors * floor_h
        inset = 0.20 if corner_pilasters else 0.08
        self._curtain_side(cx, cy - depth * 0.5, z0, width - inset, (0, -1), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)
        self._curtain_side(cx, cy + depth * 0.5, z0, width - inset, (0, 1), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)
        self._curtain_side(cx - width * 0.5, cy, z0, depth - inset, (-1, 0), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)
        self._curtain_side(cx + width * 0.5, cy, z0, depth - inset, (1, 0), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)

        if corner_pilasters:
            pw = 0.11
            for sx_s in (-1, 1):
                for sy_s in (-1, 1):
                    self.box(
                        (cx + sx_s * (width * 0.5 - pw * 0.35), cy + sy_s * (depth * 0.5 - pw * 0.35), z0 + total_h * 0.5),
                        (pw, pw, total_h + 0.02),
                        pilaster_swatch,
                        skip_bottom=True,
                    )

    def chamfer_curtain_wall(self, cx, cy, z0, width, depth, chamfer, floors, floor_h,
                             mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=SLATE, glazed_corners=True):
        """Витражное остекление точно на внешних гранях (включая скошенные углы!) восьмигранной призмы."""
        c = min(chamfer, width * 0.425, depth * 0.425)
        flat_w = max(0.24, width - c * 2.0 - 0.06)
        flat_d = max(0.24, depth - c * 2.0 - 0.06)
        self._curtain_side(cx, cy - depth * 0.5, z0, flat_w, (0, -1), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)
        self._curtain_side(cx, cy + depth * 0.5, z0, flat_w, (0, 1), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)
        self._curtain_side(cx - width * 0.5, cy, z0, flat_d, (-1, 0), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)
        self._curtain_side(cx + width * 0.5, cy, z0, flat_d, (1, 0), floors, floor_h, mullion_step, frame_swatch, spandrel_swatch)

        if glazed_corners and c >= 0.14:
            hx, hy = width * 0.5, depth * 0.5
            corners = [
                ((cx + hx - c, cy - hy), (cx + hx, cy - hy + c), (1, -1)),
                ((cx + hx, cy + hy - c), (cx + hx - c, cy + hy), (1, 1)),
                ((cx - hx + c, cy + hy), (cx - hx, cy + hy - c), (-1, 1)),
                ((cx - hx, cy - hy + c), (cx - hx + c, cy - hy), (-1, -1)),
            ]
            for (x1, y1), (x2, y2), (nx, ny) in corners:
                nl = math.hypot(nx, ny)
                ox, oy = nx / nl * 0.014, ny / nl * 0.014
                ux, uy = x1 + (x2 - x1) * 0.14 + ox, y1 + (y2 - y1) * 0.14 + oy
                vx, vy = x1 + (x2 - x1) * 0.86 + ox, y1 + (y2 - y1) * 0.86 + oy
                for fl in range(floors):
                    zf = z0 + fl * floor_h + 0.065
                    zt = z0 + (fl + 1) * floor_h - 0.012
                    gl = GLASS_LITE if fl % 2 == 0 else GLASS_DARK
                    self.add_poly([(ux, uy, zf), (vx, vy, zf), (vx, vy, zt), (ux, uy, zt)], gl, (nx, ny, 0.0), grad=True)

    def entrance_canopy(self, x, y_wall, z0, w=0.52, h=0.40, canopy_d=0.22, canopy_swatch=ROOF, door_swatch=IRON):
        """Входная группа на лицевом фасаде (−Y): портал, двустворчатая дверь со стеклом, ступень и козырёк."""
        # Ступень крыльца
        self.box((x, y_wall - 0.09, z0 + 0.025), (w + 0.16, 0.20, 0.05), STONE)
        # Портал и дверь
        self.box((x, y_wall - 0.015, z0 + h * 0.5 + 0.04), (w, 0.04, h), SLATE)
        self.box((x, y_wall - 0.025, z0 + h * 0.48 + 0.04), (w * 0.78, 0.03, h * 0.88), door_swatch)
        for sign in (-1, 1):
            self.box((x + sign * w * 0.18, y_wall - 0.032, z0 + h * 0.54 + 0.04),
                     (w * 0.26, 0.02, h * 0.62), GLASS_LITE)
        # Козырёк с боковыми тягами
        cz = z0 + h + 0.07
        self.box((x, y_wall - canopy_d * 0.5, cz), (w + 0.18, canopy_d, 0.045), canopy_swatch)
        self.box((x, y_wall - canopy_d + 0.015, cz + 0.015), (w + 0.20, 0.03, 0.03), STONE)

    def storefront_strip(self, cx, y_wall, z0, width, h=0.44, bays=3, awning_swatch=ROOF):
        """Ряд уличных витрин с маркизами/навесами на 1-м этаже."""
        usable = width - 0.24
        bw = usable / max(1, bays)
        for i in range(bays):
            bx = cx - usable * 0.5 + (i + 0.5) * bw
            is_door = (i == bays // 2)
            if is_door:
                self.entrance_canopy(bx, y_wall, z0, w=min(0.46, bw * 0.78), h=h * 0.86,
                                     canopy_d=0.18, canopy_swatch=awning_swatch)
            else:
                self.box((bx, y_wall - 0.014, z0 + h * 0.52), (bw * 0.84, 0.03, h * 0.72), SLATE)
                self.box((bx, y_wall - 0.022, z0 + h * 0.52), (bw * 0.74, 0.024, h * 0.60), GLASS_LITE)
                self.box((bx, y_wall - 0.03, z0 + h * 0.14), (bw * 0.88, 0.045, 0.04), STONE)
                # Наклонная маркиза над витриной
                self.tilted_box((bx, y_wall - 0.09, z0 + h * 0.92), (bw * 0.86, 0.20, 0.035),
                                awning_swatch, pitch_x=0.36)

    def loading_dock(self, x, y_wall, z0, out_xy=(0, -1), w=0.58, h=0.48, canopy_swatch=TERRACOTTA):
        """Грузовые секционные ворота завода/склада с отбойниками и козырьком."""
        ox, oy = out_xy
        along_x = abs(oy) > 0.5

        def span(a, t, hz):
            return (a, t, hz) if along_x else (t, a, hz)

        # Бетонная рампа и жёлто-оранжевые защитные тумбы-отбойники
        self.box((x + ox * 0.09, y + oy * 0.09 if False else y_wall + oy * 0.09, z0 + 0.04),
                 span(w + 0.18, 0.20, 0.08), CONCRETE)
        # Рама ворот и рельефные секции роллет
        self.box((x + ox * 0.015, y_wall + oy * 0.015, z0 + 0.08 + h * 0.5), span(w, 0.04, h), SLATE)
        slats = 4
        sh = (h - 0.06) / slats
        for s in range(slats):
            sz = z0 + 0.10 + (s + 0.5) * sh
            sw_col = ALUM if s % 2 == 0 else STEEL
            self.box((x + ox * 0.026, y_wall + oy * 0.026, sz), span(w * 0.86, 0.026, sh * 0.82), sw_col)
        # Козырёк и тумбы по краям
        self.box((x + ox * 0.11, y_wall + oy * 0.11, z0 + 0.10 + h + 0.04), span(w + 0.14, 0.22, 0.045), canopy_swatch)
        for sign in (-1, 1):
            bx = x + (sign * (w * 0.5 + 0.07) if along_x else ox * 0.16)
            by = y_wall + (oy * 0.16 if along_x else sign * (w * 0.5 + 0.07))
            self.box((bx, by, z0 + 0.11), (0.055, 0.055, 0.22), TERRACOTTA)

    def smokestack(self, x, y, z0, height, r_base=0.22, r_top=0.13, body_swatch=BRICK, stripe_swatch=TERRACOTTA):
        """Конусная заводская труба с цоколем, сигнальными кольцами и оголовком."""
        self.box((x, y, z0 + 0.14), (r_base * 2.5, r_base * 2.5, 0.28), GUNMETAL)
        self.cylinder((x, y, z0 + height * 0.5), r_base, r_top, height, body_swatch, segments=14)
        # Два сигнальных кольца в верхней трети трубы
        for frac in (0.74, 0.88):
            rk = r_base + (r_top - r_base) * frac + 0.012
            self.cylinder((x, y, z0 + height * frac), rk, rk * 0.98, height * 0.065, stripe_swatch, segments=14)
        # Оголовок и тёмное устье
        self.cylinder((x, y, z0 + height + 0.035), r_top * 1.18, r_top * 1.15, 0.07, IRON, segments=14)

    def chimney_home(self, x, y, z0, h=0.45, swatch=BRICK):
        """Домашний кирпичный дымоход с карнизной шапкой."""
        self.box((x, y, z0 + h * 0.5), (0.16, 0.16, h), swatch)
        self.box((x, y, z0 + h + 0.025), (0.21, 0.21, 0.05), STONE)
        self.cylinder((x, y, z0 + h + 0.08), 0.045, 0.045, 0.08, IRON, segments=8)

    def rooftop_hvac(self, x, y, z0, scale=1.0):
        """Крышный блок вентиляции / чиллер с двумя вентиляторами и воздуховодом."""
        w, d, h = 0.48 * scale, 0.34 * scale, 0.20 * scale
        self.box((x, y, z0 + h * 0.5), (w, d, h), ALUM)
        self.box((x, y, z0 + h + 0.015), (w + 0.03, d + 0.03, 0.03), SLATE)
        for sign in (-1, 1):
            fx = x + sign * w * 0.24
            self.cylinder((fx, y, z0 + h + 0.04), 0.09 * scale, 0.09 * scale, 0.04, IRON, segments=10)
            self.cylinder((fx, y, z0 + h + 0.05), 0.06 * scale, 0.06 * scale, 0.042, STEEL, segments=8)

    def solar_bank(self, cx, cy, z0, rows=2, cols=3, panel_w=0.38, panel_d=0.26):
        """Ряд наклонных солнечных панелей на плоской или пологой крыше."""
        step_x = panel_w + 0.06
        step_y = panel_d + 0.12
        for r in range(rows):
            py = cy + (r - (rows - 1) * 0.5) * step_y
            for c in range(cols):
                px = cx + (c - (cols - 1) * 0.5) * step_x
                self.box((px, py, z0 + 0.04), (0.04, 0.04, 0.08), STEEL)
                self.tilted_box((px, py, z0 + 0.095), (panel_w, panel_d, 0.026), SLATE, pitch_x=0.38)
                self.tilted_box((px, py - 0.004, z0 + 0.108), (panel_w * 0.90, panel_d * 0.86, 0.016),
                                GLASS_DARK, pitch_x=0.38)

    def helipad(self, cx, cy, z0, size=1.05):
        """Крышная вертолётная площадка на опорах с буквой H и сигнальными огнями по углам."""
        self.box((cx, cy, z0 + 0.04), (size * 0.78, size * 0.78, 0.08), STEEL)
        self.chamfer_prism(cx, cy, z0 + 0.08, size, size, 0.055, size * 0.18, GUNMETAL)
        # Кольцо разметки и буква H
        self.cylinder((cx, cy, z0 + 0.140), size * 0.39, size * 0.39, 0.014, TERRACOTTA, segments=16)
        self.cylinder((cx, cy, z0 + 0.145), size * 0.33, size * 0.33, 0.014, GUNMETAL, segments=16)
        hw = size * 0.14
        for sign in (-1, 1):
            self.box((cx + sign * hw, cy, z0 + 0.156), (0.065, size * 0.34, 0.016), WALL, grad=False)
        self.box((cx, cy, z0 + 0.156), (hw * 2.0, 0.065, 0.016), WALL, grad=False)
        for sx in (-1, 1):
            for sy in (-1, 1):
                self.box((cx + sx * size * 0.40, cy + sy * size * 0.40, z0 + 0.16), (0.05, 0.05, 0.04), ROOF_LITE)

    def gantry_crane(self, cx, cy, z0, span_x, length_y, height, swatch=TERRACOTTA):
        """Козловой/мостовой кран открытого заводского двора с рельсами, стойками и тельфером."""
        hx, hy = span_x * 0.5, length_y * 0.5
        # Подкрановые рельсы
        for sign in (-1, 1):
            self.box((cx + sign * hx, cy, z0 + 0.025), (0.06, length_y, 0.05), IRON)
        # Две А-образные опоры портала
        bridge_y = cy - length_y * 0.12
        for sign in (-1, 1):
            lx = cx + sign * hx
            for dy_s in (-1, 1):
                self.tilted_box(
                    (lx, bridge_y + dy_s * 0.16, z0 + height * 0.5),
                    (0.08, 0.08, height * 1.03),
                    swatch,
                    pitch_x=dy_s * 0.14,
                )
            self.box((lx, bridge_y, z0 + height * 0.55), (0.07, 0.32, 0.06), swatch)
        # Главная двутавровая балка моста и кабина тельфера
        self.box((cx, bridge_y, z0 + height + 0.07), (span_x + 0.28, 0.22, 0.14), swatch)
        self.box((cx, bridge_y, z0 + height + 0.16), (span_x + 0.30, 0.28, 0.04), IRON)
        tx = cx + span_x * 0.14
        self.box((tx, bridge_y, z0 + height - 0.06), (0.30, 0.30, 0.16), SLATE)
        self.cylinder((tx, bridge_y, z0 + height * 0.62), 0.02, 0.02, height * 0.55, IRON, segments=6)
        self.box((tx, bridge_y, z0 + height * 0.32), (0.14, 0.14, 0.10), TERRACOTTA)

    def horizontal_tank(self, cx, cy, z0, radius, length, swatch=ALUM, band_swatch=TERRACOTTA, axis="x"):
        """Горизонтальная промышленная цистерна на двух бетонных седловых опорах."""
        zc = z0 + radius + 0.16
        off = length * 0.30
        for sign in (-1, 1):
            sx = cx + (sign * off if axis == "x" else 0.0)
            sy = cy + (0.0 if axis == "x" else sign * off)
            self.box(
                (sx, sy, z0 + (radius * 0.55 + 0.16) * 0.5),
                (0.14, radius * 1.55, radius * 0.55 + 0.16) if axis == "x" else (radius * 1.55, 0.14, radius * 0.55 + 0.16),
                CONCRETE,
            )
        self.cylinder((cx, cy, zc), radius, radius, length, swatch, axis=axis, segments=14)
        for sign in (-1, 1):
            bx = cx + (sign * length * 0.24 if axis == "x" else 0.0)
            by = cy + (0.0 if axis == "x" else sign * length * 0.24)
            self.cylinder((bx, by, zc), radius * 1.03, radius * 1.03, 0.08, band_swatch, axis=axis, segments=14)
        # Верхний люк
        self.cylinder((cx, cy, zc + radius + 0.04), 0.08, 0.08, 0.09, STEEL, segments=8)

    def pave_base(self, width, depth, swatch=STONE, border_swatch=CONCRETE, h=0.03):
        """Аккуратная плита мощения участка с бордюром."""
        self.box((0.0, 0.0, h * 0.45), (width, depth, h * 0.9), border_swatch)
        self.box((0.0, 0.0, h * 0.75), (width - 0.10, depth - 0.10, h * 0.5), swatch)

    # --- Сборка, проверка границ участка и экспорт ---

    def fit_to_lot(self, cells_w, cells_d, margin=0.22):
        """Центрирует модель по X/Y, ставит основание точно на Z=0 и следит за габаритами клеток."""
        if not self.verts:
            return (0.0, 0.0, 0.0)
        xs = [v[0] for v in self.verts]
        ys = [v[1] for v in self.verts]
        zs = [v[2] for v in self.verts]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        min_z, max_z = min(zs), max(zs)

        cx = (min_x + max_x) * 0.5
        cy = (min_y + max_y) * 0.5
        span_x = max_x - min_x
        span_y = max_y - min_y

        max_w = cells_w * CELL - margin
        max_d = cells_d * CELL - margin
        sx = min(1.0, max_w / span_x) if span_x > 1e-5 else 1.0
        sy = min(1.0, max_d / span_y) if span_y > 1e-5 else 1.0
        s_xy = min(sx, sy)

        self.verts = [
            ((x - cx) * s_xy, (y - cy) * s_xy, (z - min_z) * s_xy)
            for (x, y, z) in self.verts
        ]
        xs = [v[0] for v in self.verts]
        ys = [v[1] for v in self.verts]
        zs = [v[2] for v in self.verts]
        return (round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3))

    def build_object(self):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        uv_layer = mesh.uv_layers.new(name="UVMap")
        for poly, uvs in zip(mesh.polygons, self.loop_uvs):
            for loop_idx, uv in zip(poly.loop_indices, uvs):
                uv_layer.data[loop_idx].uv = uv
        for poly in mesh.polygons:
            poly.use_smooth = False
        mesh.materials.append(self.material)
        mesh.validate()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj

    def export_pack_glb(self, category, cells_w, cells_d):
        """Подгоняет в габариты участка и сохраняет в assets/models/blender/pack/<category>/<name>.glb."""
        dims = self.fit_to_lot(cells_w, cells_d)
        obj = self.build_object()
        out_folder = os.path.join(PACK_DIR, category)
        os.makedirs(out_folder, exist_ok=True)
        filepath = os.path.join(out_folder, f"{self.name}.glb")
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
        print(f"PACK [{category}] {self.name} ({cells_w}x{cells_d}) -> dims={dims}m verts={verts} tris={tris}")
        return {
            "id": self.name,
            "category": category,
            "file": f"assets/models/blender/pack/{category}/{self.name}.glb",
            "godot_kit_path": f"blender/pack/{category}/{self.name}",
            "cells": [cells_w, cells_d],
            "area_cells": cells_w * cells_d,
            "dimensions_m": list(dims),
            "vertices": verts,
            "triangles": tris,
        }
