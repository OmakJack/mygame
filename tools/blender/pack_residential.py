"""Пак жилых зданий (18 моделей от 1×1 до 7×1 и 3×2) для CityBuilder."""

from arch_kit import (
    ALUM,
    ArchBuilder,
    BRICK,
    CELL,
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
    SANDSTONE,
    SLATE,
    STEEL,
    STONE,
    TERRACOTTA,
    WALL,
    clear_scene,
)


def _stepped_gable(b: ArchBuilder, cx, y_wall, z0, width, steps, step_h, wall_swatch, cap_swatch=STONE, out_y=-1):
    """Ступенчатый голландский фронтон вдоль лицевой или дворовой стены."""
    for s in range(steps):
        frac = 1.0 - s / steps
        sw = width * frac
        zs = z0 + s * step_h
        b.box((cx, y_wall - out_y * 0.04, zs + step_h * 0.5), (sw, 0.14, step_h), wall_swatch)
        b.box((cx, y_wall - out_y * 0.035, zs + step_h + 0.018), (sw + 0.05, 0.17, 0.036), cap_swatch)


def _pergola(b: ArchBuilder, cx, cy, z0, w, d, h=0.34, swatch=SANDSTONE):
    """Деревянная/металлическая пергола на террасе или во дворе."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((cx + sx * (w * 0.5 - 0.04), cy + sy * (d * 0.5 - 0.04), z0 + h * 0.5), (0.05, 0.05, h), swatch)
    for sy in (-1, 1):
        b.box((cx, cy + sy * (d * 0.5 - 0.04), z0 + h + 0.02), (w + 0.06, 0.05, 0.045), swatch)
    slats = max(3, int(w / 0.18))
    for i in range(slats):
        px = cx - w * 0.46 + (w * 0.92) * (i / max(1, slats - 1))
        b.box((px, cy, z0 + h + 0.055), (0.035, d + 0.08, 0.035), swatch)


def _arch_passage_wing(b: ArchBuilder, cx, cy, width, depth, floors, fh, wall_sw=WALL, base_sw=GUNMETAL,
                       arch_w=1.18, arch_floors=2):
    """Прямоугольный корпус с центральной проездной аркой на высоту arch_floors."""
    total_h = floors * fh
    side_w = (width - arch_w) * 0.5
    arch_h = arch_floors * fh
    for sign in (-1, 1):
        sx = cx + sign * (arch_w * 0.5 + side_w * 0.5)
        b.box((sx, cy, fh * 0.5), (side_w, depth, fh), base_sw)
        if arch_floors > 1:
            b.box((sx, cy, fh + (arch_h - fh) * 0.5), (side_w, depth, arch_h - fh), wall_sw)
    # Обрамление арки порталом из светлого камня
    for sign in (-1, 1):
        px = cx + sign * (arch_w * 0.5 + 0.05)
        b.box((px, cy - depth * 0.5 - 0.02, arch_h * 0.5), (0.12, 0.08, arch_h), STONE)
    b.box((cx, cy - depth * 0.5 - 0.025, arch_h + 0.04), (arch_w + 0.30, 0.10, 0.09), STONE)
    # Верхние этажи над аркой
    if floors > arch_floors:
        b.box((cx, cy, arch_h + (total_h - arch_h) * 0.5), (width, depth, total_h - arch_h), wall_sw)


# ---------------------------------------------------------------------------
# 1. Скандинавский коттедж 1×1 (R, ур. 1)
# ---------------------------------------------------------------------------
def build_nordic_cottage_1x1():
    clear_scene()
    b = ArchBuilder("res_nordic_cottage_1x1")
    b.pave_base(1.66, 1.66, swatch=STONE, border_swatch=CONCRETE)
    w, d, h = 1.30, 1.12, 0.72
    cy = 0.10
    b.box((0.0, cy, 0.11), (w + 0.04, d + 0.04, 0.22), STONE)
    b.box((0.0, cy, 0.22 + (h - 0.22) * 0.5), (w, d, h - 0.22), WALL)
    # Двускатная крыша и конёк
    b.gable_roof(0.0, cy, h, w, d, 0.52, roof_swatch=ROOF, gable_swatch=CREAM, trim_swatch=SANDSTONE, overhang=0.11, axis="x")
    # Уютное резное крыльцо на лицевом фасаде (−Y)
    py = cy - d * 0.5
    b.box((-0.22, py - 0.16, 0.07), (0.52, 0.32, 0.14), STONE)
    for sx in (-1, 1):
        b.box((-0.22 + sx * 0.20, py - 0.27, 0.34), (0.05, 0.05, 0.42), SANDSTONE)
    b.gable_roof(-0.22, py - 0.15, 0.55, 0.54, 0.34, 0.18, roof_swatch=ROOF_LITE, gable_swatch=CREAM, trim_swatch=SANDSTONE, overhang=0.04, axis="y")
    b.box((-0.22, py - 0.015, 0.34), (0.24, 0.03, 0.42), BRICK)
    b.box((-0.22, py - 0.025, 0.40), (0.14, 0.02, 0.16), GLASS_LITE)
    # Окна со ставнями + мансардные окошки во фронтонах
    b.window_unit(0.32, py, 0.46, (0, -1), 0.32, 0.28, shutters=True)
    b.window_unit(-0.30, cy + d * 0.5, 0.46, (0, 1), 0.28, 0.26, shutters=True)
    b.window_unit(0.30, cy + d * 0.5, 0.46, (0, 1), 0.28, 0.26, shutters=True)
    for sx in (-1, 1):
        b.window_unit(sx * w * 0.5, cy, 0.46, (sx, 0), 0.28, 0.26, shutters=True)
        b.window_unit(sx * w * 0.5, cy, h + 0.20, (sx, 0), 0.20, 0.20, frame_swatch=SANDSTONE)
    b.dormer(0.24, cy - 0.28, h + 0.14, dir_xy=(0, -1), w=0.30, d=0.28, h=0.26, wall_swatch=CREAM, roof_swatch=ROOF)
    b.chimney_home(0.38, cy + 0.20, h + 0.15, h=0.48, swatch=BRICK)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 2. Кирпичный особняк с эркером 1×1 (R, ур. 2)
# ---------------------------------------------------------------------------
def build_brick_villa_1x1():
    clear_scene()
    b = ArchBuilder("res_brick_villa_1x1")
    b.pave_base(1.70, 1.70, swatch=SANDSTONE, border_swatch=STONE)
    w, d, fh = 1.24, 1.18, 0.48
    cx, cy = -0.10, 0.08
    # 1-й этаж кирпичный, 2-й светлый с угловыми рустами
    b.box((cx, cy, fh * 0.5), (w, d, fh), BRICK)
    b.box((cx, cy, fh), (w + 0.05, d + 0.05, 0.045), STONE)
    b.box((cx, cy, fh + fh * 0.5), (w, d, fh), CREAM)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((cx + sx * (w * 0.5 - 0.04), cy + sy * (d * 0.5 - 0.04), fh * 1.5), (0.10, 0.10, fh), STONE)
    # Двухэтажный гранёный эркер на фасаде
    by = cy - d * 0.5 - 0.10
    b.chamfer_prism(cx + 0.28, by, 0.03, 0.46, 0.30, fh * 2.0, 0.10, STONE)
    for fl in (0, 1):
        b.window_unit(cx + 0.28, by - 0.15, fl * fh + 0.26, (0, -1), 0.24, 0.26)
    # Вход и кованый балкончик над ним
    b.entrance_canopy(cx - 0.26, cy - d * 0.5, 0.03, w=0.34, h=0.36, canopy_d=0.18, canopy_swatch=ROOF)
    b.window_unit(cx - 0.26, cy - d * 0.5, fh + 0.26, (0, -1), 0.26, 0.28, balcony=True)
    b.window_grid_wall(cx, cy + d * 0.5, 0.0, w, 2, fh, (0, 1), win_w=0.24, win_h=0.25, step=0.46, start_floor=0, belt_swatch=None)
    b.window_grid_wall(cx - w * 0.5, cy, 0.0, d, 2, fh, (-1, 0), win_w=0.24, win_h=0.25, step=0.48, start_floor=0, belt_swatch=None)
    # Боковой навес (карпорт) справа
    b.box((0.64, cy + 0.04, 0.42), (0.32, 0.88, 0.045), SLATE)
    for sy in (-1, 1):
        b.box((0.76, cy + 0.04 + sy * 0.36, 0.22), (0.045, 0.045, 0.40), IRON)
    # Вальмовая крыша + слуховое окно + труба
    b.hip_roof(cx, cy, fh * 2.0, w, d, 0.46, roof_swatch=ROOF, fascia_swatch=STONE, overhang=0.09)
    b.dormer(cx - 0.16, cy - 0.30, fh * 2.0 + 0.08, dir_xy=(0, -1), w=0.28, d=0.26, h=0.24, wall_swatch=CREAM)
    b.chimney_home(cx - 0.36, cy + 0.28, fh * 2.0 + 0.12, h=0.44, swatch=BRICK)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 3. Современная кубическая вилла с консолью 1×1 (R, ур. 3)
# ---------------------------------------------------------------------------
def build_modern_cube_1x1():
    clear_scene()
    b = ArchBuilder("res_modern_cube_1x1")
    b.pave_base(1.72, 1.72, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.46
    # 1-й этаж: тёмный сланец + деревянные ламели
    b.box((-0.08, 0.10, fh * 0.5), (1.22, 1.14, fh), SLATE)
    b.entrance_canopy(-0.28, 0.10 - 0.57, 0.03, w=0.38, h=0.36, canopy_d=0.16, canopy_swatch=SANDSTONE)
    b.box((0.24, 0.10 - 0.58, fh * 0.52), (0.50, 0.04, fh * 0.72), GLASS_LITE)
    # 2-й этаж: белоснежный консольный блок со сдвигом вперёд и вправо
    b.box((0.06, -0.02, fh * 1.5), (1.36, 1.24, fh), WALL)
    b.box((0.06, -0.02, fh * 2.0 + 0.02), (1.40, 1.28, 0.04), ROOF)
    # Вертикальные деревянные ламели на фасаде 2-го этажа
    for i in range(5):
        lx = -0.52 + i * 0.09
        b.box((lx, -0.65, fh * 1.5), (0.035, 0.05, fh * 0.92), SANDSTONE)
    # Панорамное угловое окно 2-го этажа
    b.box((0.34, -0.645, fh * 1.52), (0.72, 0.03, fh * 0.68), GLASS_DARK)
    b.box((0.745, -0.26, fh * 1.52), (0.03, 0.68, fh * 0.68), GLASS_LITE)
    # 3-й уровень: стеклянный выход на террасу + пергола + солнечные панели
    b.box((-0.24, 0.18, fh * 2.0 + 0.24), (0.70, 0.68, 0.44), CREAM)
    b.box((-0.24, 0.18, fh * 2.0 + 0.48), (0.76, 0.74, 0.045), ROOF)
    b.window_unit(-0.24, 0.18 - 0.34, fh * 2.0 + 0.24, (0, -1), 0.42, 0.30)
    _pergola(b, 0.38, 0.02, fh * 2.0 + 0.04, 0.56, 0.72, h=0.32, swatch=SANDSTONE)
    b.solar_bank(-0.24, 0.18, fh * 2.0 + 0.50, rows=1, cols=2, panel_w=0.28, panel_d=0.36)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 4. Жилой дом-свечка 1×1 (RH, ур. 1)
# ---------------------------------------------------------------------------
def build_point_tower_1x1():
    clear_scene()
    b = ArchBuilder("res_point_tower_1x1")
    b.pave_base(1.72, 1.72, swatch=CONCRETE, border_swatch=STONE)
    w, d, floors, fh = 1.34, 1.34, 7, 0.44
    h = floors * fh
    b.box((0, 0, fh * 0.5), (w + 0.04, d + 0.04, fh), GUNMETAL)
    b.box((0, 0, fh + (h - fh) * 0.5), (w, d, h - fh), WALL)
    # Кирпичные вертикальные пилястры по краям фасадов
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * (w * 0.5 - 0.06), sy * (d * 0.5 - 0.06), h * 0.52), (0.15, 0.15, h), BRICK)
    b.entrance_canopy(0.0, -d * 0.5, 0.03, w=0.46, h=0.36, canopy_d=0.20, canopy_swatch=ROOF)
    b.box_windows_4sides(0, 0, 0, w, d, floors, fh, win_w=0.22, win_h=0.24, step=0.42,
                         front_balconies="checker", back_balconies="alt_floors")
    # Парапет крыши и машинное отделение лифта
    b.box((0, 0, h + 0.04), (w + 0.08, d + 0.08, 0.08), ROOF)
    b.box((0.12, 0.12, h + 0.24), (0.56, 0.52, 0.34), CREAM)
    b.box((0.12, 0.12, h + 0.43), (0.62, 0.58, 0.05), ROOF_LITE)
    b.rooftop_hvac(-0.34, -0.22, h + 0.08, scale=0.72)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 5. Высотный жилой кондоминиум 1×1 (RH, ур. 3)
# ---------------------------------------------------------------------------
def build_sky_condo_1x1():
    clear_scene()
    b = ArchBuilder("res_sky_condo_1x1")
    b.pave_base(1.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.42
    # Двухэтажный гранитный вестибюль
    b.chamfer_prism(0, 0, 0.03, 1.50, 1.50, fh * 2, 0.22, GUNMETAL)
    b.entrance_canopy(0.0, -0.75, 0.03, w=0.52, h=0.42, canopy_d=0.20, canopy_swatch=ROOF)
    # Основной ствол (этажи 3..10) со скошенными углами
    z1 = 0.03 + fh * 2
    h_mid = fh * 8
    b.chamfer_prism(0, 0, z1, 1.32, 1.32, h_mid, 0.22, WALL)
    b.chamfer_windows_4sides(0, 0, z1 - fh, 1.32, 1.32, 0.22, 9, fh, win_w=0.22, win_h=0.25, step=0.38,
                             start_floor=1, front_balconies="alt_floors", back_balconies="alt_floors")
    # Верхний уступ пентхаусов (этажи 11..14) с видовой террасой
    z2 = z1 + h_mid
    b.chamfer_prism(0, 0, z2, 1.38, 1.38, 0.06, 0.22, ROOF)
    h_top = fh * 4
    b.chamfer_prism(0, 0.06, z2 + 0.06, 1.02, 1.02, h_top, 0.18, CREAM)
    b.chamfer_curtain_wall(0, 0.06, z2 + 0.06, 1.02, 1.02, 0.18, 4, fh, mullion_step=0.34,
                           frame_swatch=ALUM, spandrel_swatch=SLATE)
    z3 = z2 + 0.06 + h_top
    b.chamfer_prism(0, 0.06, z3, 1.08, 1.08, 0.07, 0.18, ROOF)
    b.chamfer_prism(0, 0.06, z3 + 0.07, 0.56, 0.56, 0.34, 0.12, WALL)
    b.cylinder((0, 0.06, z3 + 0.72), 0.03, 0.01, 0.64, ALUM, segments=8)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 6. Альпийский/швейцарский дуплекс 2×1 (R, ур. 1)
# ---------------------------------------------------------------------------
def build_swiss_duplex_2x1():
    clear_scene()
    b = ArchBuilder("res_swiss_duplex_2x1")
    b.pave_base(3.72, 1.68, swatch=STONE, border_swatch=CONCRETE)
    # Два сблокированных коттеджа со сдвигом по глубине и высоте
    specs = [(-0.82, 0.06, 1.48, 1.14, 0.78, WALL, ROOF),
             (0.76, -0.04, 1.48, 1.16, 0.88, CREAM, ROOF_LITE)]
    for cx, cy, w, d, h, w_sw, r_sw in specs:
        b.box((cx, cy, 0.12), (w + 0.04, d + 0.04, 0.24), STONE)
        b.box((cx, cy, 0.24 + (h - 0.24) * 0.5), (w, d, h - 0.24), w_sw)
        b.gable_roof(cx, cy, h, w, d, 0.46, roof_swatch=r_sw, gable_swatch=SANDSTONE, trim_swatch=BRICK, overhang=0.09, axis="x")
        # Крыльцо и окна
        b.entrance_canopy(cx - 0.24, cy - d * 0.5, 0.03, w=0.34, h=0.36, canopy_d=0.18, canopy_swatch=r_sw)
        b.window_unit(cx + 0.28, cy - d * 0.5, 0.48, (0, -1), 0.34, 0.28, shutters=True)
        b.window_unit(cx - 0.26, cy + d * 0.5, 0.48, (0, 1), 0.30, 0.26, shutters=True)
        b.window_unit(cx + 0.26, cy + d * 0.5, 0.48, (0, 1), 0.30, 0.26, shutters=True)
        b.dormer(cx + 0.18, cy - 0.28, h + 0.10, dir_xy=(0, -1), w=0.30, d=0.26, h=0.25, wall_swatch=w_sw, roof_swatch=r_sw)
        b.chimney_home(cx + 0.42, cy + 0.22, h + 0.12, h=0.42, swatch=BRICK)
    # Пристроенный гараж справа с секционными воротами
    b.box((1.62, 0.08, 0.30), (0.48, 1.02, 0.56), BRICK)
    b.box((1.62, 0.08, 0.60), (0.54, 1.08, 0.05), STONE)
    b.loading_dock(1.62, 0.08 - 0.51, 0.02, out_xy=(0, -1), w=0.36, h=0.38, canopy_swatch=ROOF)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 7. Голландские дома со ступенчатыми фронтонами 2×1 (R, ур. 2)
# ---------------------------------------------------------------------------
def build_dutch_row_2x1():
    clear_scene()
    b = ArchBuilder("res_dutch_row_2x1")
    b.pave_base(3.72, 1.70, swatch=SANDSTONE, border_swatch=STONE)
    houses = [
        (-1.14, 1.08, 1.24, 3, 0.44, BRICK, ROOF, 4),
        (0.00, 1.12, 1.28, 3, 0.48, CREAM, ROOF_LITE, 5),
        (1.14, 1.08, 1.22, 2, 0.50, TERRACOTTA, ROOF_DEEP, 4),
    ]
    for cx, w, d, floors, fh, w_sw, r_sw, g_steps in houses:
        h = floors * fh
        b.box((cx, 0.04, 0.12), (w, d, 0.24), GUNMETAL)
        b.box((cx, 0.04, 0.24 + (h - 0.24) * 0.5), (w, d, h - 0.24), w_sw)
        # Двускатная крыша коньком вдоль Y (к улице) + ступенчатый фронтон!
        gh = g_steps * 0.115
        b.gable_roof(cx, 0.04, h, w - 0.04, d, gh, roof_swatch=r_sw, gable_swatch=w_sw, trim_swatch=STONE, overhang=0.05, axis="y")
        _stepped_gable(b, cx, 0.04 - d * 0.5, h, w + 0.02, g_steps, 0.12, w_sw, cap_swatch=STONE, out_y=-1)
        # Высокое чердачное окно с балкой подъёмника под коньком
        b.window_unit(cx, 0.04 - d * 0.5 - 0.05, h + gh * 0.36, (0, -1), 0.22, 0.24, frame_swatch=STONE)
        b.box((cx, 0.04 - d * 0.5 - 0.14, h + gh * 0.72), (0.04, 0.18, 0.04), IRON)
        # Парадный вход и высокие окна
        b.entrance_canopy(cx - w * 0.22, 0.04 - d * 0.5, 0.03, w=0.30, h=0.38, canopy_d=0.15, canopy_swatch=STONE)
        b.window_unit(cx + w * 0.22, 0.04 - d * 0.5, 0.28, (0, -1), 0.26, 0.28, frame_swatch=WALL)
        b.window_grid_wall(cx, 0.04 - d * 0.5, 0.0, w, floors, fh, (0, -1),
                           win_w=0.22, win_h=0.28, step=0.40, start_floor=1, frame_swatch=WALL, belt_swatch=STONE)
        b.window_grid_wall(cx, 0.04 + d * 0.5, 0.0, w, floors, fh, (0, 1),
                           win_w=0.22, win_h=0.26, step=0.42, start_floor=0, frame_swatch=WALL, belt_swatch=STONE)
        b.chimney_home(cx + w * 0.32, 0.04 + 0.26, h + 0.18, h=0.36, swatch=BRICK)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 8. Каскадные террасные лофты 2×1 (RH, ур. 2)
# ---------------------------------------------------------------------------
def build_terrace_lofts_2x1():
    clear_scene()
    b = ArchBuilder("res_terrace_lofts_2x1")
    b.pave_base(3.74, 1.72, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.45
    # Три секции ступенями: 3, 4 и 5 этажей с озеленёнными/пергольными террасами
    sections = [
        (-1.12, 1.16, 3, BRICK),
        (0.02, 1.18, 4, WALL),
        (1.16, 1.12, 5, CREAM),
    ]
    for idx, (cx, w, fls, sw) in enumerate(sections):
        d = 1.32 - idx * 0.04
        h = fls * fh
        b.box((cx, 0.04, fh * 0.5), (w, d, fh), GUNMETAL)
        b.box((cx, 0.04, fh + (h - fh) * 0.5), (w, d, h - fh), sw)
        b.box((cx, 0.04, h + 0.03), (w + 0.05, d + 0.05, 0.06), ROOF)
        b.storefront_strip(cx, 0.04 - d * 0.5, 0.03, w, h=fh * 0.90, bays=2, awning_swatch=ROOF)
        b.box_windows_4sides(cx, 0.04, 0.0, w, d, fls, fh, win_w=0.24, win_h=0.26, step=0.44,
                             start_floor=1, front_balconies="all" if idx == 1 else "alt_floors")
        if idx < 2:
            _pergola(b, cx, 0.04, h + 0.06, w * 0.72, d * 0.68, h=0.28, swatch=SANDSTONE)
        else:
            b.solar_bank(cx, 0.04, h + 0.06, rows=2, cols=2, panel_w=0.34, panel_d=0.24)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 9. Английские георгианские таунхаусы 3×1 (R, ур. 2)
# ---------------------------------------------------------------------------
def build_english_townhouses_3x1():
    clear_scene()
    b = ArchBuilder("res_english_townhouses_3x1")
    b.pave_base(5.72, 1.70, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.45
    floors = 3
    h = floors * fh
    unit_w = 1.34
    swatches = [BRICK, CREAM, TERRACOTTA, WALL]
    for i in range(4):
        cx = -2.01 + i * unit_w
        d = 1.24 + (0.06 if i in (1, 2) else 0.0)
        b.box((cx, 0.06, 0.14), (unit_w, d + 0.04, 0.28), STONE)
        b.box((cx, 0.06, 0.28 + (h - 0.28) * 0.5), (unit_w, d, h - 0.28), swatches[i])
        # Брандмауэрные стенки с дымоходами между секциями
        if i < 3:
            bx = cx + unit_w * 0.5
            b.box((bx, 0.06, h + 0.18), (0.09, d + 0.04, 0.36), STONE)
            b.chimney_home(bx, 0.22, h + 0.34, h=0.34, swatch=BRICK)
        # Мансардная крыша и люкарны
        b.mansard_roof(cx, 0.06, h, unit_w - 0.02, d, 0.38, cap_h=0.08, inset=0.18,
                       steep_swatch=ROOF, cap_swatch=SLATE, cornice_swatch=STONE, overhang=0.05)
        b.dormer(cx - 0.28, 0.06 - d * 0.5 + 0.12, h + 0.08, dir_xy=(0, -1), w=0.26, d=0.24, h=0.25, wall_swatch=CREAM)
        b.dormer(cx + 0.28, 0.06 - d * 0.5 + 0.12, h + 0.08, dir_xy=(0, -1), w=0.26, d=0.24, h=0.25, wall_swatch=CREAM)
        # Высокое парадное крыльцо с колоннами + эркер 1-го этажа
        py = 0.06 - d * 0.5
        b.entrance_canopy(cx - 0.28, py, 0.03, w=0.32, h=0.38, canopy_d=0.18, canopy_swatch=STONE)
        b.chamfer_prism(cx + 0.26, py - 0.06, 0.03, 0.44, 0.22, fh * 1.02, 0.08, STONE)
        b.window_unit(cx + 0.26, py - 0.17, 0.26, (0, -1), 0.24, 0.26)
        b.window_grid_wall(cx, py, 0.0, unit_w, floors, fh, (0, -1),
                           win_w=0.22, win_h=0.26, step=0.42, start_floor=1, belt_swatch=STONE, balconies="center")
        b.window_grid_wall(cx, 0.06 + d * 0.5, 0.0, unit_w, floors, fh, (0, 1),
                           win_w=0.22, win_h=0.25, step=0.44, start_floor=0, belt_swatch=STONE)
    return b, 3, 1


# ---------------------------------------------------------------------------
# 10. Альпийский шале-апарт-отель 3×1 (R/RH, ур. 2)
# ---------------------------------------------------------------------------
def build_alpine_apartments_3x1():
    clear_scene()
    b = ArchBuilder("res_alpine_apartments_3x1")
    b.pave_base(5.72, 1.72, swatch=STONE, border_swatch=CONCRETE)
    w, d, fh, floors = 5.36, 1.28, 0.44, 4
    h = floors * fh
    # Каменный 1-й этаж с галереей витрин, деревянно-штукатурные верхние этажи
    b.box((0, 0.05, fh * 0.5), (w, d, fh), STONE)
    b.storefront_strip(0, 0.05 - d * 0.5, 0.03, w, h=fh * 0.88, bays=6, awning_swatch=ROOF)
    b.box((0, 0.05, fh + (h - fh) * 0.5), (w, d, h - fh), CREAM)
    # Непрерывные резные деревянные балконы-галереи на 2..4 этажах
    for fl in range(1, floors):
        zb = fl * fh
        b.box((0, 0.05 - d * 0.5 - 0.11, zb + 0.02), (w - 0.16, 0.22, 0.045), SANDSTONE)
        b.box((0, 0.05 - d * 0.5 - 0.20, zb + 0.11), (w - 0.16, 0.03, 0.14), BRICK)
    b.box_windows_4sides(0, 0.05, 0.0, w, d, floors, fh, win_w=0.24, win_h=0.25, step=0.48, start_floor=1, belt_swatch=SANDSTONE)
    # Многощипцовая скатная крыша: главный продольный скат + 3 поперечных щипца
    b.gable_roof(0, 0.05, h, w, d, 0.50, roof_swatch=ROOF, gable_swatch=SANDSTONE, trim_swatch=BRICK, overhang=0.10, axis="x")
    for gx in (-1.72, 0.0, 1.72):
        b.box((gx, 0.05 - 0.06, h + 0.16), (1.16, d + 0.12, 0.30), CREAM)
        b.gable_roof(gx, 0.05 - 0.06, h + 0.30, 1.18, d + 0.14, 0.32, roof_swatch=ROOF_LITE, gable_swatch=SANDSTONE, trim_swatch=BRICK, overhang=0.07, axis="y")
        b.window_unit(gx, 0.05 - d * 0.5 - 0.13, h + 0.24, (0, -1), 0.30, 0.24, frame_swatch=BRICK)
    for cx_c in (-1.0, 1.0):
        b.chimney_home(cx_c, 0.32, h + 0.32, h=0.44, swatch=STONE)
    return b, 3, 1


# ---------------------------------------------------------------------------
# 11. Парадный неоклассический дом («сталинка») 4×1 (RH, ур. 2)
# ---------------------------------------------------------------------------
def build_stalin_block_4x1():
    clear_scene()
    b = ArchBuilder("res_stalin_block_4x1")
    b.pave_base(7.72, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.44
    w, d = 7.42, 1.34
    _arch_passage_wing(b, 0.0, 0.04, w, d, 5, fh, wall_sw=CREAM, base_sw=GUNMETAL, arch_w=1.22, arch_floors=2)
    b.box_windows_4sides(0.0, 0.04, 0.0, w, d, 5, fh, win_w=0.23, win_h=0.27, step=0.46,
                         start_floor=2, frame_swatch=STONE, belt_swatch=STONE, front_balconies="alt_floors")
    # Два угловых 6-этажных ризалита с пилястрами и балюстрадой
    for sign in (-1, 1):
        rx = sign * 2.86
        rw, rd, rh = 1.62, 1.44, 6 * fh
        b.box((rx, 0.02, fh * 0.5), (rw, rd, fh), GUNMETAL)
        b.box((rx, 0.02, fh + (rh - fh) * 0.5), (rw, rd, rh - fh), TERRACOTTA)
        for px_s in (-0.64, -0.22, 0.22, 0.64):
            b.box((rx + px_s, 0.02 - rd * 0.5 - 0.02, fh + (rh - fh) * 0.5), (0.08, 0.05, rh - fh), STONE)
        b.box_windows_4sides(rx, 0.02, 0.0, rw, rd, 6, fh, win_w=0.22, win_h=0.26, step=0.44, start_floor=1, frame_swatch=STONE)
        b.box((rx, 0.02, rh + 0.04), (rw + 0.12, rd + 0.12, 0.08), STONE)
        b.hip_roof(rx, 0.02, rh + 0.08, rw, rd, 0.28, roof_swatch=ROOF, fascia_swatch=STONE, overhang=0.05)
        b.entrance_canopy(rx, 0.02 - rd * 0.5, 0.03, w=0.44, h=0.38, canopy_d=0.18, canopy_swatch=STONE)
    # Карниз центрального корпуса и бельведер со шпилем над аркой
    hc = 5 * fh
    b.box((0.0, 0.04, hc + 0.04), (w - 3.0, d + 0.10, 0.08), STONE)
    b.chamfer_prism(0.0, 0.04, hc + 0.08, 1.18, 1.06, 0.56, 0.20, CREAM)
    b.chamfer_prism(0.0, 0.04, hc + 0.64, 1.26, 1.14, 0.07, 0.20, STONE)
    b.chamfer_prism(0.0, 0.04, hc + 0.71, 0.72, 0.72, 0.36, 0.16, ROOF)
    b.cylinder((0.0, 0.04, hc + 1.38), 0.035, 0.01, 0.62, COPPER, segments=8)
    return b, 4, 1


# ---------------------------------------------------------------------------
# 12. Современный ЖК переменной этажности 5×1 (RH, ур. 3)
# ---------------------------------------------------------------------------
def build_modern_promenade_5x1():
    clear_scene()
    b = ArchBuilder("res_modern_promenade_5x1")
    b.pave_base(9.72, 1.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.43
    # Единый уличный стилобат с коммерческими витринами
    b.box((0.0, 0.04, fh * 0.55), (9.38, 1.40, fh * 1.1), SLATE)
    b.storefront_strip(-3.0, 0.04 - 0.70, 0.03, 3.0, h=fh, bays=4, awning_swatch=ROOF)
    b.storefront_strip(0.0, 0.04 - 0.70, 0.03, 2.8, h=fh, bays=3, awning_swatch=SANDSTONE)
    b.storefront_strip(3.0, 0.04 - 0.70, 0.03, 3.0, h=fh, bays=4, awning_swatch=ROOF)

    blocks = [
        (-3.16, 2.82, 1.24, 5, WALL, "checker"),
        (0.00, 2.94, 1.32, 8, CREAM, "all"),
        (3.14, 2.84, 1.24, 6, WALL, "checker"),
    ]
    z_base = fh * 1.1
    for idx, (cx, bw, bd, fls, sw, bal) in enumerate(blocks):
        bh = fls * fh
        b.box((cx, 0.04, z_base + bh * 0.5), (bw, bd, bh), sw)
        # Контрастная вертикальная вставка из терракоты/песчаника
        b.box((cx + (0.55 if idx != 1 else 0.0), 0.04 - bd * 0.5 - 0.015, z_base + bh * 0.5),
              (0.56, 0.04, bh), SANDSTONE if idx == 1 else TERRACOTTA)
        b.box_windows_4sides(cx, 0.04, z_base - fh, bw, bd, fls + 1, fh, win_w=0.24, win_h=0.26, step=0.46,
                             start_floor=1, front_balconies=bal, back_balconies="alt_floors")
        zt = z_base + bh
        b.box((cx, 0.04, zt + 0.035), (bw + 0.08, bd + 0.08, 0.07), ROOF)
        if idx == 1:
            b.box((cx, 0.08, zt + 0.25), (1.30, 0.82, 0.36), WALL)
            b.box((cx, 0.08, zt + 0.45), (1.38, 0.88, 0.05), ROOF_LITE)
            b.rooftop_hvac(cx - 0.92, 0.08, zt + 0.07, scale=0.8)
        else:
            _pergola(b, cx - 0.52, 0.04, zt + 0.07, 0.96, 0.78, h=0.30, swatch=SANDSTONE)
            b.solar_bank(cx + 0.62, 0.04, zt + 0.07, rows=1, cols=3, panel_w=0.34, panel_d=0.42)
    return b, 5, 1


# ---------------------------------------------------------------------------
# 13. Большой европейский бульварный дом с мансардой и куполами 7×1 (RH, ур. 3)
# ---------------------------------------------------------------------------
def build_boulevard_mansard_7x1():
    clear_scene()
    b = ArchBuilder("res_boulevard_mansard_7x1")
    b.pave_base(13.72, 1.76, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.43
    floors = 6
    w, d = 13.36, 1.34
    _arch_passage_wing(b, 0.0, 0.04, w, d, floors, fh, wall_sw=CREAM, base_sw=STONE, arch_w=1.42, arch_floors=2)
    # Витрины кафе/бутиков вдоль тротуара слева и справа от арки
    b.storefront_strip(-3.9, 0.04 - d * 0.5, 0.03, 4.6, h=fh * 0.92, bays=6, awning_swatch=ROOF_DEEP)
    b.storefront_strip(3.9, 0.04 - d * 0.5, 0.03, 4.6, h=fh * 0.92, bays=6, awning_swatch=ROOF_DEEP)
    # Непрерывные кованые балконы османовского типа на 3-м и 5-м этажах
    for fl in (2, 4):
        zb = fl * fh
        b.box((0.0, 0.04 - d * 0.5 - 0.09, zb + 0.02), (w - 0.4, 0.18, 0.04), STONE)
        b.box((0.0, 0.04 - d * 0.5 - 0.16, zb + 0.10), (w - 0.4, 0.025, 0.13), IRON)
    b.box_windows_4sides(0.0, 0.04, 0.0, w - 2.2, d, floors, fh, win_w=0.23, win_h=0.28, step=0.46,
                         start_floor=2, frame_swatch=STONE, belt_swatch=STONE)
    h = floors * fh
    b.mansard_roof(0.0, 0.04, h, w - 0.20, d, 0.46, cap_h=0.10, inset=0.24,
                   steep_swatch=SLATE, cap_swatch=ROOF, cornice_swatch=STONE, overhang=0.07)
    # Ряд мансардных люкарн и дымовых труб
    for dx in (-4.6, -3.4, -2.2, -1.0, 1.0, 2.2, 3.4, 4.6):
        b.dormer(dx, 0.04 - d * 0.5 + 0.14, h + 0.10, dir_xy=(0, -1), w=0.30, d=0.26, h=0.28, wall_swatch=STONE, roof_swatch=ROOF)
    for cx_c in (-4.0, -1.6, 1.6, 4.0):
        b.chimney_home(cx_c, 0.28, h + 0.48, h=0.38, swatch=TERRACOTTA)
    # Две угловые восьмигранные башни-ротонды с шатровыми куполами и шпилями
    for sign in (-1, 1):
        tx = sign * 5.95
        th = (floors + 1) * fh
        b.chamfer_prism(tx, 0.0, 0.03, 1.50, 1.50, fh, 0.28, STONE)
        b.chamfer_prism(tx, 0.0, 0.03 + fh, 1.44, 1.44, th - fh, 0.28, WALL)
        b.chamfer_windows_4sides(tx, 0.0, 0.03, 1.44, 1.44, 0.28, floors + 1, fh, win_w=0.22, win_h=0.26, step=0.40, start_floor=1, frame_swatch=STONE)
        b.chamfer_prism(tx, 0.0, 0.03 + th, 1.54, 1.54, 0.08, 0.28, STONE)
        # Гранёный купол и шпиль
        b.cylinder((tx, 0.0, 0.03 + th + 0.34), 0.72, 0.24, 0.52, ROOF, segments=8)
        b.cylinder((tx, 0.0, 0.03 + th + 0.68), 0.22, 0.06, 0.20, COPPER, segments=8)
        b.cylinder((tx, 0.0, 0.03 + th + 1.02), 0.03, 0.01, 0.52, COPPER, segments=8)
    return b, 7, 1


# ---------------------------------------------------------------------------
# 14. Г-образная городская усадьба с садовым двором 2×2 (R, ур. 3)
# ---------------------------------------------------------------------------
def build_garden_estate_2x2():
    clear_scene()
    b = ArchBuilder("res_garden_estate_2x2")
    b.pave_base(3.72, 3.72, swatch=SANDSTONE, border_swatch=STONE)
    fh = 0.48
    # Главный двухэтажный корпус вдоль задней и левой стороны
    mw, md = 3.24, 1.32
    mcy = 0.96
    b.box((0.0, mcy, 0.14), (mw + 0.04, md + 0.04, 0.28), STONE)
    b.box((0.0, mcy, 0.28 + (fh * 2 - 0.28) * 0.5), (mw, md, fh * 2 - 0.28), CREAM)
    b.hip_roof(0.0, mcy, fh * 2, mw, md, 0.52, roof_swatch=ROOF, fascia_swatch=STONE, overhang=0.10)
    b.box_windows_4sides(0.0, mcy, 0.0, mw, md, 2, fh, win_w=0.26, win_h=0.28, step=0.52, start_floor=0,
                         frame_swatch=SLATE, front_balconies="center")
    b.entrance_canopy(0.32, mcy - md * 0.5, 0.03, w=0.44, h=0.40, canopy_d=0.22, canopy_swatch=ROOF)
    b.dormer(-0.65, mcy - 0.34, fh * 2 + 0.10, dir_xy=(0, -1), w=0.30, d=0.26, h=0.26, wall_swatch=CREAM)
    b.dormer(0.65, mcy - 0.34, fh * 2 + 0.10, dir_xy=(0, -1), w=0.30, d=0.26, h=0.26, wall_swatch=CREAM)
    b.chimney_home(-1.05, mcy + 0.24, fh * 2 + 0.16, h=0.48, swatch=BRICK)

    # Левое переднее крыло (каретный гараж и зимний сад)
    ww, wd = 1.24, 1.72
    wcx, wcy = -1.00, -0.52
    b.box((wcx, wcy, fh * 0.55), (ww, wd, fh * 1.1), BRICK)
    b.hip_roof(wcx, wcy, fh * 1.1, ww, wd, 0.38, roof_swatch=ROOF_LITE, fascia_swatch=STONE, overhang=0.08)
    b.loading_dock(wcx, wcy - wd * 0.5, 0.02, out_xy=(0, -1), w=0.54, h=0.40, canopy_swatch=STONE)
    b.window_grid_wall(wcx + ww * 0.5, wcy, 0.0, wd, 1, fh, (1, 0), win_w=0.30, win_h=0.30, step=0.52, start_floor=0, belt_swatch=None)

    # Дворовая пергола, парадная кирпично-кованая ограда справа спереди и ворота
    _pergola(b, 0.68, -0.42, 0.03, 1.22, 1.12, h=0.38, swatch=SANDSTONE)
    fy = -1.62
    for px in (-0.18, 0.58, 1.56):
        b.box((px, fy, 0.22), (0.14, 0.14, 0.40), BRICK)
        b.box((px, fy, 0.44), (0.18, 0.18, 0.05), STONE)
    b.box((1.07, fy, 0.14), (0.86, 0.07, 0.22), BRICK)
    b.box((1.07, fy, 0.30), (0.84, 0.03, 0.12), IRON)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 15. Каре-квартал с мансардой и открытым двором 2×2 (RH, ур. 1)
# ---------------------------------------------------------------------------
def build_courtyard_mansard_2x2():
    clear_scene()
    b = ArchBuilder("res_courtyard_mansard_2x2")
    b.pave_base(3.74, 3.74, swatch=STONE, border_swatch=CONCRETE)
    fh, floors = 0.44, 4
    h = floors * fh
    # Задний корпус + два боковых крыла образуют уютный мощёный двор на улицу (−Y)
    b.box((0.0, 1.12, fh * 0.5), (3.44, 1.12, fh), GUNMETAL)
    b.box((0.0, 1.12, fh + (h - fh) * 0.5), (3.44, 1.12, h - fh), WALL)
    b.mansard_roof(0.0, 1.12, h, 3.44, 1.12, 0.38, cap_h=0.08, inset=0.18, steep_swatch=ROOF, cap_swatch=SLATE)
    b.box_windows_4sides(0.0, 1.12, 0.0, 3.44, 1.12, floors, fh, win_w=0.22, win_h=0.25, step=0.44, start_floor=1)
    b.entrance_canopy(0.0, 1.12 - 0.56, 0.03, w=0.46, h=0.38, canopy_d=0.18, canopy_swatch=ROOF)

    for sign in (-1, 1):
        wx = sign * 1.16
        b.box((wx, -0.34, fh * 0.5), (1.12, 2.02, fh), GUNMETAL)
        b.box((wx, -0.34, fh + (h - fh) * 0.5), (1.12, 2.02, h - fh), CREAM)
        b.mansard_roof(wx, -0.34, h, 1.12, 2.02, 0.38, cap_h=0.08, inset=0.18, steep_swatch=ROOF, cap_swatch=SLATE)
        b.storefront_strip(wx, -0.34 - 1.01, 0.03, 1.10, h=fh * 0.88, bays=2, awning_swatch=ROOF_LITE)
        b.box_windows_4sides(wx, -0.34, 0.0, 1.12, 2.02, floors, fh, win_w=0.22, win_h=0.25, step=0.44,
                             start_floor=1, front_balconies="center")
        b.dormer(wx, -0.34 - 0.72, h + 0.08, dir_xy=(0, -1), w=0.28, d=0.24, h=0.25, wall_swatch=CREAM)
        b.chimney_home(wx + sign * 0.22, 0.45, h + 0.42, h=0.36, swatch=BRICK)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 16. Жилая высотка на двухэтажном стилобате 2×2 (RH, ур. 3)
# ---------------------------------------------------------------------------
def build_tower_podium_2x2():
    clear_scene()
    b = ArchBuilder("res_tower_podium_2x2")
    b.pave_base(3.74, 3.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.42
    # Двухэтажный кирпично-стеклянный стилобат на весь участок
    ph = fh * 2
    b.chamfer_prism(0, 0, 0.03, 3.46, 3.46, ph, 0.28, BRICK)
    b.chamfer_prism(0, 0, 0.03 + ph, 3.54, 3.54, 0.06, 0.28, STONE)
    b.storefront_strip(0.0, -1.73, 0.03, 2.90, h=fh * 0.95, bays=4, awning_swatch=ROOF)
    b.window_grid_wall(0.0, -1.73, 0.03, 2.90, 2, fh, (0, -1), win_w=0.28, win_h=0.26, step=0.52, start_floor=1)

    # 10-этажная башня (общая высота 12 этажей), смещённая к левому заднему углу, и терраса спереди
    tx, ty = -0.38, 0.34
    zt = 0.09 + ph
    th = fh * 10
    b.chamfer_prism(tx, ty, zt, 2.18, 2.18, th, 0.34, WALL)
    b.chamfer_windows_4sides(tx, ty, zt - fh, 2.18, 2.18, 0.34, 11, fh, win_w=0.24, win_h=0.26, step=0.44,
                             start_floor=1, front_balconies="checker", back_balconies="alt_floors")
    # Двухэтажная корона пентхауса
    z_top = zt + th
    b.chamfer_prism(tx, ty, z_top, 2.28, 2.28, 0.07, 0.34, ROOF)
    b.chamfer_prism(tx, ty, z_top + 0.07, 1.48, 1.48, fh * 2, 0.24, CREAM)
    b.chamfer_curtain_wall(tx, ty, z_top + 0.07, 1.48, 1.48, 0.24, 2, fh, mullion_step=0.38)
    b.chamfer_prism(tx, ty, z_top + 0.07 + fh * 2, 1.56, 1.56, 0.07, 0.24, ROOF_LITE)
    b.rooftop_hvac(tx + 0.22, ty + 0.22, z_top + 0.14 + fh * 2, scale=0.82)

    # Благоустроенная кровля стилобата справа спереди
    _pergola(b, 1.02, -0.92, zt, 1.14, 1.10, h=0.34, swatch=SANDSTONE)
    b.solar_bank(1.06, 0.68, zt, rows=2, cols=2, panel_w=0.34, panel_d=0.32)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 17. П-образный жилой квартал со скатными крышами 3×2 (RH, ур. 2)
# ---------------------------------------------------------------------------
def build_cloister_quarter_3x2():
    clear_scene()
    b = ArchBuilder("res_cloister_quarter_3x2")
    b.pave_base(5.74, 3.74, swatch=SANDSTONE, border_swatch=STONE)
    fh, floors = 0.44, 5
    h = floors * fh
    # Передний продольный корпус с центральной проездной аркой во двор
    _arch_passage_wing(b, 0.0, -1.04, 5.42, 1.24, floors, fh, wall_sw=WALL, base_sw=STONE, arch_w=1.26, arch_floors=2)
    b.storefront_strip(-1.72, -1.04 - 0.62, 0.03, 1.88, h=fh * 0.90, bays=3, awning_swatch=ROOF)
    b.storefront_strip(1.72, -1.04 - 0.62, 0.03, 1.88, h=fh * 0.90, bays=3, awning_swatch=ROOF)
    b.box_windows_4sides(0.0, -1.04, 0.0, 5.42, 1.24, floors, fh, win_w=0.23, win_h=0.25, step=0.46,
                         start_floor=2, front_balconies="alt_floors")
    b.gable_roof(0.0, -1.04, h, 5.42, 1.24, 0.46, roof_swatch=ROOF, gable_swatch=WALL, trim_swatch=STONE, overhang=0.08, axis="x")
    for dx in (-1.9, -0.8, 0.8, 1.9):
        b.dormer(dx, -1.04 - 0.34, h + 0.10, dir_xy=(0, -1), w=0.28, d=0.25, h=0.26, wall_swatch=CREAM)

    # Два глубоких дворовых крыла слева и справа
    for sign in (-1, 1):
        wx = sign * 2.06
        b.box((wx, 0.66, fh * 0.5), (1.30, 2.24, fh), STONE)
        b.box((wx, 0.66, fh + (h - fh) * 0.5), (1.30, 2.24, h - fh), CREAM)
        b.gable_roof(wx, 0.66, h, 1.30, 2.24, 0.46, roof_swatch=ROOF_LITE, gable_swatch=CREAM, trim_swatch=STONE, overhang=0.07, axis="y")
        _stepped_gable(b, wx, 0.66 + 1.12, h, 1.30, 4, 0.115, CREAM, cap_swatch=STONE, out_y=1)
        b.box_windows_4sides(wx, 0.66, 0.0, 1.30, 2.24, floors, fh, win_w=0.22, win_h=0.25, step=0.45,
                             start_floor=1, front_balconies="none")
        b.chimney_home(wx, 0.80, h + 0.24, h=0.42, swatch=BRICK)

    # Пергола и клумба в центре тихого двора
    _pergola(b, 0.0, 0.72, 0.03, 1.46, 1.18, h=0.34, swatch=SANDSTONE)
    return b, 3, 2


# ---------------------------------------------------------------------------
# 18. Две жилые башни на общем стилобате 3×2 (RH, ур. 3)
# ---------------------------------------------------------------------------
def build_twin_towers_3x2():
    clear_scene()
    b = ArchBuilder("res_twin_towers_3x2")
    b.pave_base(5.74, 3.74, swatch=STONE, border_swatch=CONCRETE)
    fh = 0.42
    ph = fh * 2
    # П-образный двухэтажный стилобат с парадным курдонёром по центру улицы
    for sign in (-1, 1):
        b.chamfer_prism(sign * 1.72, 0.0, 0.03, 2.02, 3.42, ph, 0.22, SLATE)
        b.storefront_strip(sign * 1.72, -1.71, 0.03, 1.76, h=fh * 0.94, bays=3, awning_swatch=ROOF)
    b.box((0.0, 0.86, 0.03 + ph * 0.5), (2.20, 1.66, ph), SLATE)
    b.entrance_canopy(0.0, 0.03, 0.03, w=0.68, h=0.46, canopy_d=0.26, canopy_swatch=ROOF)
    b.box((0.0, 0.86, 0.03 + ph + 0.03), (5.48, 1.72, 0.06), ROOF_LITE)

    # Левая 13-этажная и правая 10-этажная жилые башни со скошенными гранями
    towers = [(-1.68, 0.14, 11, WALL), (1.68, -0.10, 8, CREAM)]
    zp = 0.09 + ph
    for tx, ty, fls, sw in towers:
        th = fls * fh
        b.chamfer_prism(tx, ty, zp, 1.82, 2.18, th, 0.28, sw)
        b.chamfer_windows_4sides(tx, ty, zp - fh, 1.82, 2.18, 0.28, fls + 1, fh, win_w=0.24, win_h=0.26, step=0.44,
                                 start_floor=1, front_balconies="checker", back_balconies="alt_floors")
        zt = zp + th
        b.chamfer_prism(tx, ty, zt, 1.90, 2.26, 0.07, 0.28, ROOF)
        # Пентхаус и видовая терраса
        b.chamfer_prism(tx, ty + 0.20, zt + 0.07, 1.24, 1.32, fh * 2, 0.20, WALL)
        b.chamfer_curtain_wall(tx, ty + 0.20, zt + 0.07, 1.24, 1.32, 0.20, 2, fh, mullion_step=0.36)
        b.chamfer_prism(tx, ty + 0.20, zt + 0.07 + fh * 2, 1.32, 1.40, 0.06, 0.20, ROOF)
        _pergola(b, tx, ty - 0.68, zt + 0.07, 0.96, 0.56, h=0.28, swatch=SANDSTONE)
    # Озеленённый мостик-терраса на кровле стилобата
    _pergola(b, 0.0, 0.86, zp, 1.12, 1.12, h=0.32, swatch=SANDSTONE)
    return b, 3, 2


RESIDENTIAL_SPECS = [
    ("res_nordic_cottage_1x1", "Скандинавский коттедж", "RESIDENTIAL", 1, build_nordic_cottage_1x1),
    ("res_brick_villa_1x1", "Кирпичный особняк с эркером", "RESIDENTIAL", 2, build_brick_villa_1x1),
    ("res_modern_cube_1x1", "Современная вилла с консолью", "RESIDENTIAL", 3, build_modern_cube_1x1),
    ("res_point_tower_1x1", "Кирпично-монолитный дом-свечка", "RESIDENTIAL_HIGH", 1, build_point_tower_1x1),
    ("res_sky_condo_1x1", "Жилой небоскрёб-кондоминиум", "RESIDENTIAL_HIGH", 3, build_sky_condo_1x1),
    ("res_swiss_duplex_2x1", "Двухсекционный дом-дуплекс", "RESIDENTIAL", 1, build_swiss_duplex_2x1),
    ("res_dutch_row_2x1", "Дома со ступенчатыми фронтонами", "RESIDENTIAL", 2, build_dutch_row_2x1),
    ("res_terrace_lofts_2x1", "Каскадные террасные лофты", "RESIDENTIAL_HIGH", 2, build_terrace_lofts_2x1),
    ("res_english_townhouses_3x1", "Английские таунхаусы с мансардой", "RESIDENTIAL", 2, build_english_townhouses_3x1),
    ("res_alpine_apartments_3x1", "Альпийский шале-дом с галереями", "RESIDENTIAL_HIGH", 1, build_alpine_apartments_3x1),
    ("res_stalin_block_4x1", "Парадный неоклассический дом", "RESIDENTIAL_HIGH", 2, build_stalin_block_4x1),
    ("res_modern_promenade_5x1", "Жилой комплекс переменной этажности", "RESIDENTIAL_HIGH", 3, build_modern_promenade_5x1),
    ("res_boulevard_mansard_7x1", "Бульварный дом с ротондами и аркой", "RESIDENTIAL_HIGH", 3, build_boulevard_mansard_7x1),
    ("res_garden_estate_2x2", "Городская Г-образная усадьба", "RESIDENTIAL", 3, build_garden_estate_2x2),
    ("res_courtyard_mansard_2x2", "Каре-квартал с открытым двором", "RESIDENTIAL_HIGH", 1, build_courtyard_mansard_2x2),
    ("res_tower_podium_2x2", "Жилая высотка на стилобате", "RESIDENTIAL_HIGH", 3, build_tower_podium_2x2),
    ("res_cloister_quarter_3x2", "П-образный квартал со скатной крышей", "RESIDENTIAL_HIGH", 2, build_cloister_quarter_3x2),
    ("res_twin_towers_3x2", "Парные жилые башни с курдонёром", "RESIDENTIAL_HIGH", 3, build_twin_towers_3x2),
]
