"""Процедурные генераторы 20 коммерческих зданий (магазины, пекарни, кофейни, дайнеры, рынки,
кинотеатры, пассажи, универмаги и моллы) для зон COMMERCIAL и COMMERCIAL_HIGH (уровни 1..3,
участки 1×1, 2×1, 3×1, 4×1, 5×1, 7×1, 2×2 и 3×2).

Все модели используют единый меш и один материал палитры Kenney (colormap.png) с плавными АО-градиентами,
построены в игровом масштабе (CELL = 2.0 м, model_scale = 1.0, фасад на −Y → model_turns = 2 в Godot)
и полностью совместимы с перекраской стен и акцентов крыш/маркиз в BuildingPalette.
"""

import math

from arch_kit import (
    ALUM,
    BRICK,
    CHARCOAL,
    CLAY,
    CONCRETE,
    COPPER,
    CREAM,
    GLASS_DARK,
    GLASS_LITE,
    GUNMETAL,
    IRON,
    ROOF,
    ROOF_DEEP,
    ROOF_LITE,
    ROOF_WARM,
    SANDSTONE,
    SLATE,
    STEEL,
    STONE,
    TERRACOTTA,
    WALL,
    ArchBuilder,
    clear_scene,
)


# ---------------------------------------------------------------------------
# Фирменные детали коммерческой архитектуры (маркизы, зонтики кафе, вывески)
# ---------------------------------------------------------------------------

def _striped_awning(
    b: ArchBuilder,
    cx: float,
    y_wall: float,
    z_top: float,
    width: float,
    depth: float = 0.25,
    sw_a=ROOF_DEEP,
    sw_b=WALL,
    stripes: int = 5,
):
    """Полосатая наклонная маркиза витрины с передним фестоном-карнизом."""
    n = max(3, stripes)
    seg_w = width / n
    slope_len = math.hypot(depth, 0.11)
    for i in range(n):
        sx = cx - width * 0.5 + (i + 0.5) * seg_w
        sw = sw_a if i % 2 == 0 else sw_b
        b.tilted_box(
            (sx, y_wall - depth * 0.5, z_top - 0.05),
            (seg_w + 0.006, slope_len, 0.032),
            sw,
            pitch_x=0.38,
        )
        # Передний вертикальный волан маркизы
        b.box((sx, y_wall - depth + 0.015, z_top - 0.115), (seg_w + 0.004, 0.028, 0.048), sw)
    # Боковые стальные кронштейны
    for sign in (-1, 1):
        bx = cx + sign * (width * 0.5 - 0.02)
        b.box((bx, y_wall - depth * 0.45, z_top - 0.08), (0.024, depth * 0.85, 0.024), IRON)


def _cafe_table(
    b: ArchBuilder,
    x: float,
    y: float,
    z0: float,
    umbrella_sw=ROOF_WARM,
    alt_sw=WALL,
    has_umbrella: bool = True,
):
    """Уличный столик кафе с двумя стульями, чашечкой и полосатым зонтиком-парасолем."""
    # Опора и круглая столешница
    b.cylinder((x, y, z0 + 0.09), 0.028, 0.024, 0.18, IRON, segments=6)
    b.cylinder((x, y, z0 + 0.185), 0.17, 0.17, 0.028, CREAM, segments=10)
    # Чашечка кофе на столе
    b.cylinder((x + 0.04, y - 0.03, z0 + 0.215), 0.026, 0.032, 0.035, WALL, segments=6)
    # Два стульчика слева и справа от столика
    for sx in (-1, 1):
        ch_x = x + sx * 0.23
        b.box((ch_x, y, z0 + 0.06), (0.035, 0.035, 0.12), IRON)
        b.box((ch_x, y, z0 + 0.125), (0.11, 0.11, 0.026), SANDSTONE)
        b.box((ch_x + sx * 0.045, y, z0 + 0.19), (0.024, 0.11, 0.12), SANDSTONE)

    if has_umbrella:
        b.cylinder((x, y, z0 + 0.36), 0.020, 0.018, 0.36, STEEL, segments=6)
        # Восьмиклинный купол зонтика с чередованием цветных и белых клиньев
        segs = 8
        r_umb = 0.23
        z_rim = z0 + 0.49
        apex = (x, y, z0 + 0.61)
        for i in range(segs):
            a0 = 2.0 * math.pi * i / segs
            a1 = 2.0 * math.pi * (i + 1) / segs
            p0 = (x + r_umb * math.cos(a0), y + r_umb * math.sin(a0), z_rim)
            p1 = (x + r_umb * math.cos(a1), y + r_umb * math.sin(a1), z_rim)
            am = 0.5 * (a0 + a1)
            sw = umbrella_sw if i % 2 == 0 else alt_sw
            b.add_poly([p0, p1, apex], sw, (math.cos(am), math.sin(am), 0.65))


def _coffee_cup_sign(b: ArchBuilder, cx: float, cy: float, z0: float, scale: float = 1.0):
    """Объёмная 3D-вывеска кофейни на крыше: блюдце, чашка эспрессо с ручкой и клубы пара."""
    s = scale
    # Металлическая подставка и белое блюдце
    b.box((cx, cy, z0 + 0.04 * s), (0.28 * s, 0.18 * s, 0.08 * s), STEEL)
    b.cylinder((cx, cy, z0 + 0.095 * s), 0.24 * s, 0.28 * s, 0.04 * s, WALL, segments=12)
    # Чашка с тёплым кофейным пояском и тёмным эспрессо внутри
    b.cylinder((cx, cy, z0 + 0.25 * s), 0.16 * s, 0.22 * s, 0.28 * s, WALL, segments=12)
    b.cylinder((cx, cy, z0 + 0.24 * s), 0.185 * s, 0.205 * s, 0.12 * s, ROOF_WARM, segments=12)
    b.cylinder((cx, cy, z0 + 0.395 * s), 0.19 * s, 0.19 * s, 0.02 * s, BRICK, segments=12)
    # Ручка чашки сбоку (+X)
    b.box((cx + 0.23 * s, cy, z0 + 0.32 * s), (0.10 * s, 0.045 * s, 0.04 * s), WALL)
    b.box((cx + 0.23 * s, cy, z0 + 0.19 * s), (0.10 * s, 0.045 * s, 0.04 * s), WALL)
    b.box((cx + 0.27 * s, cy, z0 + 0.255 * s), (0.04 * s, 0.045 * s, 0.16 * s), WALL)
    # Три завитка ароматного пара над чашкой
    for dx, dz, tilt in ((-0.05, 0.48, 0.22), (0.04, 0.56, -0.20), (-0.02, 0.64, 0.15)):
        b.tilted_box((cx + dx * s, cy, z0 + dz * s), (0.045 * s, 0.035 * s, 0.11 * s), CREAM, roll_y=tilt)


def _bakery_croissant_sign(b: ArchBuilder, cx: float, cy: float, z0: float, scale: float = 1.0):
    """Объёмная 3D-эмблема пекарни: золотистый круассан/крендель на кованом щите."""
    s = scale
    b.box((cx, cy, z0 + 0.18 * s), (0.48 * s, 0.07 * s, 0.32 * s), IRON)
    b.box((cx, cy, z0 + 0.18 * s), (0.42 * s, 0.09 * s, 0.26 * s), ROOF_DEEP)
    # Дуга круассана из 5 золотистых сегментов
    segs = [
        (-0.13, 0.14, -0.55, 0.10, 0.08),
        (-0.07, 0.21, -0.25, 0.12, 0.095),
        (0.0, 0.23, 0.0, 0.14, 0.11),
        (0.07, 0.21, 0.25, 0.12, 0.095),
        (0.13, 0.14, 0.55, 0.10, 0.08),
    ]
    for dx, dz, roll, w, h in segs:
        b.tilted_box(
            (cx + dx * s, cy - 0.035 * s, z0 + dz * s),
            (w * s, 0.06 * s, h * s),
            SANDSTONE,
            roll_y=roll,
        )


def _blade_sign(b: ArchBuilder, x: float, y_wall: float, z0: float, h: float = 0.78, w: float = 0.20, sw=ROOF_WARM):
    """Вертикальная консольная вывеска на фасаде магазина/ресторана/кинотеатра."""
    # Кронштейны к стене
    for dz in (0.18, h - 0.18):
        b.box((x, y_wall - 0.07, z0 + dz), (0.04, 0.14, 0.04), IRON)
    # Корпус и светящееся поле вывески
    b.box((x, y_wall - 0.18, z0 + h * 0.5), (0.065, w, h), SLATE)
    b.box((x, y_wall - 0.18, z0 + h * 0.5), (0.082, w - 0.04, h - 0.06), sw)
    for k in range(3):
        zk = z0 + h * (0.26 + 0.24 * k)
        b.box((x, y_wall - 0.19, zk), (0.092, w - 0.06, 0.05), WALL, grad=False)


