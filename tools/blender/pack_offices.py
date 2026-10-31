"""Пак офисных и деловых зданий (15 моделей от 1×1 до 7×1 и 3×2) для CityBuilder."""

import math

from arch_kit import (
    ALUM,
    ArchBuilder,
    BRICK,
    CHARCOAL,
    CONCRETE,
    COPPER,
    CREAM,
    GLASS_DARK,
    GLASS_LITE,
    GUNMETAL,
    IRON,
    ROOF,
    ROOF_LITE,
    SANDSTONE,
    SLATE,
    STEEL,
    STONE,
    TERRACOTTA,
    WALL,
    clear_scene,
)


def _colonnade_front(b: ArchBuilder, cx, y_front, z0, width, height, cols=6, col_swatch=STONE):
    """Парадная колоннада вдоль уличного фасада (−Y)."""
    usable = width - 0.20
    for i in range(cols):
        px = cx - usable * 0.5 + usable * (i / max(1, cols - 1))
        b.box((px, y_front, z0 + height * 0.5), (0.11, 0.11, height), col_swatch)
        b.box((px, y_front, z0 + 0.05), (0.15, 0.15, 0.09), STONE)
        b.box((px, y_front, z0 + height - 0.04), (0.15, 0.15, 0.08), STONE)


def _diagrid_frame(b: ArchBuilder, cx, cy, z0, width, depth, tiers, tier_h, swatch=ALUM):
    """Внешний ромбовидный стальной каркас (diagrid) на четырёх фасадах башни."""
    sides = [
        (cx, cy - depth * 0.5 - 0.02, width - 0.24, True),
        (cx, cy + depth * 0.5 + 0.02, width - 0.24, True),
        (cx - width * 0.5 - 0.02, cy, depth - 0.24, False),
        (cx + width * 0.5 + 0.02, cy, depth - 0.24, False),
    ]
    for sx, sy, span, along_x in sides:
        cells = max(1, int(span / 0.55))
        cw = span / cells
        diag_len = math.hypot(cw, tier_h)
        ang = math.atan2(cw, tier_h)
        for t in range(tiers):
            zc = z0 + (t + 0.5) * tier_h
            for c in range(cells):
                off = -span * 0.5 + (c + 0.5) * cw
                for sign in (-1, 1):
                    if along_x:
                        b.tilted_box((sx + off, sy, zc), (0.036, 0.036, diag_len), swatch, roll_y=sign * ang)
                    else:
                        b.tilted_box((sx, sy + off, zc), (0.036, 0.036, diag_len), swatch, pitch_x=sign * ang)


# ---------------------------------------------------------------------------
# 1. Бутик-офис / архитектурное бюро 1×1 (O, ур. 1)
# ---------------------------------------------------------------------------
def build_off_boutique_1x1():
    clear_scene()
    b = ArchBuilder("off_boutique_1x1")
    b.pave_base(1.72, 1.72, swatch=STONE, border_swatch=CONCRETE)
    w, d, floors, fh = 1.40, 1.34, 4, 0.48
    h = floors * fh
    b.box((0, 0.04, h * 0.5), (w, d, h), BRICK)
    b.curtain_wall_4sides(0, 0.04, 0.03, w, d, floors, fh, mullion_step=0.40,
                          frame_swatch=SLATE, spandrel_swatch=CHARCOAL, corner_pilasters=True, pilaster_swatch=BRICK)
    # Солнцезащитные вертикальные ламели из тёплого дерева/песчаника на фасаде
    for i in range(6):
        lx = -0.50 + i * 0.20
        b.box((lx, 0.04 - d * 0.5 - 0.03, fh + (h - fh) * 0.5), (0.032, 0.06, h - fh - 0.06), SANDSTONE)
    b.entrance_canopy(0.0, 0.04 - d * 0.5, 0.03, w=0.58, h=0.44, canopy_d=0.22, canopy_swatch=ROOF)
    b.box((0, 0.04, h + 0.04), (w + 0.08, d + 0.08, 0.08), STONE)
    b.rooftop_hvac(-0.28, 0.16, h + 0.08, scale=0.80)
    b.solar_bank(0.28, 0.06, h + 0.08, rows=2, cols=1, panel_w=0.44, panel_d=0.28)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 2. Башня ар-деко со шпилем 1×1 (O, ур. 2)
# ---------------------------------------------------------------------------
def build_off_artdeco_spire_1x1():
    clear_scene()
    b = ArchBuilder("off_artdeco_spire_1x1")
    b.pave_base(1.74, 1.74, swatch=SANDSTONE, border_swatch=STONE)
    fh = 0.44
    # Три высотных яруса с классическими уступами (setbacks)
    tiers = [
        (1.52, 1.52, 3, CREAM),
        (1.24, 1.24, 5, CREAM),
        (0.92, 0.92, 3, WALL),
    ]
    z = 0.03
    for idx, (tw, td, fls, sw) in enumerate(tiers):
        th = fls * fh
        b.chamfer_prism(0, 0, z, tw, td, th, 0.18, sw)
        b.chamfer_curtain_wall(0, 0, z, tw, td, 0.18, fls, fh, mullion_step=0.34,
                               frame_swatch=COPPER, spandrel_swatch=GUNMETAL, glazed_corners=False)
        # Вертикальные каменные рёбра ар-деко
        for sign in (-1, 1):
            b.box((sign * tw * 0.24, 0, z + th * 0.5 + 0.04), (0.07, td + 0.05, th + 0.08), STONE)
            b.box((0, sign * td * 0.24, z + th * 0.5 + 0.04), (tw + 0.05, 0.07, th + 0.08), STONE)
        b.chamfer_prism(0, 0, z + th, tw + 0.06, td + 0.06, 0.06, 0.18, COPPER if idx == 2 else STONE)
        z += th + 0.06
    b.entrance_canopy(0.0, -0.76, 0.03, w=0.56, h=0.46, canopy_d=0.20, canopy_swatch=COPPER)
    # Ступенчатая медная корона и шпиль
    b.chamfer_prism(0, 0, z, 0.58, 0.58, 0.34, 0.14, ROOF)
    b.chamfer_prism(0, 0, z + 0.34, 0.34, 0.34, 0.26, 0.08, COPPER)
    b.cylinder((0, 0, z + 0.96), 0.035, 0.008, 0.76, COPPER, segments=8)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 3. Стеклянный небоскрёб с ромбовидным каркасом (Diagrid) 1×1 (O, ур. 3)