def _produce_stall(b: ArchBuilder, cx: float, y_front: float, z0: float, width: float = 0.72):
    """Уличный фермерский прилавок с лотками овощей/фруктов под козырьком."""
    b.box((cx, y_front, z0 + 0.14), (width, 0.28, 0.28), SANDSTONE)
    colors = (ROOF_DEEP, ROOF_LITE, ROOF, ROOF_WARM)
    bins = 4
    bw = (width - 0.08) / bins
    for i in range(bins):
        bx = cx - (width - 0.08) * 0.5 + (i + 0.5) * bw
        b.tilted_box((bx, y_front - 0.01, z0 + 0.30), (bw * 0.86, 0.26, 0.08), colors[i % 4], pitch_x=0.28)


def _planter_box(b: ArchBuilder, cx: float, cy: float, z0: float, w: float = 0.48, d: float = 0.22):
    """Каменное кашпо с зелёным кустарником у витрины."""
    b.box((cx, cy, z0 + 0.08), (w, d, 0.16), STONE)
    b.chamfer_prism(cx, cy, z0 + 0.15, w - 0.06, d - 0.05, 0.14, 0.04, ROOF)


def _clock_turret(b: ArchBuilder, cx: float, cy: float, z0: float, radius: float = 0.32, h: float = 0.62, dome_sw=ROOF_DEEP):
    """Восьмигранная башенка с часами и куполом со шпилем (для бутиков и универмагов)."""
    w = radius * 2.0
    b.chamfer_prism(cx, cy, z0, w, w, h, w * 0.28, CREAM)
    b.chamfer_prism(cx, cy, z0 + h, w + 0.06, w + 0.06, 0.06, w * 0.28, STONE)
    # Циферблаты часов на 4 сторонах
    cz = z0 + h * 0.62
    for ox, oy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        fx, fy = cx + ox * (radius + 0.015), cy + oy * (radius + 0.015)
        b.facade_box((fx, fy, cz), (0.20, 0.03, 0.20) if abs(oy) > 0 else (0.03, 0.20, 0.20), IRON, (ox, oy))
        b.facade_box((fx + ox * 0.01, fy + oy * 0.01, cz), (0.15, 0.025, 0.15) if abs(oy) > 0 else (0.025, 0.15, 0.15), WALL, (ox, oy))
    # Гранёный купол и шпиль
    b.cylinder((cx, cy, z0 + h + 0.18), radius * 0.98, radius * 0.42, 0.24, dome_sw, segments=8)
    b.cylinder((cx, cy, z0 + h + 0.34), radius * 0.42, 0.04, 0.12, dome_sw, segments=8)
    b.cylinder((cx, cy, z0 + h + 0.50), 0.025, 0.012, 0.24, COPPER, segments=6)


# ===========================================================================
# КАТЕГОРИЯ A: МАГАЗИНЫ, КАФЕШКИ, ПЕКАРНИ, РЫНКИ (COMMERCIAL — 11 моделей)
# ===========================================================================

def build_com_corner_bakery_1x1():
    """1. Угловая булочная-пекарня «Бриошь» (1×1, COMMERCIAL, ур. 1)."""
    clear_scene()
    b = ArchBuilder("com_corner_bakery_1x1")
    b.pave_base(1.74, 1.74)
    # Тёплый кирпично-кремовый 2-этажный дом со скошенным углом
    w, d, h1, h2 = 1.46, 1.38, 0.72, 0.62
    cy = 0.08
    b.chamfer_prism(0.0, cy, 0.03, w, d, h1, 0.24, BRICK)
    b.chamfer_prism(0.0, cy, 0.03 + h1, w + 0.04, d + 0.04, 0.05, 0.24, STONE)
    b.chamfer_prism(0.0, cy, 0.08 + h1, w, d, h2, 0.24, CREAM)
    # Большие витрины пекарни и полосатая маркиза спереди (−Y)
    yw = cy - d * 0.5
    b.storefront_strip(0.0, yw, 0.03, w - 0.36, h=0.58, bays=2, awning_swatch=ROOF_DEEP)
    _striped_awning(b, 0.0, yw, 0.68, w - 0.34, depth=0.24, sw_a=ROOF_DEEP, sw_b=WALL, stripes=5)
    # Окна второго этажа со ставнями
    b.chamfer_windows_4sides(0.0, cy, 0.08 + h1, w, d, 0.24, 1, h2, win_w=0.22, win_h=0.26, step=0.44, start_floor=0)
    # Вальмовая черепичная крыша, печная труба и 3D-круассан над входом
    z_roof = 0.08 + h1 + h2
    b.hip_roof(0.0, cy, z_roof, w - 0.04, d - 0.04, 0.42, roof_swatch=ROOF, fascia_swatch=STONE, overhang=0.08)
    b.chimney_home(0.42, cy + 0.28, z_roof + 0.10, h=0.48, swatch=BRICK)
    _bakery_croissant_sign(b, 0.0, yw - 0.04, 0.72, scale=0.85)
    # Уличный столик со стульями и зонтиком у тротуара
    _cafe_table(b, -0.46, -0.60, 0.03, umbrella_sw=ROOF_WARM, alt_sw=WALL)
    _planter_box(b, 0.48, -0.64, 0.03, w=0.42, d=0.20)
    return b, 1, 1


def build_com_street_cafe_1x1():
    """2. Уличная кофейня с верандой «Эспрессо» (1×1, COMMERCIAL, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_street_cafe_1x1")
    b.pave_base(1.74, 1.74)
    # Деревянный террасный подиум спереди (−Y)
    b.box((0.0, -0.48, 0.055), (1.58, 0.62, 0.05), SANDSTONE)
    # Основной 2-этажный павильон кофейни со скошенным стеклянным углом
    w, d, h = 1.48, 0.98, 1.28
    cy = 0.26
    b.chamfer_prism(0.0, cy, 0.03, w, d, h, 0.22, WALL)
    b.chamfer_curtain_wall(0.0, cy, 0.03, w, d, 0.22, 2, h * 0.5, mullion_step=0.36, frame_swatch=SLATE, spandrel_swatch=SANDSTONE)
    # Парапет, полосатая маркиза и большая 3D-чашка кофе с паром на крыше!
    z_top = 0.03 + h
    b.chamfer_prism(0.0, cy, z_top, w + 0.06, d + 0.06, 0.09, 0.22, ROOF_DEEP)
    _striped_awning(b, 0.0, cy - d * 0.5, 0.66, w - 0.32, depth=0.26, sw_a=ROOF, sw_b=CREAM, stripes=5)
    _coffee_cup_sign(b, -0.34, cy - 0.06, z_top + 0.09, scale=0.95)
    b.rooftop_hvac(0.38, cy + 0.14, z_top + 0.09, scale=0.68)
    # Два столика с зонтиками на деревянной террасе и зелёные кашпо
    _cafe_table(b, -0.42, -0.48, 0.08, umbrella_sw=ROOF_DEEP, alt_sw=CREAM)
    _cafe_table(b, 0.42, -0.48, 0.08, umbrella_sw=ROOF, alt_sw=CREAM)
    for sx in (-0.68, 0.68):
        _planter_box(b, sx, -0.74, 0.03, w=0.24, d=0.18)
    return b, 1, 1


def build_com_boutique_giftshop_1x1():
    """3. Двухэтажный магазин-бутик с мансардой и часовой башенкой (1×1, COMMERCIAL, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_boutique_giftshop_1x1")
    b.pave_base(1.74, 1.74)
    w, d, h = 1.48, 1.32, 1.52
    cy = 0.08
    b.box((0.0, cy, 0.03 + 0.32), (w, d, 0.64), SLATE)
    b.box((0.0, cy, 0.67 + 0.44), (w - 0.02, d - 0.02, 0.88), CREAM)
    yw = cy - d * 0.5
    b.storefront_strip(0.0, yw, 0.03, w - 0.16, h=0.58, bays=3, awning_swatch=ROOF_WARM)
    _striped_awning(b, 0.0, yw, 0.64, w - 0.20, depth=0.22, sw_a=ROOF_WARM, sw_b=WALL, stripes=5)
    b.box_windows_4sides(0.0, cy, 0.67, w - 0.02, d - 0.02, 2, 0.44, win_w=0.22, win_h=0.25, step=0.42, start_floor=0, front_balconies="all")
    # Французская мансарда со слуховыми окошками и угловой башенкой с часами
    b.mansard_roof(0.0, cy, 1.55, w - 0.02, d - 0.02, 0.36, cap_h=0.10, inset=0.20, steep_swatch=ROOF, cap_swatch=SLATE)
    b.dormer(-0.34, yw + 0.08, 1.59, dir_xy=(0, -1), w=0.26, d=0.24, h=0.25, wall_swatch=CREAM, roof_swatch=ROOF_LITE)
    _clock_turret(b, 0.44, yw + 0.22, 1.52, radius=0.24, h=0.46, dome_sw=ROOF_DEEP)
    _blade_sign(b, -0.68, yw, 0.72, h=0.68, w=0.18, sw=ROOF_LITE)
    return b, 1, 1


def build_com_retro_diner_2x1():
    """4. Классическое придорожное кафе-дайнер с неоновым пилоном и летними зонтиками (2×1, COMMERCIAL, ур. 1)."""
    clear_scene()
    b = ArchBuilder("com_retro_diner_2x1")
    b.pave_base(3.74, 1.74)
    # Хромированный вагончик дайнера со скруглёнными углами слева и террасой справа
    dx, dy, dw, dd, dh = -0.42, 0.14, 2.48, 1.16, 0.92
    b.chamfer_prism(dx, dy, 0.03, dw, dd, 0.18, 0.26, ROOF_DEEP)
    b.chamfer_prism(dx, dy, 0.21, dw, dd, 0.56, 0.26, ALUM)
    b.chamfer_prism(dx, dy, 0.77, dw + 0.04, dd + 0.04, 0.18, 0.26, ROOF_WARM)
    # Горизонтальные молдинги из нержавейки и ленточные окна кабинок
    b.chamfer_curtain_wall(dx, dy, 0.22, dw, dd, 0.26, 1, 0.52, mullion_step=0.42, frame_swatch=STEEL, spandrel_swatch=ROOF_DEEP)
    # Полукруглый свод крыши дайнера и вытяжки кухни
    b.barrel_roof(dx, dy, 0.95, dw - 0.28, dd - 0.18, 0.22, roof_swatch=ALUM, end_swatch=ROOF_LITE, rib_swatch=STEEL, segments=8, ribs=4)
    b.entrance_canopy(dx, dy - dd * 0.5, 0.03, w=0.56, h=0.64, canopy_d=0.26, canopy_swatch=ROOF_LITE)
    b.rooftop_hvac(dx + 0.65, dy + 0.15, 1.12, scale=0.75)
    # Высокий ретро-пилон вывески «DINER» со стрелкой и звездой у правого края
    px, py = 1.32, -0.42
    b.box((px, py, 0.08), (0.36, 0.36, 0.10), STONE)
    b.cylinder((px - 0.08, py, 0.92), 0.05, 0.04, 1.72, STEEL, segments=8)
    b.cylinder((px + 0.08, py, 0.92), 0.05, 0.04, 1.72, STEEL, segments=8)
    b.tilted_box((px, py, 1.38), (0.68, 0.14, 0.42), ROOF_DEEP, roll_y=0.14)
    b.tilted_box((px, py, 1.38), (0.58, 0.16, 0.32), CREAM, roll_y=0.14)
    b.box((px, py, 1.74), (0.52, 0.15, 0.16), ROOF_LITE)
    # Три столика под зонтиками на летней площадке справа
    for tx, ty, sw in ((1.08, 0.32, ROOF_DEEP), (1.52, 0.32, ROOF_LITE), (0.25, -0.60, ROOF_WARM)):
        _cafe_table(b, tx, ty, 0.03, umbrella_sw=sw, alt_sw=WALL)
    return b, 2, 1


def build_com_bistro_terrace_2x1():
    """5. Угловой ресторанчик-бистро с деревянной перголой и летней верандой (2×1, COMMERCIAL, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_bistro_terrace_2x1")
    b.pave_base(3.74, 1.74)
    # Двухэтажный корпус итальянской траттории слева
    bx, by, bw, bd, bh = -0.68, 0.08, 2.08, 1.38, 1.48
    b.box((bx, by, 0.03 + bh * 0.5), (bw, bd, bh), CREAM)
    b.box((bx, by, 0.03 + 0.08), (bw + 0.04, bd + 0.04, 0.16), BRICK)
    yw = by - bd * 0.5
    b.storefront_strip(bx, yw, 0.03, bw - 0.18, h=0.62, bays=3, awning_swatch=ROOF_DEEP)
    _striped_awning(b, bx, yw, 0.68, bw - 0.22, depth=0.26, sw_a=ROOF_DEEP, sw_b=CREAM, stripes=6)
    b.box_windows_4sides(bx, by, 0.03, bw, bd, 2, bh * 0.5, win_w=0.24, win_h=0.26, step=0.46, start_floor=1, front_balconies="all")
    b.hip_roof(bx, by, 0.03 + bh, bw, bd, 0.44, roof_swatch=TERRACOTTA, fascia_swatch=STONE, overhang=0.09)
    # Высокая кирпичная труба дровяной печи для пиццы
    b.chimney_home(bx + 0.68, by + 0.38, 0.03 + bh + 0.08, h=0.58, swatch=BRICK)
    _blade_sign(b, bx - bw * 0.5 + 0.12, yw, 0.72, h=0.68, w=0.20, sw=ROOF)

    # Пристроенная деревянная пергола летней веранды справа (+X) с 3 столиками и кашпо
    tx, ty, tw, td = 1.02, 0.04, 1.32, 1.38
    b.box((tx, ty, 0.055), (tw, td, 0.05), SANDSTONE)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((tx + sx * (tw * 0.45), ty + sy * (td * 0.44), 0.48), (0.065, 0.065, 0.86), BRICK)
    for sx in (-1, 1):
        b.box((tx + sx * (tw * 0.45), ty, 0.92), (0.07, td + 0.08, 0.06), BRICK)
    for r in range(6):
        ry = ty - td * 0.44 + r * (td * 0.88 / 5)
        b.box((tx, ry, 0.96), (tw + 0.10, 0.045, 0.045), SANDSTONE)
    _cafe_table(b, tx - 0.30, ty - 0.32, 0.08, umbrella_sw=ROOF_WARM, alt_sw=CREAM, has_umbrella=False)
    _cafe_table(b, tx + 0.30, ty - 0.32, 0.08, umbrella_sw=ROOF_WARM, alt_sw=CREAM, has_umbrella=False)
    _cafe_table(b, tx, ty + 0.30, 0.08, umbrella_sw=ROOF_DEEP, alt_sw=WALL, has_umbrella=True)
    _planter_box(b, tx + 0.32, -0.72, 0.03, w=0.52, d=0.20)
    return b, 2, 1


def build_com_neighborhood_market_2x1():
    """6. Фермерский гастроном и кулинария с уличными лотками и солнечными батареями (2×1, COMMERCIAL, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_neighborhood_market_2x1")
    b.pave_base(3.74, 1.74)
    w, d, h = 3.44, 1.24, 1.42
    cy = 0.06
    b.box((0.0, cy, 0.03 + h * 0.5), (w, d, h), WALL)
    # Отделка деревянными ламелями и высокий стеклянный входной портал по центру
    b.box((0.0, cy, 0.03 + h - 0.16), (w + 0.04, d + 0.04, 0.24), SANDSTONE)
    b.box((0.0, cy, 0.03 + h + 0.04), (w + 0.08, d + 0.08, 0.08), SLATE)
    yw = cy - d * 0.5
    b.storefront_strip(-0.98, yw, 0.03, 1.24, h=0.68, bays=2, awning_swatch=ROOF)
    b.storefront_strip(0.98, yw, 0.03, 1.24, h=0.68, bays=2, awning_swatch=ROOF)
    # Высокий центральный стеклянный тамбур с двускатным козырьком
    b.box((0.0, yw - 0.08, 0.03 + 0.82), (0.86, 0.24, 1.64), SLATE)
    b.curtain_wall_4sides(0.0, yw - 0.08, 0.03, 0.84, 0.22, 2, 0.78, mullion_step=0.28, frame_swatch=ALUM, spandrel_swatch=ROOF, corner_pilasters=False)
    b.gable_roof(0.0, yw - 0.08, 1.67, 0.92, 0.32, 0.26, roof_swatch=ROOF, gable_swatch=CREAM, axis="y")
    # Уличные прилавки со свежими овощами/фруктами и столик кофейни
    _produce_stall(b, -1.02, yw - 0.18, 0.03, width=0.88)
    _produce_stall(b, 1.02, yw - 0.18, 0.03, width=0.88)
    # Солнечные панели и чиллер на крыше, грузовая рампа сзади (+Y)
    b.solar_bank(-0.85, cy + 0.05, 0.03 + h + 0.08, rows=2, cols=3, panel_w=0.36, panel_d=0.24)
    b.rooftop_hvac(1.05, cy + 0.12, 0.03 + h + 0.08, scale=0.85)
    b.loading_dock(0.95, cy + d * 0.5, 0.03, out_xy=(0, 1), w=0.56, h=0.48, canopy_swatch=TERRACOTTA)
    return b, 2, 1


def build_com_strip_shops_3x1():
    """7. Торговый ряд «Три лавки» — книжная, кафе-мороженое и аптека (3×1, COMMERCIAL, ур. 1)."""
    clear_scene()
    b = ArchBuilder("com_strip_shops_3x1")
    b.pave_base(5.74, 1.74)
    # Три сблокированных магазинчика разной высоты и стиля вдоль улицы
    specs = [
        (-1.82, 1.76, 1.30, 1.36, BRICK, ROOF_DEEP, WALL, "gable"),
        (0.0, 1.88, 1.34, 1.54, CREAM, ROOF_WARM, CREAM, "flat"),
        (1.82, 1.76, 1.30, 1.42, WALL, ROOF, WALL, "hip"),
    ]
    for sx, sw_w, sd, sh, wall_sw, acc_sw, alt_sw, rkind in specs:
        cy = 0.10
        b.box((sx, cy, 0.03 + sh * 0.5), (sw_w, sd, sh), wall_sw)
        yw = cy - sd * 0.5
        b.storefront_strip(sx, yw, 0.03, sw_w - 0.14, h=0.60, bays=3, awning_swatch=acc_sw)
        _striped_awning(b, sx, yw, 0.66, sw_w - 0.18, depth=0.24, sw_a=acc_sw, sw_b=alt_sw, stripes=5)
        b.box_windows_4sides(sx, cy, 0.03, sw_w, sd, 2, sh * 0.5, win_w=0.22, win_h=0.24, step=0.44, start_floor=1)
        zt = 0.03 + sh
        if rkind == "gable":
            b.gable_roof(sx, cy, zt, sw_w, sd, 0.36, roof_swatch=acc_sw, gable_swatch=wall_sw, axis="y")
        elif rkind == "hip":
            b.hip_roof(sx, cy, zt, sw_w, sd, 0.36, roof_swatch=acc_sw, fascia_swatch=STONE)
        else:
            b.box((sx, cy, zt + 0.06), (sw_w + 0.06, sd + 0.06, 0.12), acc_sw)
            _coffee_cup_sign(b, sx, cy - 0.18, zt + 0.12, scale=0.85)
    # Уличные столики перед центральным кафе-мороженым
    _cafe_table(b, -0.48, -0.60, 0.03, umbrella_sw=ROOF_WARM, alt_sw=WALL)
    _cafe_table(b, 0.48, -0.60, 0.03, umbrella_sw=ROOF_LITE, alt_sw=WALL)
    return b, 3, 1


def build_com_artisan_row_4x1():
    """8. Староместский променад с кофейнями, пекарней и торговыми лавками (4×1, COMMERCIAL, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_artisan_row_4x1")
    b.pave_base(7.74, 1.76)
    houses = [
        (-2.74, 1.82, 1.32, 1.68, CREAM, ROOF_DEEP, "mansard"),
        (-0.92, 1.82, 1.30, 1.52, BRICK, ROOF_WARM, "gable_y"),
        (0.92, 1.82, 1.30, 1.62, WALL, ROOF, "hip"),
        (2.74, 1.82, 1.32, 1.74, SANDSTONE, ROOF_LITE, "mansard"),
    ]
    for hx, hw, hd, hh, wall_sw, roof_sw, rstyle in houses:
        cy = 0.10
        b.box((hx, cy, 0.03 + hh * 0.5), (hw, hd, hh), wall_sw)
        yw = cy - hd * 0.5
        b.storefront_strip(hx, yw, 0.03, hw - 0.14, h=0.62, bays=3, awning_swatch=roof_sw)
        _striped_awning(b, hx, yw, 0.66, hw - 0.20, depth=0.24, sw_a=roof_sw, sw_b=WALL, stripes=5)
        b.box_windows_4sides(hx, cy, 0.03, hw, hd, 3, hh / 3.0, win_w=0.22, win_h=0.22, step=0.42, start_floor=1, front_balconies="checker")
        zt = 0.03 + hh
        if rstyle == "mansard":
            b.mansard_roof(hx, cy, zt, hw, hd, 0.34, cap_h=0.08, inset=0.18, steep_swatch=roof_sw, cap_swatch=SLATE)
        elif rstyle == "gable_y":
            b.gable_roof(hx, cy, zt, hw, hd, 0.42, roof_swatch=roof_sw, gable_swatch=wall_sw, axis="y")
        else:
            b.hip_roof(hx, cy, zt, hw, hd, 0.38, roof_swatch=roof_sw, fascia_swatch=STONE)
    # Уличные столики кафе и кашпо вдоль променада
    for tx, sw in ((-2.2, ROOF_DEEP), (-0.4, ROOF_WARM), (1.3, ROOF), (3.1, ROOF_LITE)):
        _cafe_table(b, tx, -0.60, 0.03, umbrella_sw=sw, alt_sw=CREAM)
    _blade_sign(b, -3.55, -0.56, 0.75, h=0.72, w=0.20, sw=ROOF_DEEP)
    _blade_sign(b, 3.55, -0.56, 0.75, h=0.72, w=0.20, sw=ROOF_WARM)
    return b, 4, 1


def build_com_market_promenade_5x1():
    """9. Гастрономический бульвар и торговые ряды с центральным павильоном-кафе (5×1, COMMERCIAL, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_market_promenade_5x1")
    b.pave_base(9.74, 1.76)
    cy = 0.10
    # Центральный остеклённый павильон-оранжерея ресторана со сводчатой крышей и чашкой кофе
    b.chamfer_prism(0.0, cy, 0.03, 2.36, 1.38, 1.66, 0.28, WALL)
    b.chamfer_curtain_wall(0.0, cy, 0.03, 2.36, 1.38, 0.28, 2, 0.80, mullion_step=0.38, frame_swatch=SLATE, spandrel_swatch=ROOF)
    b.barrel_roof(0.0, cy, 1.69, 2.10, 1.28, 0.38, roof_swatch=ROOF, end_swatch=CREAM, rib_swatch=STEEL, segments=10, ribs=4)
    _coffee_cup_sign(b, 0.0, cy - 0.22, 2.08, scale=1.0)
    # Боковые двухэтажные торговые крылья с аркадами витрин
    for sign, roof_sw, wall_sw in ((-1, ROOF_DEEP, CREAM), (1, ROOF_WARM, SANDSTONE)):
        wx = sign * 2.95
        ww, wd, wh = 3.24, 1.30, 1.44
        b.box((wx, cy, 0.03 + wh * 0.5), (ww, wd, wh), wall_sw)
        yw = cy - wd * 0.5
        b.storefront_strip(wx, yw, 0.03, ww - 0.20, h=0.62, bays=5, awning_swatch=roof_sw)
        _striped_awning(b, wx, yw, 0.66, ww - 0.24, depth=0.24, sw_a=roof_sw, sw_b=WALL, stripes=8)
        b.box_windows_4sides(wx, cy, 0.03, ww, wd, 2, wh * 0.5, win_w=0.24, win_h=0.24, step=0.44, start_floor=1, front_balconies="alt_floors")
        b.hip_roof(wx, cy, 0.03 + wh, ww, wd, 0.40, roof_swatch=roof_sw, fascia_swatch=STONE)
    # Терраса со столиками и фермерскими прилавками вдоль всей улицы
    for tx, sw in ((-3.6, ROOF_DEEP), (-1.8, ROOF_WARM), (-0.5, ROOF), (0.5, ROOF_LITE), (1.8, ROOF_WARM), (3.6, ROOF_DEEP)):
        _cafe_table(b, tx, -0.60, 0.03, umbrella_sw=sw, alt_sw=WALL)
    return b, 5, 1


def build_com_farmers_bazaar_2x2():
    """10. Крытый городской рынок и фудкорт со сводчатым залом и двориком кафе (2×2, COMMERCIAL, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_farmers_bazaar_2x2")
    b.pave_base(3.74, 3.74)
    # Главный сводчатый павильон рынка в глубине и слева
    hx, hy, hw, hd, hh = -0.42, 0.34, 2.48, 2.68, 1.48
    b.box((hx, hy, 0.03 + hh * 0.5), (hw, hd, hh), BRICK)
    b.box((hx, hy, 0.03 + 0.10), (hw + 0.06, hd + 0.06, 0.20), STONE)
    b.barrel_roof(hx, hy, 0.03 + hh, hw - 0.12, hd, 0.52, roof_swatch=ROOF, end_swatch=CREAM, rib_swatch=STEEL, segments=10, ribs=5)
    # Парадный вход рынка на улице (−Y) с большими витражами и маркизой
    yw = hy - hd * 0.5
    b.storefront_strip(hx, yw, 0.03, hw - 0.24, h=0.72, bays=3, awning_swatch=ROOF_DEEP)
    _striped_awning(b, hx, yw, 0.76, hw - 0.28, depth=0.28, sw_a=ROOF_DEEP, sw_b=CREAM, stripes=6)
    b.box_windows_4sides(hx, hy, 0.03, hw, hd, 2, hh * 0.5, win_w=0.26, win_h=0.28, step=0.48, start_floor=1)
    # Угловая часовая башенка рынка
    _clock_turret(b, hx + hw * 0.5 - 0.18, yw + 0.18, 0.03 + hh, radius=0.28, h=0.56, dome_sw=ROOF_DEEP)
    # Боковая крытая торговая галерея справа (+X) и открытый дворик фудкорта спереди-справа
    gx, gy, gw, gd, gh = 1.24, 0.58, 0.88, 2.18, 0.96
    b.box((gx, gy, 0.03 + gh * 0.5), (gw, gd, gh), CREAM)
    b.hip_roof(gx, gy, 0.03 + gh, gw, gd, 0.28, roof_swatch=TERRACOTTA, fascia_swatch=STONE)
    _produce_stall(b, gx - 0.12, -0.82, 0.03, width=0.84)
    _produce_stall(b, gx - 0.12, -1.32, 0.03, width=0.84)
    for tx, ty, sw in ((-0.95, -1.42, ROOF_WARM), (0.05, -1.42, ROOF), (1.15, -1.42, ROOF_DEEP)):
        _cafe_table(b, tx, ty, 0.03, umbrella_sw=sw, alt_sw=WALL)
    return b, 2, 2


def build_com_supermarket_plaza_3x2():
    """11. Супермаркет с кафетерием, угловой башней-вывеской и солнечной крышей (3×2, COMMERCIAL, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_supermarket_plaza_3x2")
    b.pave_base(5.74, 3.74)
    # Просторный торговый зал супермаркета
    mx, my, mw, md, mh = -0.18, 0.28, 4.96, 2.66, 1.56
    b.box((mx, my, 0.03 + mh * 0.5), (mw, md, mh), WALL)
    b.box((mx, my, 0.03 + mh - 0.22), (mw + 0.06, md + 0.06, 0.28), ROOF)
    b.box((mx, my, 0.03 + mh + 0.05), (mw + 0.12, md + 0.12, 0.10), SLATE)
    # Выступающий стеклянный атриум кассовой зоны и кафетерия спереди (−Y)
    ay = my - md * 0.5 - 0.18
    b.chamfer_prism(-0.55, ay, 0.03, 3.36, 0.52, 1.24, 0.18, SLATE)
    b.chamfer_curtain_wall(-0.55, ay, 0.03, 3.36, 0.52, 0.18, 2, 0.60, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=ROOF_LITE)
    _striped_awning(b, -0.55, ay - 0.26, 0.72, 2.86, depth=0.28, sw_a=ROOF, sw_b=WALL, stripes=7)
    # Высокая угловая башня-пилон супермаркета справа спереди
    tx, ty = 2.18, my - md * 0.5 + 0.12
    b.chamfer_prism(tx, ty, 0.03, 0.92, 0.92, 2.52, 0.20, ROOF_DEEP)
    b.chamfer_curtain_wall(tx, ty, 0.45, 0.94, 0.94, 0.20, 3, 0.56, mullion_step=0.32, frame_swatch=ALUM, spandrel_swatch=ROOF_WARM)
    _coffee_cup_sign(b, tx, ty, 2.55, scale=0.95)
    # Летняя веранда кафетерия у входа и фермерские лотки
    for cx_t, sw in ((-1.85, ROOF_WARM), (-0.95, ROOF), (0.05, ROOF_DEEP), (1.05, ROOF_LITE)):
        _cafe_table(b, cx_t, -1.52, 0.03, umbrella_sw=sw, alt_sw=WALL)
    # Крышная солнечная электростанция, HVAC и два грузовых дока сзади (+Y)
    z_roof = 0.03 + mh + 0.10
    b.solar_bank(-0.95, my + 0.15, z_roof, rows=3, cols=5, panel_w=0.40, panel_d=0.28)
    b.rooftop_hvac(1.35, my - 0.25, z_roof, scale=0.95)
    b.rooftop_hvac(1.35, my + 0.55, z_roof, scale=0.95)
    b.loading_dock(-1.15, my + md * 0.5, 0.03, out_xy=(0, 1), w=0.62, h=0.52, canopy_swatch=TERRACOTTA)
    b.loading_dock(0.25, my + md * 0.5, 0.03, out_xy=(0, 1), w=0.62, h=0.52, canopy_swatch=TERRACOTTA)
    return b, 3, 2


# ===========================================================================
# КАТЕГОРИЯ B: ТОРГОВЫЕ ДОМА, ПАССАЖИ, КИНОТЕАТРЫ И МОЛЛЫ (COMMERCIAL_HIGH — 9 моделей)
# ===========================================================================

def build_com_rooftop_lounge_1x1():
    """12. 4-этажный ресторан-клуб с террасой и зонтиками на крыше (1×1, COMMERCIAL_HIGH, ур. 1)."""
    clear_scene()
    b = ArchBuilder("com_rooftop_lounge_1x1")
    b.pave_base(1.74, 1.74)
    w, d, h = 1.50, 1.36, 2.08
    b.chamfer_prism(0.0, 0.08, 0.03, w, d, h, 0.24, CREAM)
    yw = 0.08 - d * 0.5
    b.storefront_strip(0.0, yw, 0.03, w - 0.34, h=0.60, bays=2, awning_swatch=ROOF_WARM)
    _striped_awning(b, 0.0, yw, 0.66, w - 0.36, depth=0.22, sw_a=ROOF_WARM, sw_b=WALL, stripes=5)
    b.chamfer_curtain_wall(0.0, 0.08, 0.65, w, d, 0.24, 3, 0.46, mullion_step=0.36, frame_swatch=SLATE, spandrel_swatch=TERRACOTTA)
    # Эксплуатируемая кровля-ресторан с парапетом, барным павильоном и 2 столиками под зонтиками
    zt = 0.03 + h
    b.chamfer_prism(0.0, 0.08, zt, w + 0.06, d + 0.06, 0.10, 0.24, STONE)
    b.box((0.0, 0.44, zt + 0.28), (1.06, 0.44, 0.38), ROOF_DEEP)
    b.box((0.0, 0.40, zt + 0.49), (1.16, 0.54, 0.05), CREAM)
    _cafe_table(b, -0.34, -0.16, zt + 0.10, umbrella_sw=ROOF_WARM, alt_sw=WALL)
    _cafe_table(b, 0.34, -0.16, zt + 0.10, umbrella_sw=ROOF_LITE, alt_sw=WALL)
    _blade_sign(b, -0.66, yw, 0.82, h=1.05, w=0.18, sw=ROOF_DEEP)
    return b, 1, 1


def build_com_flagship_store_1x1():
    """13. 6-этажный флагманский Дом моды со стеклянным углом и купольной короной (1×1, COMMERCIAL_HIGH, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_flagship_store_1x1")
    b.pave_base(1.74, 1.74)
    w, d, h = 1.50, 1.38, 3.12
    cy = 0.06
    b.chamfer_prism(0.0, cy, 0.03, w, d, h, 0.28, WALL)
    b.chamfer_curtain_wall(0.0, cy, 0.03, w, d, 0.28, 6, h / 6.0, mullion_step=0.36, frame_swatch=ALUM, spandrel_swatch=SLATE)
    yw = cy - d * 0.5
    _striped_awning(b, 0.0, yw, 0.66, w - 0.42, depth=0.22, sw_a=ROOF_DEEP, sw_b=CREAM, stripes=5)
    # Ступенчатая корона с купольной ротондой и двумя световыми пилонами
    zt = 0.03 + h
    b.chamfer_prism(0.0, cy, zt, w + 0.06, d + 0.06, 0.10, 0.28, STONE)
    b.chamfer_prism(0.0, cy, zt + 0.10, 1.12, 1.12, 0.44, 0.24, ROOF_DEEP)
    b.chamfer_curtain_wall(0.0, cy, zt + 0.10, 1.12, 1.12, 0.24, 1, 0.42, mullion_step=0.30, frame_swatch=ALUM, spandrel_swatch=ROOF_LITE)
    _clock_turret(b, 0.0, cy, zt + 0.54, radius=0.36, h=0.52, dome_sw=ROOF_WARM)
    _blade_sign(b, -0.68, yw, 0.90, h=1.45, w=0.18, sw=ROOF_WARM)
    _blade_sign(b, 0.68, yw, 0.90, h=1.45, w=0.18, sw=ROOF_LITE)
    return b, 1, 1


def build_com_cinema_palace_2x1():
    """14. Городской кинотеатр и кафе «Синема» с радиусным козырьком ар-деко (2×1, COMMERCIAL_HIGH, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_cinema_palace_2x1")
    b.pave_base(3.74, 1.76)
    w, d, h = 3.44, 1.28, 2.28
    cy = 0.14
    b.chamfer_prism(0.0, cy, 0.03, w, d, h, 0.28, CREAM)
    # Ступенчатый аттик ар-деко и вертикальные пилястры на фасаде
    b.chamfer_prism(0.0, cy, 0.03 + h, 2.48, d - 0.16, 0.36, 0.22, ROOF_DEEP)
    b.chamfer_prism(0.0, cy, 0.03 + h + 0.36, 1.48, d - 0.32, 0.28, 0.18, ROOF_WARM)
    yw = cy - d * 0.5
    for px in (-1.35, -0.75, 0.75, 1.35):
        b.box((px, yw - 0.02, 0.03 + h * 0.5), (0.14, 0.08, h), STONE)
        # Цветные афишные лайтбоксы между пилястрами
    for bx, sw in ((-1.05, ROOF_WARM), (1.05, ROOF_LITE)):
        b.box((bx, yw - 0.02, 1.18), (0.42, 0.05, 1.12), SLATE)
        b.box((bx, yw - 0.035, 1.18), (0.34, 0.03, 0.98), sw)
    # Выступающий световой козырёк-маркиза кинотеатра (marquee) и вертикальная башня-вывеска
    b.chamfer_prism(0.0, yw - 0.16, 0.68, 1.36, 0.36, 0.26, 0.12, ROOF_DEEP)
    b.chamfer_prism(0.0, yw - 0.16, 0.72, 1.40, 0.40, 0.16, 0.12, WALL)
    b.box((0.0, yw - 0.10, 0.03 + 1.65), (0.32, 0.24, 2.45), ROOF_DEEP)
    b.box((0.0, yw - 0.12, 0.03 + 1.75), (0.20, 0.26, 2.15), ROOF_LITE)
    # Боковые кафешки со столиками у входа в кинотеатр
    _cafe_table(b, -1.15, -0.58, 0.03, umbrella_sw=ROOF_DEEP, alt_sw=WALL)
    _cafe_table(b, 1.15, -0.58, 0.03, umbrella_sw=ROOF_WARM, alt_sw=WALL)
    b.rooftop_hvac(-1.10, cy + 0.15, 0.03 + h, scale=0.80)
    b.rooftop_hvac(1.10, cy + 0.15, 0.03 + h, scale=0.80)
    return b, 2, 1


def build_com_grand_emporium_3x1():
    """15. 4-этажный Центральный Универмаг с мансардой и куполом (3×1, COMMERCIAL_HIGH, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_grand_emporium_3x1")
    b.pave_base(5.74, 1.76)
    w, d, h = 5.44, 1.32, 2.28
    cy = 0.10
    # Каменный цокольный ярус с высокими витринами и 3 верхних этажа
    b.box((0.0, cy, 0.03 + 0.36), (w, d, 0.72), STONE)
    b.box((0.0, cy, 0.75 + (h - 0.72) * 0.5), (w - 0.04, d - 0.04, h - 0.72), CREAM)
    yw = cy - d * 0.5
    b.storefront_strip(-1.72, yw, 0.03, 1.68, h=0.64, bays=3, awning_swatch=ROOF_DEEP)
    b.storefront_strip(1.72, yw, 0.03, 1.68, h=0.64, bays=3, awning_swatch=ROOF_DEEP)
    _striped_awning(b, -1.72, yw, 0.68, 1.62, depth=0.24, sw_a=ROOF_DEEP, sw_b=WALL, stripes=5)
    _striped_awning(b, 1.72, yw, 0.68, 1.62, depth=0.24, sw_a=ROOF_DEEP, sw_b=WALL, stripes=5)
    # Центральный ризалит с витражным порталом на всю высоту
    b.box((0.0, cy - 0.04, 0.03 + (h + 0.22) * 0.5), (1.36, d + 0.10, h + 0.22), WALL)
    b.curtain_wall_4sides(0.0, cy - 0.04, 0.03, 1.36, d + 0.10, 4, (h + 0.20) / 4.0, mullion_step=0.34, frame_swatch=SLATE, spandrel_swatch=ROOF_DEEP)
    b.box_windows_4sides(0.0, cy, 0.75, w - 0.04, d - 0.04, 3, (h - 0.72) / 3.0, win_w=0.24, win_h=0.26, step=0.46, start_floor=0, front_balconies="alt_floors")
    # Французская мансарда, центральный гранёный купол со шпилем и угловые башенки
    zt = 0.03 + h
    b.mansard_roof(0.0, cy, zt, w - 0.04, d - 0.04, 0.42, cap_h=0.10, inset=0.22, steep_swatch=SLATE, cap_swatch=ROOF_DEEP)
    _clock_turret(b, 0.0, cy - 0.04, zt + 0.22, radius=0.48, h=0.68, dome_sw=ROOF)
    for sx in (-2.28, 2.28):
        _clock_turret(b, sx, yw + 0.22, zt, radius=0.26, h=0.48, dome_sw=ROOF_DEEP)
        _cafe_table(b, sx * 0.52, -0.60, 0.03, umbrella_sw=ROOF_WARM, alt_sw=CREAM)
    return b, 3, 1


def build_com_glass_arcade_4x1():
    """16. Торговый пассаж со стеклянным сводом и уличными кафе (4×1, COMMERCIAL_HIGH, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_glass_arcade_4x1")
    b.pave_base(7.74, 1.76)
    cy = 0.10
    # Два 4-этажных боковых крыла и широкий стеклянный пассаж со сводом между ними
    for sign in (-1, 1):
        wx = sign * 2.48
        ww, wd, wh = 2.38, 1.32, 2.42
        b.chamfer_prism(wx, cy, 0.03, ww, wd, wh, 0.22, WALL)
        yw = cy - wd * 0.5
        b.storefront_strip(wx, yw, 0.03, ww - 0.34, h=0.64, bays=3, awning_swatch=ROOF)
        _striped_awning(b, wx, yw, 0.68, ww - 0.38, depth=0.24, sw_a=ROOF, sw_b=WALL, stripes=6)
        b.chamfer_curtain_wall(wx, cy, 0.70, ww, wd, 0.22, 3, (wh - 0.67) / 3.0, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=SLATE)
        b.mansard_roof(wx, cy, 0.03 + wh, ww - 0.12, wd - 0.12, 0.38, cap_h=0.08, inset=0.18, steep_swatch=ROOF_DEEP, cap_swatch=SLATE)
    # Центральный стеклянный атриум-пассаж с высоким полукруглым сводом
    aw, ad, ah = 2.68, 1.36, 2.18
    b.box((0.0, cy, 0.03 + ah * 0.5), (aw, ad, ah), SLATE)
    b.curtain_wall_4sides(0.0, cy, 0.03, aw, ad, 4, ah / 4.0, mullion_step=0.36, frame_swatch=ALUM, spandrel_swatch=ROOF_LITE, corner_pilasters=True, pilaster_swatch=STONE)
    b.barrel_roof(0.0, cy, 0.03 + ah, aw - 0.12, ad + 0.02, 0.64, roof_swatch=GLASS_LITE, end_swatch=GLASS_DARK, rib_swatch=STEEL, segments=12, ribs=5)
    # Козырёк входа пассажа и столики уличных кофеен
    b.entrance_canopy(0.0, cy - ad * 0.5, 0.03, w=0.92, h=0.72, canopy_d=0.26, canopy_swatch=ROOF_WARM)
    for tx, sw in ((-2.8, ROOF_DEEP), (-1.6, ROOF_WARM), (1.6, ROOF), (2.8, ROOF_LITE)):
        _cafe_table(b, tx, -0.60, 0.03, umbrella_sw=sw, alt_sw=WALL)
    return b, 4, 1


def build_com_boulevard_galleria_5x1():
    """17. Проспектная торговая галерея с ресторанами и зонтиками на террасах крыш (5×1, COMMERCIAL_HIGH, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_boulevard_galleria_5x1")
    b.pave_base(9.74, 1.76)
    cy = 0.10
    # Длинный 2-этажный торговый стилобат во всю ширину участка
    pw, pd, ph = 9.42, 1.32, 1.38
    b.chamfer_prism(0.0, cy, 0.03, pw, pd, ph, 0.24, CREAM)
    yw = cy - pd * 0.5
    for sx, sw in ((-3.2, ROOF_DEEP), (0.0, ROOF_WARM), (3.2, ROOF)):
        b.storefront_strip(sx, yw, 0.03, 2.64, h=0.64, bays=4, awning_swatch=sw)
        _striped_awning(b, sx, yw, 0.68, 2.58, depth=0.24, sw_a=sw, sw_b=WALL, stripes=7)
    b.chamfer_curtain_wall(0.0, cy, 0.70, pw, pd, 0.24, 1, 0.64, mullion_step=0.40, frame_swatch=ALUM, spandrel_swatch=SLATE)
    zt = 0.03 + ph
    b.chamfer_prism(0.0, cy, zt, pw + 0.06, pd + 0.06, 0.08, 0.24, STONE)

    # Две 5-этажные башни галереи по краям и центральный купольный павильон, между ними — террасы ресторанов!
    for sign, t_sw in ((-1, ROOF_DEEP), (1, ROOF)):
        tx = sign * 3.25
        tw, td, th = 2.38, 1.24, 1.88
        b.chamfer_prism(tx, cy, zt + 0.08, tw, td, th, 0.22, WALL)
        b.chamfer_curtain_wall(tx, cy, zt + 0.08, tw, td, 0.22, 3, th / 3.0, mullion_step=0.36, frame_swatch=ALUM, spandrel_swatch=t_sw)
        b.chamfer_prism(tx, cy, zt + 0.08 + th, tw + 0.06, td + 0.06, 0.10, 0.22, t_sw)
        b.solar_bank(tx, cy, zt + 0.18 + th, rows=2, cols=3, panel_w=0.36, panel_d=0.24)
        _blade_sign(b, tx + sign * (tw * 0.5 - 0.12), yw, 0.95, h=1.65, w=0.20, sw=t_sw)

    # Центральный стеклянный ротонда-ресторан на крыше стилобата и открытые террасы со столиками
    b.cylinder((0.0, cy, zt + 0.58), 0.72, 0.72, 0.96, GLASS_DARK, segments=12)
    b.cylinder((0.0, cy, zt + 1.12), 0.78, 0.30, 0.28, ROOF_WARM, segments=12)
    _coffee_cup_sign(b, 0.0, cy, zt + 1.38, scale=0.95)
    for rx, sw in ((-1.45, ROOF_WARM), (-0.98, ROOF_LITE), (0.98, ROOF_DEEP), (1.45, ROOF)):
        _cafe_table(b, rx, cy - 0.08, zt + 0.08, umbrella_sw=sw, alt_sw=WALL)
    for gx, sw in ((-2.1, ROOF_DEEP), (-0.9, ROOF_WARM), (0.9, ROOF), (2.1, ROOF_LITE)):
        _cafe_table(b, gx, -0.60, 0.03, umbrella_sw=sw, alt_sw=CREAM)
    return b, 5, 1


def build_com_grand_avenue_mall_7x1():
    """18. Гранд-пассаж и проспектный торговый комплекс с тремя куполами и верандами (7×1, COMMERCIAL_HIGH, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_grand_avenue_mall_7x1")
    b.pave_base(13.74, 1.76)
    cy = 0.10
    pw, pd, ph = 13.42, 1.32, 1.52
    b.chamfer_prism(0.0, cy, 0.03, pw, pd, ph, 0.26, CREAM)
    yw = cy - pd * 0.5
    for sx, sw in ((-4.8, ROOF_DEEP), (-1.6, ROOF_WARM), (1.6, ROOF), (4.8, ROOF_LITE)):
        b.storefront_strip(sx, yw, 0.03, 2.86, h=0.66, bays=4, awning_swatch=sw)
        _striped_awning(b, sx, yw, 0.70, 2.80, depth=0.24, sw_a=sw, sw_b=WALL, stripes=7)
    b.chamfer_curtain_wall(0.0, cy, 0.72, pw, pd, 0.26, 2, 0.39, mullion_step=0.40, frame_swatch=ALUM, spandrel_swatch=SLATE)
    zt = 0.03 + ph
    b.chamfer_prism(0.0, cy, zt, pw + 0.06, pd + 0.06, 0.08, 0.26, STONE)

    # Центральный 6-этажный атриум со сводом + две боковые 5-этажные башни с часовыми куполами
    b.chamfer_prism(0.0, cy, zt + 0.08, 3.28, 1.28, 2.18, 0.24, WALL)
    b.chamfer_curtain_wall(0.0, cy, zt + 0.08, 3.28, 1.28, 0.24, 4, 2.18 / 4.0, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=ROOF_WARM)
    b.barrel_roof(0.0, cy, zt + 2.26, 2.96, 1.22, 0.58, roof_swatch=GLASS_LITE, end_swatch=ROOF_DEEP, rib_swatch=STEEL, segments=12, ribs=5)

    for sign, r_sw in ((-1, ROOF_DEEP), (1, ROOF)):
        tx = sign * 4.78
        tw, td, th = 2.68, 1.24, 1.82
        b.chamfer_prism(tx, cy, zt + 0.08, tw, td, th, 0.22, WALL)
        b.chamfer_curtain_wall(tx, cy, zt + 0.08, tw, td, 0.22, 3, th / 3.0, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=r_sw)
        b.mansard_roof(tx, cy, zt + 0.08 + th, tw - 0.08, td - 0.08, 0.38, cap_h=0.08, inset=0.18, steep_swatch=r_sw, cap_swatch=SLATE)
        _clock_turret(b, tx, cy - 0.08, zt + 0.46 + th, radius=0.34, h=0.58, dome_sw=r_sw)
        # Террасы кафе на стилобате между центральным корпусом и боковыми башнями
        for dx, u_sw in ((-0.55, ROOF_WARM), (0.55, ROOF_LITE)):
            _cafe_table(b, sign * 2.55 + dx, cy - 0.08, zt + 0.08, umbrella_sw=u_sw, alt_sw=WALL)
    for gx, u_sw in ((-5.4, ROOF_DEEP), (-3.1, ROOF_WARM), (-1.1, ROOF), (1.1, ROOF_LITE), (3.1, ROOF_WARM), (5.4, ROOF_DEEP)):
        _cafe_table(b, gx, -0.60, 0.03, umbrella_sw=u_sw, alt_sw=CREAM)
    return b, 7, 1


def build_com_atrium_department_2x2():
    """19. Многоуровневый Торговый Дом «Атриум» с пирамидальным фонарём и кафе на террасе (2×2, COMMERCIAL_HIGH, ур. 2)."""
    clear_scene()
    b = ArchBuilder("com_atrium_department_2x2")
    b.pave_base(3.74, 3.74)
    # 3-этажный главный подиум универмага во весь участок
    w, d, h1 = 3.42, 3.28, 1.88
    cy = 0.12
    b.chamfer_prism(0.0, cy, 0.03, w, d, h1, 0.42, CREAM)
    yw = cy - d * 0.5
    b.storefront_strip(-0.88, yw, 0.03, 1.32, h=0.66, bays=2, awning_swatch=ROOF_DEEP)
    b.storefront_strip(0.88, yw, 0.03, 1.32, h=0.66, bays=2, awning_swatch=ROOF_DEEP)
    _striped_awning(b, -0.88, yw, 0.70, 1.28, depth=0.24, sw_a=ROOF_DEEP, sw_b=WALL, stripes=5)
    _striped_awning(b, 0.88, yw, 0.70, 1.28, depth=0.24, sw_a=ROOF_DEEP, sw_b=WALL, stripes=5)
    b.entrance_canopy(0.0, yw, 0.03, w=0.78, h=0.72, canopy_d=0.28, canopy_swatch=ROOF_WARM)
    b.chamfer_curtain_wall(0.0, cy, 0.72, w, d, 0.42, 2, (h1 - 0.69) * 0.5, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=SLATE)

    # Второй ярус со сдвигом вглубь (оставляет спереди открытую террасу-ресторан!) и стеклянная пирамида атриума
    z1 = 0.03 + h1
    b.chamfer_prism(0.0, cy, z1, w + 0.06, d + 0.06, 0.09, 0.42, STONE)
    w2, d2, h2 = 2.68, 2.28, 1.18
    cy2 = cy + 0.36
    b.chamfer_prism(0.0, cy2, z1 + 0.09, w2, d2, h2, 0.32, WALL)
    b.chamfer_curtain_wall(0.0, cy2, z1 + 0.09, w2, d2, 0.32, 2, h2 * 0.5, mullion_step=0.36, frame_swatch=ALUM, spandrel_swatch=ROOF_DEEP)
    z2 = z1 + 0.09 + h2
    b.chamfer_prism(0.0, cy2, z2, w2 + 0.06, d2 + 0.06, 0.08, 0.32, ROOF_WARM)
    # Стеклянный пирамидальный зенитный фонарь атриума
    b.hip_roof(0.0, cy2, z2 + 0.08, 1.62, 1.48, 0.56, roof_swatch=GLASS_LITE, fascia_swatch=STEEL, overhang=0.02, ridge_frac=0.0)
    # Столики кафе на террасе 4-го этажа и у главного входа
    for tx, sw in ((-0.82, ROOF_WARM), (0.0, ROOF), (0.82, ROOF_LITE)):
        _cafe_table(b, tx, cy - 1.12, z1 + 0.09, umbrella_sw=sw, alt_sw=WALL)
    for tx, sw in ((-1.18, ROOF_DEEP), (1.18, ROOF_WARM)):
        _cafe_table(b, tx, -1.58, 0.03, umbrella_sw=sw, alt_sw=CREAM)
    _blade_sign(b, -1.52, yw + 0.16, 0.90, h=1.35, w=0.22, sw=ROOF_DEEP)
    _blade_sign(b, 1.52, yw + 0.16, 0.90, h=1.35, w=0.22, sw=ROOF_WARM)
    return b, 2, 2


def build_com_metropolis_mall_3x2():
    """20. Флагманский торгово-развлекательный молл «Метрополис» (3×2, COMMERCIAL_HIGH, ур. 3)."""
    clear_scene()
    b = ArchBuilder("com_metropolis_mall_3x2")
    b.pave_base(5.74, 3.74)
    cy = 0.22
    # Главный 3-этажный корпус молла со скошенными углами
    mw, md, mh = 5.42, 3.04, 1.96
    b.chamfer_prism(0.0, cy, 0.03, mw, md, mh, 0.44, WALL)
    yw = cy - md * 0.5
    b.storefront_strip(-1.68, yw, 0.03, 1.72, h=0.68, bays=3, awning_swatch=ROOF_DEEP)
    b.storefront_strip(1.68, yw, 0.03, 1.72, h=0.68, bays=3, awning_swatch=ROOF)
    _striped_awning(b, -1.68, yw, 0.72, 1.66, depth=0.24, sw_a=ROOF_DEEP, sw_b=WALL, stripes=6)
    _striped_awning(b, 1.68, yw, 0.72, 1.66, depth=0.24, sw_a=ROOF, sw_b=WALL, stripes=6)
    b.chamfer_curtain_wall(0.0, cy, 0.72, mw, md, 0.44, 2, (mh - 0.69) * 0.5, mullion_step=0.40, frame_swatch=ALUM, spandrel_swatch=SLATE)
    zt = 0.03 + mh
    b.chamfer_prism(0.0, cy, zt, mw + 0.08, md + 0.08, 0.10, 0.44, STONE)

    # Центральная полукруглая стеклянная ротонда главного входа со сводчатым зенитным фонарём галереи
    b.cylinder((0.0, yw + 0.34, 0.03 + 1.38), 0.80, 0.80, 2.76, GLASS_DARK, segments=14)
    for ring_z in (0.72, 1.42, 2.12, 2.78):
        b.cylinder((0.0, yw + 0.34, ring_z), 0.83, 0.83, 0.07, ROOF_WARM, segments=14)
    b.barrel_roof(0.0, cy + 0.22, zt + 0.10, 2.18, 2.28, 0.62, roof_swatch=GLASS_LITE, end_swatch=ROOF_DEEP, rib_swatch=STEEL, segments=12, ribs=6)

    # Высокая 6-этажная угловая башня кинокомплекса/ресторана слева и солнечная станция справа
    tx, ty, tw, td, th = -1.78, cy + 0.28, 1.68, 1.78, 1.84
    b.chamfer_prism(tx, ty, zt + 0.10, tw, td, th, 0.26, CREAM)
    b.chamfer_curtain_wall(tx, ty, zt + 0.10, tw, td, 0.26, 3, th / 3.0, mullion_step=0.36, frame_swatch=ALUM, spandrel_swatch=ROOF_DEEP)
    b.chamfer_prism(tx, ty, zt + 0.10 + th, tw + 0.06, td + 0.06, 0.10, 0.26, ROOF_DEEP)
    _coffee_cup_sign(b, tx, ty - 0.25, zt + 0.20 + th, scale=1.05)

    # Открытый фудкорт со столиками на террасе 4-го этажа справа и перед входом на улице
    b.solar_bank(1.78, cy + 0.48, zt + 0.10, rows=3, cols=3, panel_w=0.38, panel_d=0.26)
    b.rooftop_hvac(1.78, cy + 1.15, zt + 0.10, scale=0.95)
    for rx, sw in ((1.32, ROOF_WARM), (2.12, ROOF), (1.72, ROOF_LITE)):
        _cafe_table(b, rx, cy - 0.86, zt + 0.10, umbrella_sw=sw, alt_sw=WALL)
    for gx, sw in ((-2.15, ROOF_DEEP), (-1.25, ROOF_WARM), (1.25, ROOF), (2.15, ROOF_LITE)):
        _cafe_table(b, gx, -1.58, 0.03, umbrella_sw=sw, alt_sw=CREAM)
    _blade_sign(b, -2.52, yw + 0.18, 0.92, h=1.62, w=0.22, sw=ROOF_DEEP)
    _blade_sign(b, 2.52, yw + 0.18, 0.92, h=1.62, w=0.22, sw=ROOF_WARM)
    b.loading_dock(-1.65, cy + md * 0.5, 0.03, out_xy=(0, 1), w=0.62, h=0.52, canopy_swatch=TERRACOTTA)
    b.loading_dock(1.65, cy + md * 0.5, 0.03, out_xy=(0, 1), w=0.62, h=0.52, canopy_swatch=TERRACOTTA)
    return b, 3, 2


COMMERCIAL_SPECS = [
    # (id, display_name, suggested_zone, suggested_level, fn)
    # --- COMMERCIAL (Магазины, кафешки, булочные, рынки — 11 шт.) ---
    ("com_corner_bakery_1x1", "Угловая пекарня «Бриошь»", "COMMERCIAL", 1, build_com_corner_bakery_1x1),
    ("com_street_cafe_1x1", "Уличная кофейня с верандой", "COMMERCIAL", 2, build_com_street_cafe_1x1),
    ("com_boutique_giftshop_1x1", "Бутик с мансардой и часами", "COMMERCIAL", 3, build_com_boutique_giftshop_1x1),
    ("com_retro_diner_2x1", "Ретро-дайнер с неоновой вывеской", "COMMERCIAL", 1, build_com_retro_diner_2x1),
    ("com_bistro_terrace_2x1", "Траттория-бистро с перголой", "COMMERCIAL", 2, build_com_bistro_terrace_2x1),
    ("com_neighborhood_market_2x1", "Фермерский гастроном и кулинария", "COMMERCIAL", 3, build_com_neighborhood_market_2x1),
    ("com_strip_shops_3x1", "Торговый ряд с кафе-мороженым", "COMMERCIAL", 1, build_com_strip_shops_3x1),
    ("com_artisan_row_4x1", "Староместский променад с кафе", "COMMERCIAL", 2, build_com_artisan_row_4x1),
    ("com_market_promenade_5x1", "Гастрономический бульвар", "COMMERCIAL", 2, build_com_market_promenade_5x1),
    ("com_farmers_bazaar_2x2", "Крытый городской рынок и фудкорт", "COMMERCIAL", 2, build_com_farmers_bazaar_2x2),
    ("com_supermarket_plaza_3x2", "Супермаркет с кафетерием", "COMMERCIAL", 3, build_com_supermarket_plaza_3x2),

    # --- COMMERCIAL_HIGH (Торговые дома, кинотеатры, пассажи, моллы — 9 шт.) ---
    ("com_rooftop_lounge_1x1", "Ресторан с лаунж-террасой на крыше", "COMMERCIAL_HIGH", 1, build_com_rooftop_lounge_1x1),
    ("com_flagship_store_1x1", "Флагманский Дом моды", "COMMERCIAL_HIGH", 3, build_com_flagship_store_1x1),
    ("com_cinema_palace_2x1", "Кинотеатр и кафе «Синема»", "COMMERCIAL_HIGH", 2, build_com_cinema_palace_2x1),
    ("com_grand_emporium_3x1", "Центральный универмаг с куполом", "COMMERCIAL_HIGH", 2, build_com_grand_emporium_3x1),
    ("com_glass_arcade_4x1", "Торговый пассаж со стеклянным сводом", "COMMERCIAL_HIGH", 3, build_com_glass_arcade_4x1),
    ("com_boulevard_galleria_5x1", "Проспектная торговая галерея", "COMMERCIAL_HIGH", 3, build_com_boulevard_galleria_5x1),
    ("com_grand_avenue_mall_7x1", "Гранд-пассаж с куполами и верандами", "COMMERCIAL_HIGH", 3, build_com_grand_avenue_mall_7x1),
    ("com_atrium_department_2x2", "Торговый Дом «Атриум»", "COMMERCIAL_HIGH", 2, build_com_atrium_department_2x2),
    ("com_metropolis_mall_3x2", "Торгово-развлекательный молл «Метрополис»", "COMMERCIAL_HIGH", 3, build_com_metropolis_mall_3x2),
]