# ---------------------------------------------------------------------------
def build_off_diagrid_needle_1x1():
    clear_scene()
    b = ArchBuilder("off_diagrid_needle_1x1")
    b.pave_base(1.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.42
    floors = 15
    h = floors * fh
    # Высокий стеклянный вестибюль + восьмигранный ствол
    b.chamfer_prism(0, 0, 0.03, 1.50, 1.50, fh * 2, 0.26, SLATE)
    b.entrance_canopy(0, -0.75, 0.03, w=0.58, h=0.48, canopy_d=0.20, canopy_swatch=ALUM)
    z1 = 0.03 + fh * 2
    shaft_h = h - fh * 2
    b.chamfer_prism(0, 0, z1, 1.40, 1.40, shaft_h, 0.28, GLASS_DARK)
    b.chamfer_curtain_wall(0, 0, z1, 1.40, 1.40, 0.28, floors - 2, fh, mullion_step=0.36,
                           frame_swatch=ALUM, spandrel_swatch=SLATE)
    _diagrid_frame(b, 0, 0, z1, 1.40, 1.40, tiers=6, tier_h=shaft_h / 6.0, swatch=ALUM)
    # Скошенная стеклянная корона и антенная мачта
    zt = z1 + shaft_h
    b.chamfer_prism(0, 0, zt, 1.46, 1.46, 0.07, 0.28, ALUM)
    b.chamfer_prism(0, 0.06, zt + 0.07, 1.10, 1.10, 0.56, 0.22, GLASS_LITE)
    b.tilted_box((0, 0.04, zt + 0.66), (1.16, 1.22, 0.07), ROOF, pitch_x=0.28)
    b.cylinder((0.18, 0.14, zt + 1.16), 0.032, 0.01, 0.96, ALUM, segments=8)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 4. Стеклянный павильон на колоннаде 2×1 (O, ур. 1)
# ---------------------------------------------------------------------------
def build_off_glass_pavilion_2x1():
    clear_scene()
    b = ArchBuilder("off_glass_pavilion_2x1")
    b.pave_base(3.72, 1.72, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.46
    w, d = 3.40, 1.34
    # Заглублённый 1-й этаж с открытой колоннадой у улицы
    b.box((0, 0.12, fh * 0.6), (w - 0.34, d - 0.22, fh * 1.2), SLATE)
    _colonnade_front(b, 0, 0.04 - d * 0.5 + 0.06, 0.03, w, fh * 1.2, cols=6, col_swatch=ALUM)
    b.entrance_canopy(0.0, 0.12 - (d - 0.22) * 0.5, 0.03, w=0.68, h=0.44, canopy_d=0.22, canopy_swatch=ROOF)
    # Парящий 3-этажный стеклянный объём с солнцезащитными полками
    z1 = 0.03 + fh * 1.2
    uh = fh * 3
    b.box((0, 0.04, z1 + uh * 0.5), (w, d, uh), WALL)
    b.curtain_wall_4sides(0, 0.04, z1, w, d, 3, fh, mullion_step=0.42,
                          frame_swatch=ALUM, spandrel_swatch=SLATE, pilaster_swatch=WALL)
    for fl in range(1, 4):
        b.box((0, 0.04, z1 + fl * fh), (w + 0.12, d + 0.12, 0.045), ALUM)
    zt = z1 + uh + 0.04
    b.box((0, 0.04, zt + 0.03), (w + 0.08, d + 0.08, 0.06), ROOF)
    b.solar_bank(-0.78, 0.04, zt + 0.06, rows=2, cols=3, panel_w=0.38, panel_d=0.28)
    b.rooftop_hvac(1.06, 0.08, zt + 0.06, scale=0.95)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 5. Консольный бизнес-центр со сдвигом объёмов 2×1 (O, ур. 2)
# ---------------------------------------------------------------------------
def build_off_cantilever_2x1():
    clear_scene()
    b = ArchBuilder("off_cantilever_2x1")
    b.pave_base(3.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.44
    # Нижний 3-этажный корпус смещён влево
    h1 = fh * 3
    b.box((-0.34, 0.04, h1 * 0.5), (2.72, 1.34, h1), GUNMETAL)
    b.curtain_wall_4sides(-0.34, 0.04, 0.03, 2.72, 1.34, 3, fh, mullion_step=0.42, frame_swatch=ALUM, spandrel_swatch=SLATE)
    b.entrance_canopy(-0.54, 0.04 - 0.67, 0.03, w=0.66, h=0.44, canopy_d=0.22, canopy_swatch=ROOF)
    # Средний 3-этажный консольный блок выступает вправо над площадью с V-колонной!
    h2 = fh * 3
    b.box((0.36, 0.00, h1 + h2 * 0.5), (2.68, 1.38, h2), WALL)
    b.curtain_wall_4sides(0.36, 0.00, h1, 2.68, 1.38, 3, fh, mullion_step=0.40, frame_swatch=ALUM, spandrel_swatch=CHARCOAL, pilaster_swatch=WALL)
    # Наклонные V-опоры под консолью справа
    for sign in (-1, 1):
        b.tilted_box((1.34, 0.0 + sign * 0.34, h1 * 0.5), (0.09, 0.09, h1 * 1.04), ALUM, pitch_x=sign * 0.18)
    # Верхний 2-этажный пентхаус смещён к центру + террасы
    h3 = fh * 2
    z2 = h1 + h2
    b.box((-0.14, 0.06, z2 + h3 * 0.5), (1.96, 1.18, h3), CREAM)
    b.curtain_wall_4sides(-0.14, 0.06, z2, 1.96, 1.18, 2, fh, mullion_step=0.38, frame_swatch=STEEL, spandrel_swatch=SLATE, pilaster_swatch=CREAM)
    b.box((-0.14, 0.06, z2 + h3 + 0.04), (2.06, 1.26, 0.07), ROOF)
    b.rooftop_hvac(-0.54, 0.08, z2 + h3 + 0.08, scale=0.85)
    b.solar_bank(0.42, 0.06, z2 + h3 + 0.08, rows=2, cols=2, panel_w=0.34, panel_d=0.26)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 6. Парные офисные пластины с атриумом и вертолётной площадкой 2×1 (O, ур. 3)
# ---------------------------------------------------------------------------
def build_off_twin_slabs_2x1():
    clear_scene()
    b = ArchBuilder("off_twin_slabs_2x1")
    b.pave_base(3.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.42
    # Двухэтажный подиум на весь участок
    ph = fh * 2
    b.chamfer_prism(0, 0, 0.03, 3.48, 1.46, ph, 0.18, GUNMETAL)
    b.entrance_canopy(0.0, -0.73, 0.03, w=0.78, h=0.48, canopy_d=0.22, canopy_swatch=ROOF)
    # Две башни (12 и 10 этажей над подиумом) и прозрачная стеклянная шахта лифтов между ними
    zp = 0.03 + ph
    for sx, fls, sw in ((-0.98, 11, WALL), (0.98, 9, CREAM)):
        th = fls * fh
        b.chamfer_prism(sx, 0.02, zp, 1.38, 1.32, th, 0.16, sw)
        b.chamfer_curtain_wall(sx, 0.02, zp, 1.38, 1.32, 0.16, fls, fh, mullion_step=0.36,
                               frame_swatch=ALUM, spandrel_swatch=SLATE)
        b.chamfer_prism(sx, 0.02, zp + th, 1.44, 1.38, 0.07, 0.16, ROOF)
    # Центральное стеклянное ядро с мостиками
    ch = 9 * fh
    b.box((0.0, 0.04, zp + ch * 0.5), (0.64, 0.94, ch), GLASS_LITE)
    for fl in (2, 5, 8):
        b.box((0.0, 0.04, zp + fl * fh), (0.68, 0.98, 0.06), ALUM)
    # Вертолётная площадка на высокой левой башне
    b.helipad(-0.98, 0.02, zp + 11 * fh + 0.07, size=1.08)
    b.rooftop_hvac(0.98, 0.04, zp + 9 * fh + 0.07, scale=0.85)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 7. Представительский офис / Банк с колоннадой и атриумом 3×1 (O, ур. 1)
# ---------------------------------------------------------------------------
def build_off_colonnade_hq_3x1():
    clear_scene()
    b = ArchBuilder("off_colonnade_hq_3x1")
    b.pave_base(5.74, 1.74, swatch=SANDSTONE, border_swatch=STONE)
    fh, floors = 0.46, 5
    w, d = 5.40, 1.36
    h = floors * fh
    b.box((0, 0.06, h * 0.5), (w, d, h), CREAM)
    # Боковые стеклянные крылья и центральный двухсветный портик с колоннадой
    for sign in (-1, 1):
        b.curtain_wall_4sides(sign * 1.72, 0.06, 0.03, 1.82, d, floors, fh, mullion_step=0.40,
                              frame_swatch=COPPER, spandrel_swatch=SLATE, pilaster_swatch=CREAM)
    b.box((0, 0.06 - d * 0.5 - 0.08, h * 0.5), (1.76, 0.18, h), STONE)
    _colonnade_front(b, 0, 0.06 - d * 0.5 - 0.20, 0.03, 1.72, fh * 2.2, cols=4, col_swatch=STONE)
    b.entrance_canopy(0, 0.06 - d * 0.5 - 0.17, 0.03, w=0.66, h=0.48, canopy_d=0.18, canopy_swatch=COPPER)
    b.curtain_wall_4sides(0, 0.06, fh * 2.3, 1.50, d + 0.16, 3, fh * 0.88, mullion_step=0.38,
                          frame_swatch=COPPER, spandrel_swatch=GUNMETAL, corner_pilasters=False)
    # Карниз, аттик и стеклянная пирамида светового фонаря (как у биржи/музея)
    b.box((0, 0.06, h + 0.05), (w + 0.14, d + 0.14, 0.10), STONE)
    b.hip_roof(0, 0.06, h + 0.10, 1.56, 1.08, 0.46, roof_swatch=GLASS_LITE, fascia_swatch=ALUM, overhang=0.02, ridge_frac=0.25)
    for sign in (-1, 1):
        b.rooftop_hvac(sign * 1.85, 0.12, h + 0.10, scale=0.88)
    return b, 3, 1


# ---------------------------------------------------------------------------
# 8. Каскадный террасный бизнес-центр 3×1 (O, ур. 2)
# ---------------------------------------------------------------------------
def build_off_stepped_terrace_3x1():
    clear_scene()
    b = ArchBuilder("off_stepped_terrace_3x1")
    b.pave_base(5.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.44
    steps = [
        (-1.82, 1.78, 5, WALL),
        (0.00, 1.84, 7, CREAM),
        (1.82, 1.78, 9, WALL),
    ]
    for idx, (cx, sw_w, fls, wall_sw) in enumerate(steps):
        d = 1.38 - idx * 0.03
        th = fls * fh
        b.box((cx, 0.03, th * 0.5), (sw_w, d, th), wall_sw)
        b.curtain_wall_4sides(cx, 0.03, 0.03, sw_w, d, fls, fh, mullion_step=0.40,
                              frame_swatch=ALUM, spandrel_swatch=SLATE, pilaster_swatch=wall_sw)
        b.box((cx, 0.03, th + 0.04), (sw_w + 0.08, d + 0.08, 0.08), ROOF)
        if idx == 1:
            b.entrance_canopy(cx, 0.03 - d * 0.5, 0.03, w=0.72, h=0.46, canopy_d=0.24, canopy_swatch=ROOF)
        if idx < 2:
            b.solar_bank(cx, 0.03, th + 0.08, rows=2, cols=3, panel_w=0.38, panel_d=0.26)
        else:
            b.helipad(cx, 0.03, th + 0.08, size=1.08)
    return b, 3, 1


# ---------------------------------------------------------------------------
# 9. Башня-арка со стеклянным небесным мостом (Skybridge Gate) 4×1 (O, ур. 3)
# ---------------------------------------------------------------------------
def build_off_skybridge_gate_4x1():
    clear_scene()
    b = ArchBuilder("off_skybridge_gate_4x1")
    b.pave_base(7.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.43
    total_fl = 11
    th = total_fl * fh
    # Две мощные боковые башни (слева и справа) оставляют открытый городской портал по центру
    for sign in (-1, 1):
        tx = sign * 2.52
        tw, td = 2.34, 1.40
        b.chamfer_prism(tx, 0.02, 0.03, tw, td, th, 0.20, WALL)
        b.chamfer_curtain_wall(tx, 0.02, 0.03, tw, td, 0.20, total_fl, fh, mullion_step=0.40,
                               frame_swatch=ALUM, spandrel_swatch=SLATE)
        b.entrance_canopy(tx, 0.02 - td * 0.5, 0.03, w=0.68, h=0.46, canopy_d=0.22, canopy_swatch=ROOF)
        b.chamfer_prism(tx, 0.02, 0.03 + th, tw + 0.08, td + 0.08, 0.07, 0.20, ROOF)
    # Парящий 3-этажный стеклянный мост-перемычка (этажи 8..10) + смотровая крыша
    zb = 0.03 + 7 * fh
    bh = 3 * fh
    bw, bd = 2.96, 1.24
    b.box((0.0, 0.02, zb - 0.04), (bw, bd + 0.06, 0.08), ALUM)
    b.box((0.0, 0.02, zb + bh * 0.5), (bw, bd, bh), GLASS_DARK)
    b.curtain_wall_4sides(0.0, 0.02, zb, bw, bd, 3, fh, mullion_step=0.42,
                          frame_swatch=ALUM, spandrel_swatch=CHARCOAL, corner_pilasters=False)
    b.box((0.0, 0.02, zb + bh + 0.04), (bw + 0.06, bd + 0.08, 0.08), ROOF_LITE)
    b.solar_bank(0.0, 0.02, zb + bh + 0.08, rows=2, cols=4, panel_w=0.42, panel_d=0.28)
    b.helipad(-2.52, 0.02, 0.10 + th, size=1.10)
    b.rooftop_hvac(2.52, 0.04, 0.10 + th, scale=0.95)
    return b, 4, 1


# ---------------------------------------------------------------------------
# 10. IT-бульвар из трёх стеклянных корпусов с переходами 5×1 (O, ур. 2)
# ---------------------------------------------------------------------------
def build_off_tech_boulevard_5x1():
    clear_scene()
    b = ArchBuilder("off_tech_boulevard_5x1")
    b.pave_base(9.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.44
    # Одноэтажная стеклянная галерея с колоннадой вдоль всего фасада
    b.box((0.0, 0.10, fh * 0.6), (9.24, 1.22, fh * 1.2), SLATE)
    _colonnade_front(b, 0.0, -0.64, 0.03, 9.30, fh * 1.2, cols=12, col_swatch=ALUM)
    b.entrance_canopy(0.0, 0.10 - 0.61, 0.03, w=0.84, h=0.48, canopy_d=0.22, canopy_swatch=ROOF)

    # Три гранёных IT-блока (6, 8, 6 этажей) + воздушные переходы между ними
    z1 = 0.03 + fh * 1.2
    pods = [(-3.26, 2.56, 5, WALL), (0.0, 2.74, 7, CREAM), (3.26, 2.56, 5, WALL)]
    for idx, (px, pw, fls, sw) in enumerate(pods):
        ph = fls * fh
        b.chamfer_prism(px, 0.04, z1, pw, 1.38, ph, 0.22, sw)
        b.chamfer_curtain_wall(px, 0.04, z1, pw, 1.38, 0.22, fls, fh, mullion_step=0.40,
                               frame_swatch=ALUM, spandrel_swatch=SLATE)
        zt = z1 + ph
        b.chamfer_prism(px, 0.04, zt, pw + 0.06, 1.44, 0.07, 0.22, ROOF)
        if idx == 1:
            b.hip_roof(px, 0.04, zt + 0.07, 1.64, 0.96, 0.36, roof_swatch=GLASS_LITE, fascia_swatch=ALUM, overhang=0.02)
        else:
            b.solar_bank(px, 0.04, zt + 0.07, rows=2, cols=3, panel_w=0.40, panel_d=0.28)
    for sign in (-1, 1):
        bx = sign * 1.66
        b.box((bx, 0.04, z1 + fh * 2.5), (0.86, 0.86, fh * 1.4), GLASS_LITE)
        b.box((bx, 0.04, z1 + fh * 3.25), (0.90, 0.90, 0.05), ALUM)
    return b, 5, 1


# ---------------------------------------------------------------------------
# 11. Флагманский деловой комплекс (World Plaza) 7×1 (O, ур. 3)
# ---------------------------------------------------------------------------
def build_off_world_plaza_7x1():
    clear_scene()
    b = ArchBuilder("off_world_plaza_7x1")
    b.pave_base(13.74, 1.76, swatch=SANDSTONE, border_swatch=STONE)
    fh = 0.42
    # Двухэтажный парадный стилобат на все 7 клеток
    ph = fh * 2
    b.chamfer_prism(0, 0.02, 0.03, 13.38, 1.46, ph, 0.24, GUNMETAL)
    _colonnade_front(b, 0.0, -0.72, 0.03, 4.60, ph, cols=6, col_swatch=STONE)
    b.entrance_canopy(0.0, -0.71, 0.03, w=0.96, h=0.52, canopy_d=0.26, canopy_swatch=ROOF)
    for sign in (-1, 1):
        b.storefront_strip(sign * 4.4, -0.71, 0.03, 3.8, h=fh * 0.96, bays=5, awning_swatch=COPPER)

    zp = 0.03 + ph
    # Два 7-этажных симметричных крыла + два 10-этажных плеча + 15-этажная доминанта в центре!
    masses = [
        (-4.86, 3.12, 1.32, 6, CREAM),
        (4.86, 3.12, 1.32, 6, CREAM),
        (-2.18, 2.28, 1.36, 9, WALL),
        (2.18, 2.28, 1.36, 9, WALL),
        (0.00, 2.48, 1.44, 14, WALL),
    ]
    for idx, (mx, mw, md, fls, sw) in enumerate(masses):
        mh = fls * fh
        b.chamfer_prism(mx, 0.02, zp, mw, md, mh, 0.20, sw)
        b.chamfer_curtain_wall(mx, 0.02, zp, mw, md, 0.20, fls, fh, mullion_step=0.40,
                               frame_swatch=ALUM, spandrel_swatch=SLATE)
        zt = zp + mh
        b.chamfer_prism(mx, 0.02, zt, mw + 0.06, md + 0.06, 0.07, 0.20, ROOF)
        if idx in (0, 1):
            b.solar_bank(mx, 0.02, zt + 0.07, rows=2, cols=4, panel_w=0.42, panel_d=0.26)
        elif idx == 2:
            b.helipad(mx, 0.02, zt + 0.07, size=1.06)
        elif idx == 3:
            b.rooftop_hvac(mx, 0.02, zt + 0.07, scale=0.95)
        else:
            # Стеклянная корона центральной башни и двойной шпиль
            b.chamfer_prism(0, 0.02, zt + 0.07, 1.56, 1.06, fh * 2, 0.18, GLASS_LITE)
            b.chamfer_prism(0, 0.02, zt + 0.07 + fh * 2, 1.62, 1.12, 0.06, 0.18, COPPER)
            for sx in (-0.34, 0.34):
                b.cylinder((sx, 0.02, zt + 0.56 + fh * 2), 0.03, 0.008, 0.88, ALUM, segments=8)
    return b, 7, 1


# ---------------------------------------------------------------------------
# 12. Бизнес-куб со световым атриумом 2×2 (O, ур. 1)
# ---------------------------------------------------------------------------
def build_off_atrium_cube_2x2():
    clear_scene()
    b = ArchBuilder("off_atrium_cube_2x2")
    b.pave_base(3.74, 3.74, swatch=STONE, border_swatch=CONCRETE)
    fh, floors = 0.45, 6
    w, d = 3.36, 3.36
    h = floors * fh
    b.chamfer_prism(0, 0, 0.03, w, d, h, 0.42, WALL)
    b.chamfer_curtain_wall(0, 0, 0.03, w, d, 0.42, floors, fh, mullion_step=0.42,
                           frame_swatch=ALUM, spandrel_swatch=SLATE)
    # Выразительные горизонтальные солнцезащитные пояса вокруг всего куба
    for fl in range(1, floors + 1):
        b.chamfer_prism(0, 0, 0.03 + fl * fh - 0.02, w + 0.10, d + 0.10, 0.055, 0.42,
                        ROOF if fl == floors else STONE)
    b.entrance_canopy(0.0, -d * 0.5, 0.03, w=0.82, h=0.48, canopy_d=0.24, canopy_swatch=ROOF)
    # Стеклянный купол центрального атриума и инженерия на углах крыши
    zt = 0.09 + h
    b.hip_roof(0, 0, zt, 1.68, 1.68, 0.48, roof_swatch=GLASS_LITE, fascia_swatch=ALUM, overhang=0.03, ridge_frac=0.0)
    b.rooftop_hvac(-1.02, 1.02, zt, scale=0.85)
    b.rooftop_hvac(1.02, 1.02, zt, scale=0.85)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 13. Корпоративный небоскрёб «Цитадель» 2×2 (O, ур. 3)
# ---------------------------------------------------------------------------
def build_off_citadel_tower_2x2():
    clear_scene()
    b = ArchBuilder("off_citadel_tower_2x2")
    b.pave_base(3.74, 3.74, swatch=SANDSTONE, border_swatch=STONE)
    fh = 0.42
    # Двухэтажный гранитно-стеклянный подиум с колоннадой
    ph = fh * 2
    b.chamfer_prism(0, 0, 0.03, 3.48, 3.48, ph, 0.34, GUNMETAL)
    _colonnade_front(b, 0.0, -1.74, 0.03, 2.60, ph, cols=5, col_swatch=STONE)
    b.entrance_canopy(0.0, -1.72, 0.03, w=0.84, h=0.50, canopy_d=0.26, canopy_swatch=ROOF)
    b.chamfer_prism(0, 0, 0.03 + ph, 3.56, 3.56, 0.07, 0.34, STONE)

    # Крестообразный небоскрёб: центральное ядро 16 этажей + 4 крыла на 11 и 14 этажей!
    zp = 0.10 + ph
    core_h = 16 * fh
    b.chamfer_prism(0, 0, zp, 1.96, 1.96, core_h, 0.26, WALL)
    b.chamfer_curtain_wall(0, 0, zp, 1.96, 1.96, 0.26, 16, fh, mullion_step=0.38,
                           frame_swatch=ALUM, spandrel_swatch=SLATE)
    # Боковые лопасти креста
    wing_h_x = 13 * fh
    b.box((0, 0, zp + wing_h_x * 0.5), (2.86, 1.24, wing_h_x), CREAM)
    b.curtain_wall_4sides(0, 0, zp, 2.86, 1.24, 13, fh, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=CHARCOAL, pilaster_swatch=CREAM)
    b.box((0, 0, zp + wing_h_x + 0.03), (2.94, 1.30, 0.06), ROOF_LITE)

    wing_h_y = 10 * fh
    b.box((0, 0, zp + wing_h_y * 0.5), (1.24, 2.86, wing_h_y), CREAM)
    b.curtain_wall_4sides(0, 0, zp, 1.24, 2.86, 10, fh, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=CHARCOAL, pilaster_swatch=CREAM)
    b.box((0, 0, zp + wing_h_y + 0.03), (1.30, 2.94, 0.06), ROOF_LITE)

    # Корона, вертолётная площадка и шпиль
    zt = zp + core_h
    b.chamfer_prism(0, 0, zt, 2.04, 2.04, 0.08, 0.26, ROOF)
    b.helipad(0, 0, zt + 0.08, size=1.32)
    b.cylinder((0.68, 0.68, zt + 0.62), 0.032, 0.008, 1.05, ALUM, segments=8)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 14. Технологический кампус со стеклянной ротондой и мостом 3×2 (O, ур. 2)
# ---------------------------------------------------------------------------
def build_off_silicon_campus_3x2():
    clear_scene()
    b = ArchBuilder("off_silicon_campus_3x2")
    b.pave_base(5.74, 3.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.45
    # Два смещённых 6-этажных стеклянных крыла + диагональный небесный переход + круглый лекторий!
    wings = [
        (-1.38, -0.68, 2.66, 1.54, 5, WALL),
        (1.22, 0.72, 2.96, 1.58, 6, CREAM),
    ]
    for wx, wy, ww, wd, fls, sw in wings:
        wh = fls * fh
        b.chamfer_prism(wx, wy, 0.03, ww, wd, wh, 0.24, sw)
        b.chamfer_curtain_wall(wx, wy, 0.03, ww, wd, 0.24, fls, fh, mullion_step=0.42,
                               frame_swatch=ALUM, spandrel_swatch=SLATE)
        b.chamfer_prism(wx, wy, 0.03 + wh, ww + 0.08, wd + 0.08, 0.07, 0.24, ROOF)
        b.solar_bank(wx, wy, 0.10 + wh, rows=2, cols=4, panel_w=0.40, panel_d=0.32)
    b.entrance_canopy(-1.38, -0.68 - 0.77, 0.03, w=0.76, h=0.46, canopy_d=0.22, canopy_swatch=ROOF)

    # Диагональный двухэтажный стеклянный переход между корпусами на уровне 3–4 этажа
    b.box((-0.08, 0.02, 0.03 + fh * 3.0), (2.10, 0.86, fh * 1.5), GLASS_LITE, angle_z=-0.52)
    b.box((-0.08, 0.02, 0.03 + fh * 3.8), (2.16, 0.92, 0.06), ALUM, angle_z=-0.52)

    # Круглый стеклянный павильон-аудитория (как Apple Visitor / Lecture Hall) справа спереди!
    rx, ry = 1.62, -0.96
    b.cylinder((rx, ry, 0.03 + 0.36), 0.78, 0.78, 0.72, GLASS_DARK, segments=16)
    b.cylinder((rx, ry, 0.03 + 0.75), 0.92, 0.92, 0.07, ALUM, segments=16)
    b.cylinder((rx, ry, 0.03 + 0.81), 0.62, 0.62, 0.05, ROOF, segments=16)
    return b, 3, 2


# ---------------------------------------------------------------------------
# 15. Финансовый центр мегаполиса (две гранёные башни + атриум) 3×2 (O, ур. 3)
# ---------------------------------------------------------------------------
def build_off_financial_center_3x2():
    clear_scene()
    b = ArchBuilder("off_financial_center_3x2")
    b.pave_base(5.76, 3.76, swatch=SANDSTONE, border_swatch=STONE)
    fh = 0.42
    # Трёхэтажный конгресс-стилобат с арочным стеклянным сводом по центру
    ph = fh * 3
    b.chamfer_prism(0, 0.12, 0.03, 5.42, 3.24, ph, 0.32, GUNMETAL)
    _colonnade_front(b, 0.0, 0.12 - 1.62, 0.03, 4.80, ph, cols=8, col_swatch=STONE)
    b.entrance_canopy(0.0, 0.12 - 1.60, 0.03, w=0.96, h=0.52, canopy_d=0.26, canopy_swatch=COPPER)
    zp = 0.03 + ph
    b.barrel_roof(0.0, 0.12, zp, 1.56, 2.96, 0.48, roof_swatch=GLASS_LITE, end_swatch=ALUM, rib_swatch=ALUM, segments=8, ribs=5)

    # Левая 16-этажная (всего 19) и правая 11-этажная (всего 14) гранёные финансовые башни
    for tx, ty, fls, sw, crown in ((-1.76, 0.12, 16, WALL, True), (1.76, 0.12, 11, CREAM, False)):
        th = fls * fh
        b.chamfer_prism(tx, ty, zp, 1.88, 2.26, th, 0.34, sw)
        b.chamfer_curtain_wall(tx, ty, zp, 1.88, 2.26, 0.34, fls, fh, mullion_step=0.38,
                               frame_swatch=ALUM, spandrel_swatch=SLATE)
        zt = zp + th
        b.chamfer_prism(tx, ty, zt, 1.96, 2.34, 0.08, 0.34, ROOF)
        if crown:
            b.chamfer_prism(tx, ty, zt + 0.08, 1.28, 1.52, fh * 2, 0.24, GLASS_LITE)
            b.chamfer_prism(tx, ty, zt + 0.08 + fh * 2, 1.34, 1.58, 0.07, 0.24, COPPER)
            b.cylinder((tx, ty, zt + 0.65 + fh * 2), 0.036, 0.008, 1.05, COPPER, segments=8)
        else:
            b.helipad(tx, ty, zt + 0.08, size=1.22)

    # Двухэтажный панорамный скайбридж на уровне 9–10 этажей
    zb = zp + 6 * fh
    b.box((0.0, 0.12, zb + fh * 0.8), (1.76, 1.04, fh * 1.6), GLASS_DARK)
    b.box((0.0, 0.12, zb + fh * 1.65), (1.80, 1.10, 0.06), ALUM)
    return b, 3, 2


OFFICE_SPECS = [
    ("off_boutique_1x1", "Архитектурное бюро с ламелями", "OFFICE", 1, build_off_boutique_1x1),
    ("off_artdeco_spire_1x1", "Офисная башня ар-деко со шпилем", "OFFICE", 2, build_off_artdeco_spire_1x1),
    ("off_diagrid_needle_1x1", "Небоскрёб с ромбовидным каркасом", "OFFICE", 3, build_off_diagrid_needle_1x1),
    ("off_glass_pavilion_2x1", "Стеклянный павильон на колоннаде", "OFFICE", 1, build_off_glass_pavilion_2x1),
    ("off_cantilever_2x1", "Консольный бизнес-центр", "OFFICE", 2, build_off_cantilever_2x1),
    ("off_twin_slabs_2x1", "Парные офисные пластины с атриумом", "OFFICE", 3, build_off_twin_slabs_2x1),
    ("off_colonnade_hq_3x1", "Штаб-квартира с портиком и фонарём", "OFFICE", 1, build_off_colonnade_hq_3x1),
    ("off_stepped_terrace_3x1", "Каскадный террасный бизнес-центр", "OFFICE", 2, build_off_stepped_terrace_3x1),
    ("off_skybridge_gate_4x1", "Деловой комплекс «Небесные ворота»", "OFFICE", 3, build_off_skybridge_gate_4x1),
    ("off_tech_boulevard_5x1", "IT-бульвар с воздушными переходами", "OFFICE", 2, build_off_tech_boulevard_5x1),
    ("off_world_plaza_7x1", "Флагманский деловой центр World Plaza", "OFFICE", 3, build_off_world_plaza_7x1),
    ("off_atrium_cube_2x2", "Бизнес-куб со стеклянным куполом", "OFFICE", 1, build_off_atrium_cube_2x2),
    ("off_citadel_tower_2x2", "Корпоративный небоскрёб «Цитадель»", "OFFICE", 3, build_off_citadel_tower_2x2),
    ("off_silicon_campus_3x2", "Технологический кампус с ротондой", "OFFICE", 2, build_off_silicon_campus_3x2),
    ("off_financial_center_3x2", "Финансовый центр мегаполиса", "OFFICE", 3, build_off_financial_center_3x2),
]
