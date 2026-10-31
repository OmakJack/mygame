"""Пак заводов и промышленных комплексов (15 моделей от 1×1 до 7×1 и 3×2) для CityBuilder."""

import math

from arch_kit import (
    ALUM,
    ArchBuilder,
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
    clear_scene,
)


def _pipe_rack(b: ArchBuilder, x1, y1, x2, y2, z_pipe, pipes=2, r=0.055, pipe_sw=ALUM):
    """Надземная эстакада трубопроводов между узлами завода."""
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    if length < 0.08:
        return
    ang = math.atan2(dy, dx)
    mx, my = (x1 + x2) * 0.5, (y1 + y2) * 0.5
    # Опоры эстакады
    supports = max(2, int(length / 1.2) + 1)
    for s in range(supports):
        t = (s + 0.3) / supports if supports == 2 else s / max(1, supports - 1)
        t = min(0.88, max(0.12, t))
        sx, sy = x1 + dx * t, y1 + dy * t
        b.box((sx, sy, z_pipe * 0.5), (0.07, 0.28, z_pipe), GUNMETAL, angle_z=ang)
        b.box((sx, sy, z_pipe), (0.09, 0.34, 0.05), STEEL, angle_z=ang)
    # Трубы параллельно
    nx, ny = -dy / length, dx / length
    for i in range(pipes):
        off = (i - (pipes - 1) * 0.5) * (r * 2.5)
        sw = TERRACOTTA if i == 1 and pipes > 2 else pipe_sw
        b.tilted_box((mx + nx * off, my + ny * off, z_pipe + r + 0.03),
                     (length, r * 1.85, r * 1.85), sw, yaw_z=ang)


def _shipping_container(b: ArchBuilder, cx, cy, z0, swatch, angle_z=0.0, length=1.12):
    """Гофрированный морской контейнер во дворе терминала."""
    w, h = 0.44, 0.44
    b.box((cx, cy, z0 + h * 0.5), (length, w, h), swatch, angle_z=angle_z)
    b.box((cx, cy, z0 + h + 0.012), (length + 0.02, w + 0.02, 0.024), IRON, angle_z=angle_z)


def _cyclone_separator(b: ArchBuilder, x, y, z0, scale=1.0):
    """Наружный промышленный циклон-пылеуловитель на стальной раме."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((x + sx * 0.13 * scale, y + sy * 0.13 * scale, z0 + 0.22 * scale),
                  (0.045, 0.045, 0.44 * scale), IRON)
    b.cylinder((x, y, z0 + 0.36 * scale), 0.04 * scale, 0.18 * scale, 0.30 * scale, STEEL, segments=10)
    b.cylinder((x, y, z0 + 0.66 * scale), 0.18 * scale, 0.18 * scale, 0.32 * scale, ALUM, segments=10)
    b.cylinder((x, y, z0 + 0.90 * scale), 0.08 * scale, 0.08 * scale, 0.20 * scale, IRON, segments=8)


# ---------------------------------------------------------------------------
# 1. Кирпичная ремесленная мастерская 1×1 (I, ур. 1)
# ---------------------------------------------------------------------------
def build_ind_brick_workshop_1x1():
    clear_scene()
    b = ArchBuilder("ind_brick_workshop_1x1")
    b.pave_base(1.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    w, d, h = 1.38, 1.24, 0.88
    cx, cy = -0.06, 0.08
    b.box((cx, cy, 0.12), (w + 0.04, d + 0.04, 0.24), GUNMETAL)
    b.box((cx, cy, 0.24 + (h - 0.24) * 0.5), (w, d, h - 0.24), BRICK)
    # Фальцевая двускатная крыша + зенитный световой конёк
    b.gable_roof(cx, cy, h, w, d, 0.42, roof_swatch=SLATE, gable_swatch=BRICK, trim_swatch=STONE, overhang=0.08, axis="y")
    b.box((cx, cy, h + 0.44), (0.40, d * 0.66, 0.16), SLATE)
    for sx in (-1, 1):
        b.box((cx + sx * 0.205, cy, h + 0.44), (0.02, d * 0.58, 0.10), GLASS_LITE)
    # Подъёмные ворота на улице + большие цеховые окна по бокам
    b.loading_dock(cx - 0.22, cy - d * 0.5, 0.02, out_xy=(0, -1), w=0.56, h=0.52, canopy_swatch=TERRACOTTA)
    b.window_unit(cx + 0.38, cy - d * 0.5, 0.52, (0, -1), 0.30, 0.34, frame_swatch=IRON)
    for sx in (-1, 1):
        b.window_grid_wall(cx + sx * w * 0.5, cy, 0.14, d, 1, 0.68, (sx, 0),
                           win_w=0.34, win_h=0.38, step=0.52, start_floor=0, frame_swatch=IRON, belt_swatch=None)
    # Заводская кирпичная труба справа сзади
    b.smokestack(0.58, 0.48, 0.03, height=1.82, r_base=0.16, r_top=0.10, body_swatch=BRICK, stripe_swatch=STONE)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 2. Котельная / энергоблок с циклоном и трубой 1×1 (I, ур. 2)
# ---------------------------------------------------------------------------
def build_ind_boiler_house_1x1():
    clear_scene()
    b = ArchBuilder("ind_boiler_house_1x1")
    b.pave_base(1.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Высокий котельный зал + низкое машинное крыло
    b.box((-0.24, 0.06, 0.68), (0.98, 1.28, 1.36), CLAY)
    b.box((-0.24, 0.06, 1.39), (1.04, 1.34, 0.06), SLATE)
    b.window_grid_wall(-0.24, 0.06 - 0.64, 0.18, 0.96, 2, 0.54, (0, -1),
                       win_w=0.26, win_h=0.34, step=0.40, start_floor=0, frame_swatch=IRON, belt_swatch=GUNMETAL)
    b.loading_dock(-0.28, 0.06 - 0.64, 0.02, out_xy=(0, -1), w=0.46, h=0.44, canopy_swatch=ROOF)
    b.rooftop_hvac(-0.24, 0.12, 1.42, scale=0.80)
    # Циклон, топливный бак и высокая полосатая труба справа
    _cyclone_separator(b, 0.48, -0.34, 0.03, scale=0.92)
    b.smokestack(0.46, 0.36, 0.03, height=2.55, r_base=0.22, r_top=0.13, body_swatch=CONCRETE, stripe_swatch=TERRACOTTA)
    _pipe_rack(b, -0.05, 0.36, 0.46, 0.36, 0.95, pipes=2, r=0.05, pipe_sw=STEEL)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 3. Чистый приборостроительный цех (Clean-Tech Lab) 1×1 (I, ур. 3)
# ---------------------------------------------------------------------------
def build_ind_precision_lab_1x1():
    clear_scene()
    b = ArchBuilder("ind_precision_lab_1x1")
    b.pave_base(1.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    w, d, h = 1.46, 1.38, 1.16
    b.chamfer_prism(0, 0.04, 0.03, w, d, 0.28, 0.16, GUNMETAL)
    b.chamfer_prism(0, 0.04, 0.31, w, d, h - 0.28, 0.16, WALL)
    # Горизонтальное ленточное остекление чистой зоны + акцентный фриз
    for sign in (-1, 1):
        b.box((0, 0.04 + sign * (d * 0.5 + 0.01), 0.78), (w - 0.34, 0.03, 0.30), GLASS_LITE)
        b.box((sign * (w * 0.5 + 0.01), 0.04, 0.78), (0.03, d - 0.34, 0.30), GLASS_DARK)
    b.chamfer_prism(0, 0.04, h + 0.03, w + 0.06, d + 0.06, 0.07, 0.16, ROOF)
    b.entrance_canopy(-0.28, 0.04 - d * 0.5, 0.03, w=0.44, h=0.38, canopy_d=0.18, canopy_swatch=ROOF)
    b.loading_dock(0.36, 0.04 - d * 0.5, 0.02, out_xy=(0, -1), w=0.42, h=0.40, canopy_swatch=ALUM)
    # Шедовый световой фонарь и солнечные батареи на крыше
    b.sawtooth_roof(-0.24, 0.06, h + 0.10, 0.72, 0.92, teeth=2, tooth_h=0.24, roof_swatch=ALUM, wall_swatch=WALL, axis="y")
    b.rooftop_hvac(0.40, 0.24, h + 0.10, scale=0.82)
    b.solar_bank(0.40, -0.24, h + 0.10, rows=1, cols=1, panel_w=0.44, panel_d=0.34)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 4. Механический завод с шедовой зубчатой крышей 2×1 (I, ур. 1)
# ---------------------------------------------------------------------------
def build_ind_sawtooth_mill_2x1():
    clear_scene()
    b = ArchBuilder("ind_sawtooth_mill_2x1")
    b.pave_base(3.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    w, d, h = 2.96, 1.36, 0.98
    cx = -0.24
    b.box((cx, 0.04, 0.16), (w + 0.04, d + 0.04, 0.32), GUNMETAL)
    b.box((cx, 0.04, 0.32 + (h - 0.32) * 0.5), (w, d, h - 0.32), WALL)
    # Четырёхзубчатая шедовая крыша вдоль оси X!
    b.sawtooth_roof(cx, 0.04, h, w, d, teeth=4, tooth_h=0.36, roof_swatch=SLATE, wall_swatch=WALL, axis="x")
    # Два грузовых дока и цеховые окна на фасаде
    b.loading_dock(cx - 0.86, 0.04 - d * 0.5, 0.02, out_xy=(0, -1), w=0.58, h=0.48, canopy_swatch=TERRACOTTA)
    b.loading_dock(cx - 0.10, 0.04 - d * 0.5, 0.02, out_xy=(0, -1), w=0.58, h=0.48, canopy_swatch=TERRACOTTA)
    b.window_grid_wall(cx + 0.78, 0.04 - d * 0.5, 0.14, 1.04, 1, 0.72, (0, -1),
                       win_w=0.32, win_h=0.36, step=0.46, start_floor=0, frame_swatch=IRON, belt_swatch=None)
    b.window_grid_wall(cx, 0.04 + d * 0.5, 0.14, w, 1, 0.72, (0, 1),
                       win_w=0.34, win_h=0.36, step=0.54, start_floor=0, frame_swatch=IRON, belt_swatch=None)
    # Котельная пристройка и труба справа
    b.box((1.48, 0.12, 0.42), (0.56, 1.02, 0.84), BRICK)
    b.smokestack(1.50, 0.36, 0.03, height=2.20, r_base=0.19, r_top=0.11, body_swatch=BRICK, stripe_swatch=TERRACOTTA)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 5. Сборочный ангар с арочным сводом на рёбрах 2×1 (I, ур. 2)
# ---------------------------------------------------------------------------
def build_ind_barrel_hangar_2x1():
    clear_scene()
    b = ArchBuilder("ind_barrel_hangar_2x1")
    b.pave_base(3.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Арочный ангар слева (повёрнут вдоль X? Нет, вдоль Y смотрит огромными воротами на улицу, плюс второй пролёт!)
    # Поставим сдвоенный арочный свод, обращённый торцевыми воротами на фасад −Y, + двухэтажная диспетчерская!
    for idx, hx in enumerate((-0.92, 0.42)):
        hw, hd, wh = 1.32, 1.38, 0.68
        b.box((hx, 0.04, wh * 0.5), (hw, hd, wh), GUNMETAL if idx == 0 else WALL)
        b.barrel_roof(hx, 0.04, wh, hw, hd, 0.52, roof_swatch=ALUM if idx == 0 else ROOF,
                      end_swatch=WALL, rib_swatch=STEEL, segments=10, ribs=4)
        b.loading_dock(hx, 0.04 - hd * 0.5, 0.02, out_xy=(0, -1), w=0.72, h=0.54, canopy_swatch=TERRACOTTA)
        # Полукруглое окно в люнете над воротами
        b.window_unit(hx, 0.04 - hd * 0.5, wh + 0.22, (0, -1), 0.52, 0.24, frame_swatch=SLATE)
    # Двухэтажная башенка диспетчерской справа
    ox, oy = 1.44, -0.02
    b.box((ox, oy, 0.68), (0.68, 1.24, 1.36), CREAM)
    b.box((ox, oy, 1.40), (0.74, 1.30, 0.07), ROOF)
    b.entrance_canopy(ox, oy - 0.62, 0.03, w=0.38, h=0.38, canopy_d=0.16, canopy_swatch=ROOF)
    b.window_unit(ox, oy - 0.62, 1.02, (0, -1), 0.44, 0.30, frame_swatch=SLATE)
    b.rooftop_hvac(ox, oy + 0.16, 1.44, scale=0.75)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 6. Компактный химреакторный узел с цистерной и колоннами 2×1 (I, ур. 3)
# ---------------------------------------------------------------------------
def build_ind_chem_reactor_2x1():
    clear_scene()
    b = ArchBuilder("ind_chem_reactor_2x1")
    b.pave_base(3.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Аппаратно-операторный корпус слева
    b.box((-1.04, 0.06, 0.62), (1.36, 1.28, 1.24), WALL)
    b.box((-1.04, 0.06, 1.27), (1.42, 1.34, 0.06), ROOF)
    b.entrance_canopy(-1.26, 0.06 - 0.64, 0.03, w=0.40, h=0.38, canopy_d=0.16, canopy_swatch=ROOF)
    b.window_grid_wall(-1.04, 0.06 - 0.64, 0.56, 1.26, 1, 0.52, (0, -1), win_w=0.28, win_h=0.28, step=0.44, start_floor=0, belt_swatch=None)
    b.rooftop_hvac(-1.04, 0.14, 1.30, scale=0.85)
    # Две стальные ректификационные колонны в центре с кольцевыми площадками обслуживания
    for cx_col, h_col, r_col in ((0.06, 2.35, 0.24), (0.66, 1.95, 0.20)):
        b.cylinder((cx_col, 0.22, 0.03 + h_col * 0.5), r_col, r_col * 0.94, h_col, ALUM, segments=14)
        for frac in (0.38, 0.72):
            b.cylinder((cx_col, 0.22, 0.03 + h_col * frac), r_col + 0.07, r_col + 0.07, 0.04, TERRACOTTA, segments=14)
    # Горизонтальная напорная цистерна справа спереди и трубная эстакада
    b.horizontal_tank(1.06, -0.34, 0.03, radius=0.28, length=1.22, swatch=STEEL, band_swatch=ROOF_WARM, axis="x")
    _pipe_rack(b, -0.38, 0.22, 1.34, 0.22, 0.88, pipes=3, r=0.045, pipe_sw=ALUM)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 7. Краснокирпичный литейный завод с фонарём и двумя трубами 3×1 (I, ур. 2)
# ---------------------------------------------------------------------------
def build_ind_red_foundry_3x1():
    clear_scene()
    b = ArchBuilder("ind_red_foundry_3x1")
    b.pave_base(5.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Главный базиликальный литейный цех из тёмного кирпича с пилястрами
    w, d, h = 4.28, 1.36, 1.24
    cx = -0.52
    b.box((cx, 0.04, 0.18), (w + 0.06, d + 0.06, 0.36), GUNMETAL)
    b.box((cx, 0.04, 0.36 + (h - 0.36) * 0.5), (w, d, h - 0.36), BRICK)
    # Кирпичные контрфорсы-пилястры и высокие окна цеха
    bays = 6
    step = (w - 0.24) / bays
    for i in range(bays + 1):
        px = cx - (w - 0.24) * 0.5 + i * step
        for sy in (-1, 1):
            b.box((px, 0.04 + sy * (d * 0.5 + 0.025), h * 0.52), (0.09, 0.06, h), CLAY)
    for i in range(bays):
        wx = cx - (w - 0.24) * 0.5 + (i + 0.5) * step
        if i in (1, 4):
            b.loading_dock(wx, 0.04 - d * 0.5, 0.02, out_xy=(0, -1), w=0.54, h=0.52, canopy_swatch=SLATE)
        else:
            b.window_unit(wx, 0.04 - d * 0.5, 0.68, (0, -1), 0.38, 0.52, frame_swatch=IRON, sill_swatch=STONE)
        b.window_unit(wx, 0.04 + d * 0.5, 0.68, (0, 1), 0.38, 0.52, frame_swatch=IRON, sill_swatch=STONE)

    # Двускатная крыша + продольный светоаэрационный фонарь (monitor roof)!
    b.gable_roof(cx, 0.04, h, w, d, 0.42, roof_swatch=SLATE, gable_swatch=BRICK, trim_swatch=STONE, overhang=0.08, axis="x")
    mw, md, mh = w * 0.78, 0.56, 0.36
    b.box((cx, 0.04, h + 0.32 + mh * 0.5), (mw, md, mh), SLATE)
    for sy in (-1, 1):
        b.box((cx, 0.04 + sy * (md * 0.5 + 0.01), h + 0.34 + mh * 0.5), (mw - 0.20, 0.025, mh * 0.68), GLASS_LITE)
    b.gable_roof(cx, 0.04, h + 0.32 + mh, mw, md, 0.18, roof_swatch=IRON, gable_swatch=BRICK, trim_swatch=STONE, overhang=0.05, axis="x")

    # Шихтовый бункер и две мощные дымовые трубы справа
    b.box((2.14, 0.02, 0.66), (0.92, 1.18, 1.32), GUNMETAL)
    b.smokestack(1.94, 0.38, 0.03, height=2.85, r_base=0.22, r_top=0.13, body_swatch=BRICK, stripe_swatch=STONE)
    b.smokestack(2.48, 0.38, 0.03, height=2.55, r_base=0.20, r_top=0.12, body_swatch=BRICK, stripe_swatch=STONE)
    _cyclone_separator(b, 2.22, -0.38, 1.32, scale=0.80)
    return b, 3, 1


# ---------------------------------------------------------------------------
# 8. Силосный элеватор / цементный терминал с конвейерным мостом 3×1 (I, ур. 2)
# ---------------------------------------------------------------------------
def build_ind_silo_elevator_3x1():
    clear_scene()
    b = ArchBuilder("ind_silo_elevator_3x1")
    b.pave_base(5.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Батарея из 4 высоких бетонно-алюминиевых силосных башен слева и в центре
    silo_h = 2.28
    silo_r = 0.44
    xs = [-2.12, -1.20, -0.28, 0.64]
    for sx in xs:
        b.cylinder((sx, 0.10, 0.03 + silo_h * 0.5), silo_r, silo_r, silo_h, STONE, segments=16)
        b.cylinder((sx, 0.10, 0.03 + silo_h + 0.10), silo_r * 1.02, silo_r * 0.62, 0.20, ALUM, segments=16)
    # Надсилосная конвейерная галерея с окнами
    gx = sum(xs) / len(xs)
    gw = (xs[-1] - xs[0]) + silo_r * 1.6
    gz = 0.03 + silo_h + 0.20
    b.box((gx, 0.10, gz + 0.20), (gw, 0.56, 0.40), WALL)
    b.box((gx, 0.10, gz + 0.42), (gw + 0.06, 0.62, 0.05), ROOF)
    b.window_grid_wall(gx, 0.10 - 0.28, gz, gw, 1, 0.38, (0, -1), win_w=0.28, win_h=0.20, step=0.52, start_floor=0, belt_swatch=None)

    # Приёмно-фасовочный корпус справа + наклонная галерея нории/конвейера!
    rx = 2.02
    b.box((rx, 0.04, 0.58), (1.36, 1.32, 1.16), CREAM)
    b.gable_roof(rx, 0.04, 1.16, 1.36, 1.32, 0.34, roof_swatch=ROOF, gable_swatch=CREAM, trim_swatch=STEEL, overhang=0.06, axis="x")
    b.loading_dock(rx - 0.24, 0.04 - 0.66, 0.02, out_xy=(0, -1), w=0.56, h=0.48, canopy_swatch=TERRACOTTA)
    b.entrance_canopy(rx + 0.36, 0.04 - 0.66, 0.03, w=0.34, h=0.36, canopy_d=0.16, canopy_swatch=ROOF)
    # Наклонный конвейер от фасовочного корпуса к верху силосов
    b.tilted_box((1.28, 0.10, 1.78), (1.58, 0.34, 0.30), ALUM, roll_y=0.58)
    return b, 3, 1


# ---------------------------------------------------------------------------
# 9. Машиностроительный конвейерный завод 4×1 (I, ур. 2)
# ---------------------------------------------------------------------------
def build_ind_assembly_plant_4x1():
    clear_scene()
    b = ArchBuilder("ind_assembly_plant_4x1")
    b.pave_base(7.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Двухэтажный АБК (административно-бытовой корпус) слева + длинный 5-зубчатый шедовый цех!
    b.box((-2.88, 0.02, 0.66), (1.56, 1.38, 1.32), CREAM)
    b.box((-2.88, 0.02, 1.35), (1.62, 1.44, 0.07), ROOF)
    b.entrance_canopy(-2.88, 0.02 - 0.69, 0.03, w=0.58, h=0.42, canopy_d=0.20, canopy_swatch=ROOF)
    b.curtain_wall_4sides(-2.88, 0.02, 0.56, 1.56, 1.38, 2, 0.38, mullion_step=0.38, frame_swatch=SLATE, spandrel_swatch=GUNMETAL, corner_pilasters=False)

    # Сборочный пролёт (ширина 5.4 м) с 5 шедовыми фонарями и цветной полосой бренда
    cw, cd, ch = 5.42, 1.36, 1.08
    cx = 0.82
    b.box((cx, 0.04, 0.18), (cw, cd, 0.36), GUNMETAL)
    b.box((cx, 0.04, 0.36 + (ch - 0.36) * 0.5), (cw, cd, ch - 0.36), WALL)
    b.box((cx, 0.04 - cd * 0.5 - 0.015, ch - 0.14), (cw + 0.02, 0.04, 0.16), ROOF)
    b.sawtooth_roof(cx, 0.04, ch, cw, cd, teeth=5, tooth_h=0.38, roof_swatch=ALUM, wall_swatch=WALL, axis="x")
    for dx in (-1.75, -0.35, 1.05):
        b.loading_dock(cx + dx, 0.04 - cd * 0.5, 0.02, out_xy=(0, -1), w=0.62, h=0.50, canopy_swatch=TERRACOTTA)
    b.window_grid_wall(cx + 2.15, 0.04 - cd * 0.5, 0.16, 0.96, 1, 0.72, (0, -1),
                       win_w=0.32, win_h=0.36, step=0.44, start_floor=0, frame_swatch=SLATE, belt_swatch=None)
    b.rooftop_hvac(-2.88, 0.06, 1.39, scale=0.88)
    return b, 4, 1


# ---------------------------------------------------------------------------
# 10. Логистический терминал с доками, контейнерами и краном 5×1 (I, ур. 3)
# ---------------------------------------------------------------------------
def build_ind_logistics_hub_5x1():
    clear_scene()
    b = ArchBuilder("ind_logistics_hub_5x1")
    b.pave_base(9.74, 1.76, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Кросс-док терминал слева/в центре (6.2 м) + контейнерный двор с козловым краном справа!
    hw, hd, hh = 6.18, 1.38, 1.18
    hx = -1.52
    b.box((hx, 0.08, 0.16), (hw, hd, 0.32), GUNMETAL)
    b.box((hx, 0.08, 0.32 + (hh - 0.32) * 0.5), (hw, hd, hh - 0.32), WALL)
    b.box((hx, 0.08, hh + 0.04), (hw + 0.10, hd + 0.10, 0.08), ROOF)
    # 5 погрузочных ворот с козырьками + угловой двухэтажный диспетчерский блок
    for i in range(5):
        lx = hx - 2.30 + i * 0.92
        b.loading_dock(lx, 0.08 - hd * 0.5, 0.02, out_xy=(0, -1), w=0.58, h=0.50, canopy_swatch=TERRACOTTA)
    ox = hx + 2.38
    b.box((ox, 0.04, 0.82), (1.36, 1.44, 1.64), SLATE)
    b.curtain_wall_4sides(ox, 0.04, 0.48, 1.36, 1.44, 2, 0.52, mullion_step=0.38, frame_swatch=ALUM, spandrel_swatch=CHARCOAL, corner_pilasters=False)
    b.entrance_canopy(ox, 0.04 - 0.72, 0.03, w=0.52, h=0.42, canopy_d=0.18, canopy_swatch=ROOF)
    b.box((ox, 0.04, 1.68), (1.44, 1.50, 0.07), ROOF)
    # Солнечные панели и световые люки на крыше склада
    b.solar_bank(hx - 1.10, 0.08, hh + 0.08, rows=2, cols=5, panel_w=0.44, panel_d=0.30)

    # Контейнерный двор справа с козловым краном и штабелями разноцветных контейнеров
    yx = 3.12
    b.gantry_crane(yx, 0.04, 0.03, span_x=2.48, length_y=1.36, height=1.78, swatch=TERRACOTTA)
    _shipping_container(b, yx - 0.54, 0.24, 0.03, TERRACOTTA, length=1.08)
    _shipping_container(b, yx - 0.54, 0.24, 0.47, ROOF, length=1.08)
    _shipping_container(b, yx + 0.62, 0.24, 0.03, GLASS_DARK, length=1.08)
    _shipping_container(b, yx + 0.04, -0.32, 0.03, SANDSTONE, length=1.08)
    return b, 5, 1


# ---------------------------------------------------------------------------
# 11. Тяжёлый металлургический/машиностроительный комбинат 7×1 (I, ур. 3)
# ---------------------------------------------------------------------------
def build_ind_heavy_works_7x1():
    clear_scene()
    b = ArchBuilder("ind_heavy_works_7x1")
    b.pave_base(13.74, 1.76, swatch=CONCRETE, border_swatch=GUNMETAL)

    # 1) Левый доменно-энергетический узел с печью, кауперами (воздухонагревателями) и трубами
    b.box((-5.35, 0.08, 0.20), (2.32, 1.40, 0.40), GUNMETAL)
    b.box((-5.35, 0.08, 0.86), (2.26, 1.34, 1.72), BRICK)
    b.gable_roof(-5.35, 0.08, 1.72, 2.26, 1.34, 0.38, roof_swatch=IRON, gable_swatch=BRICK, trim_swatch=STEEL, overhang=0.06, axis="x")
    for px in (-6.36, -5.35, -4.34):
        b.facade_box((-5.35 + (px + 5.35), 0.08 - 0.67, 0.88), (0.09, 0.05, 1.68), IRON, out_xy=(0, -1))
    for wx in (-5.86, -4.84):
        b.window_unit(wx, 0.08 - 0.67, 1.18, (0, -1), 0.42, 0.64, frame_swatch=IRON, sill_swatch=STONE)
    b.loading_dock(-5.86, 0.08 - 0.67, 0.02, out_xy=(0, -1), w=0.58, h=0.48, canopy_swatch=TERRACOTTA)
    # Три стальных купольных каупера и дымовая труба
    for i in range(3):
        kx = -3.68 + i * 0.54
        b.cylinder((kx, 0.24, 0.03 + 1.10), 0.22, 0.20, 2.20, CLAY, segments=12)
        b.cylinder((kx, 0.24, 0.03 + 2.28), 0.20, 0.06, 0.18, IRON, segments=12)
    b.smokestack(-6.18, 0.42, 0.03, height=3.25, r_base=0.24, r_top=0.14, body_swatch=BRICK, stripe_swatch=TERRACOTTA)

    # 2) Центральный прокатный цех (5.4 м) с 6-зубчатой шедовой крышей и погрузочными воротами
    mx = 0.08
    mw, md, mh = 5.36, 1.38, 1.26
    b.box((mx, 0.04, 0.20), (mw, md, 0.40), GUNMETAL)
    b.box((mx, 0.04, 0.40 + (mh - 0.40) * 0.5), (mw, md, mh - 0.40), SLATE)
    b.sawtooth_roof(mx, 0.04, mh, mw, md, teeth=6, tooth_h=0.38, roof_swatch=ALUM, wall_swatch=SLATE, axis="x")
    for dx in (-1.85, -0.60, 0.65, 1.90):
        b.loading_dock(mx + dx, 0.04 - md * 0.5, 0.02, out_xy=(0, -1), w=0.60, h=0.52, canopy_swatch=TERRACOTTA)
    _pipe_rack(b, -3.55, 0.34, -2.55, 0.34, 1.35, pipes=3, r=0.055, pipe_sw=STEEL)

    # 3) Правый открытый скраповый/отгрузочный двор с большим козловым краном, циклонами и второй трубой
    yx = 4.86
    b.gantry_crane(yx, 0.02, 0.03, span_x=3.18, length_y=1.38, height=1.96, swatch=TERRACOTTA)
    b.horizontal_tank(yx - 0.68, 0.28, 0.03, radius=0.28, length=1.32, swatch=ALUM, band_swatch=TERRACOTTA, axis="x")
    _cyclone_separator(b, yx + 0.72, 0.32, 0.03, scale=1.05)
    b.smokestack(6.28, 0.42, 0.03, height=2.95, r_base=0.22, r_top=0.13, body_swatch=CONCRETE, stripe_swatch=TERRACOTTA)
    return b, 7, 1


# ---------------------------------------------------------------------------
# 12. Нефтебаза / резервуарный парк с насосной станцией 2×2 (I, ур. 1)
# ---------------------------------------------------------------------------
def build_ind_tank_depot_2x2():
    clear_scene()
    b = ArchBuilder("ind_tank_depot_2x2")
    b.pave_base(3.74, 3.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Бетонное защитное каре обвалования вокруг резервуарного парка сзади
    for sx, sy, sw, sd in ((0, 1.66, 3.44, 0.10), (-1.67, 0.52, 0.10, 2.28), (1.67, 0.52, 0.10, 2.28), (0, -0.58, 3.44, 0.10)):
        b.box((sx, sy, 0.13), (sw, sd, 0.20), STONE)
    # Три цилиндрических резервуара с плавающими/конусными крышами и мостиком между ними
    tanks = [(-0.92, 0.72, 0.58, 1.38, WALL), (0.38, 0.84, 0.52, 1.56, ALUM), (1.18, -0.02, 0.38, 1.24, WALL)]
    for tx, ty, tr, th, sw in tanks:
        b.cylinder((tx, ty, 0.03 + th * 0.5), tr, tr, th, sw, segments=16)
        b.cylinder((tx, ty, 0.03 + th * 0.82), tr * 1.02, tr * 1.02, 0.08, TERRACOTTA, segments=16)
        b.cylinder((tx, ty, 0.03 + th + 0.08), tr * 1.02, tr * 0.15, 0.16, STEEL, segments=16)
    b.box((-0.26, 0.78, 0.03 + 1.44), (1.36, 0.16, 0.05), IRON)

    # Насосная станция и автоналивная эстакада спереди у улицы
    b.box((-0.92, -1.16, 0.44), (1.42, 0.82, 0.88), BRICK)
    b.gable_roof(-0.92, -1.16, 0.88, 1.42, 0.82, 0.24, roof_swatch=ROOF, gable_swatch=BRICK, trim_swatch=STONE, overhang=0.06, axis="x")
    b.entrance_canopy(-0.92, -1.16 - 0.41, 0.03, w=0.38, h=0.36, canopy_d=0.16, canopy_swatch=ROOF)
    # Навес наливной эстакады справа спереди
    b.box((0.78, -1.18, 0.86), (1.46, 0.76, 0.07), TERRACOTTA)
    for sx in (-0.52, 0.52):
        b.box((0.78 + sx, -1.18, 0.44), (0.08, 0.08, 0.84), STEEL)
    _pipe_rack(b, -0.92, -0.74, -0.92, 0.16, 0.62, pipes=2, r=0.045, pipe_sw=ALUM)
    _pipe_rack(b, -0.22, -1.16, 0.78, -1.16, 0.62, pipes=2, r=0.045, pipe_sw=STEEL)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 13. Микроэлектронная фабрика (Semiconductor Clean Fab) 2×2 (I, ур. 3)
# ---------------------------------------------------------------------------
def build_ind_clean_fab_2x2():
    clear_scene()
    b = ArchBuilder("ind_clean_fab_2x2")
    b.pave_base(3.74, 3.74, swatch=STONE, border_swatch=CONCRETE)
    # Герметичный корпус чистых комнат со скошенными гранями и внешними вентшахтами-колоннами!
    w, d, h = 2.96, 2.74, 1.56
    cy = 0.20
    b.chamfer_prism(0, cy, 0.03, w, d, 0.34, 0.26, GUNMETAL)
    b.chamfer_prism(0, cy, 0.37, w, d, h - 0.34, 0.26, WALL)
    b.chamfer_prism(0, cy, h + 0.03, w + 0.10, d + 0.10, 0.08, 0.26, ROOF)
    # Характерные внешние вертикальные воздуховоды чистых комнат по бокам (как у TSMC/Intel Fab!)
    for sx in (-1, 1):
        for dy in (-0.72, 0.0, 0.72):
            b.box((sx * (w * 0.5 + 0.09), cy + dy, h * 0.56), (0.18, 0.24, h * 0.96), ALUM)
            b.box((sx * (w * 0.5 + 0.09), cy + dy, h + 0.16), (0.20, 0.26, 0.22), STEEL)
    # Двухэтажная стеклянная входная группа на улице (−Y)
    b.box((0.0, cy - d * 0.5 - 0.22, 0.64), (1.76, 0.46, 1.28), SLATE)
    b.curtain_wall_4sides(0.0, cy - d * 0.5 - 0.22, 0.03, 1.76, 0.46, 2, 0.60, mullion_step=0.38,
                          frame_swatch=ALUM, spandrel_swatch=CHARCOAL, corner_pilasters=False)
    b.entrance_canopy(0.0, cy - d * 0.5 - 0.45, 0.03, w=0.62, h=0.44, canopy_d=0.20, canopy_swatch=ROOF)
    # Криогенные азотные танки слева спереди и мощное инженерное поле + солнечные батареи на крыше
    for kx in (-1.38, -1.04):
        b.cylinder((kx, -1.28, 0.03 + 0.58), 0.14, 0.14, 1.16, WALL, segments=12)
        b.cylinder((kx, -1.28, 0.03 + 1.20), 0.14, 0.04, 0.10, ALUM, segments=12)
    b.rooftop_hvac(-0.76, cy + 0.58, h + 0.11, scale=1.05)
    b.rooftop_hvac(0.76, cy + 0.58, h + 0.11, scale=1.05)
    b.solar_bank(0.0, cy - 0.42, h + 0.11, rows=2, cols=4, panel_w=0.44, panel_d=0.32)
    return b, 2, 2


# ---------------------------------------------------------------------------
# 14. Промышленный энергокомбинат с гиперболоидной градирней 3×2 (I, ур. 2)
# ---------------------------------------------------------------------------
def build_ind_thermo_plant_3x2():
    clear_scene()
    b = ArchBuilder("ind_thermo_plant_3x2")
    b.pave_base(5.76, 3.76, swatch=CONCRETE, border_swatch=GUNMETAL)

    # Гиперболоидная градирня слева — выразительный силуэт индустриального узла!
    b.hyperboloid_tower(-1.62, 0.18, 0.03, r_base=0.98, r_throat=0.62, r_top=0.72, height=2.95, swatch=STONE, rim_swatch=TERRACOTTA)

    # Машинный и турбинный зал справа (двухъярусный) со световым фонарём и полосатой трубой
    hx, hy = 1.12, 0.24
    hw, hd, hh = 2.96, 2.38, 1.54
    b.box((hx, hy, 0.20), (hw + 0.06, hd + 0.06, 0.40), GUNMETAL)
    b.box((hx, hy, 0.40 + (hh - 0.40) * 0.5), (hw, hd, hh - 0.40), CLAY)
    b.box((hx, hy, hh + 0.04), (hw + 0.10, hd + 0.10, 0.08), SLATE)
    # Вертикальное ленточное остекление турбинного зала
    for i in range(5):
        wx = hx - 1.08 + i * 0.54
        b.window_unit(wx, hy - hd * 0.5, 0.92, (0, -1), 0.30, 0.78, frame_swatch=IRON, sill_swatch=STONE)
        b.window_unit(wx, hy + hd * 0.5, 0.92, (0, 1), 0.30, 0.78, frame_swatch=IRON, sill_swatch=STONE)
    b.loading_dock(hx - 0.86, hy - hd * 0.5, 0.02, out_xy=(0, -1), w=0.62, h=0.52, canopy_swatch=TERRACOTTA)
    b.entrance_canopy(hx + 0.78, hy - hd * 0.5, 0.03, w=0.48, h=0.40, canopy_d=0.18, canopy_swatch=ROOF)
    # Световой фонарь на крыше зала и высокая дымовая труба сзади
    b.gable_roof(hx - 0.20, hy, hh + 0.08, 2.10, 0.82, 0.34, roof_swatch=ALUM, gable_swatch=CLAY, trim_swatch=STEEL, overhang=0.05, axis="x")
    b.smokestack(2.24, 1.18, 0.03, height=3.45, r_base=0.25, r_top=0.14, body_swatch=CONCRETE, stripe_swatch=TERRACOTTA)

    # Открытое распределительное устройство (трансформаторы) спереди слева и паропроводы к градирне
    _pipe_rack(b, -0.72, 0.22, -0.36, 0.22, 1.10, pipes=2, r=0.075, pipe_sw=ALUM)
    for tx in (-2.12, -1.28):
        b.box((tx, -1.28, 0.28), (0.52, 0.42, 0.50), GUNMETAL)
        for bx_i in (-0.14, 0.0, 0.14):
            b.cylinder((tx + bx_i, -1.28, 0.64), 0.04, 0.025, 0.24, COPPER, segments=8)
    return b, 3, 2


# ---------------------------------------------------------------------------
# 15. Нефтехимический комбинат с колоннами крекинга и эстакадами 3×2 (I, ур. 3)
# ---------------------------------------------------------------------------
def build_ind_refinery_complex_3x2():
    clear_scene()
    b = ArchBuilder("ind_refinery_complex_3x2")
    b.pave_base(5.76, 3.76, swatch=CONCRETE, border_swatch=GUNMETAL)

    # 1) Этажерка установки каталитического крекинга с 3 ректификационными колоннами в центре-слева
    fx, fy = -1.28, 0.38
    # Многоярусный стальной каркас этажерки
    for sx in (-0.78, 0.0, 0.78):
        for sy in (-0.64, 0.64):
            b.box((fx + sx, fy + sy, 1.05), (0.08, 0.08, 2.04), IRON)
    for z_deck in (0.68, 1.34, 1.98):
        b.box((fx, fy, z_deck), (1.72, 1.44, 0.06), TERRACOTTA if z_deck > 1.8 else STEEL)
    for cx_c, cy_c, hc, rc in ((fx - 0.44, fy, 3.05, 0.26), (fx + 0.36, fy + 0.22, 2.65, 0.22), (fx + 0.38, fy - 0.32, 2.15, 0.18)):
        b.cylinder((cx_c, cy_c, 0.03 + hc * 0.5), rc, rc * 0.90, hc, ALUM, segments=14)
        b.cylinder((cx_c, cy_c, 0.03 + hc * 0.78), rc + 0.06, rc + 0.06, 0.05, TERRACOTTA, segments=14)
    # Высокая тонкая факельная мачта на углу этажерки
    b.smokestack(fx - 0.96, fy + 0.78, 0.03, height=3.55, r_base=0.14, r_top=0.08, body_swatch=STEEL, stripe_swatch=TERRACOTTA)

    # 2) Резервуарный парк справа сзади (2 вертикальных бака + 2 горизонтальных буллита)
    for tx, ty, tr, th in ((1.22, 0.92, 0.56, 1.54), (2.26, 0.92, 0.44, 1.42)):
        b.cylinder((tx, ty, 0.03 + th * 0.5), tr, tr, th, WALL, segments=16)
        b.cylinder((tx, ty, 0.03 + th * 0.80), tr * 1.02, tr * 1.02, 0.08, ROOF, segments=16)
        b.cylinder((tx, ty, 0.03 + th + 0.08), tr * 1.02, tr * 0.16, 0.16, ALUM, segments=16)
    b.horizontal_tank(1.74, -0.18, 0.03, radius=0.28, length=1.64, swatch=ALUM, band_swatch=TERRACOTTA, axis="x")

    # 3) Операторно-лабораторный корпус спереди у улицы + двухъярусные эстакады труб
    ox, oy = -1.24, -1.16
    b.chamfer_prism(ox, oy, 0.03, 2.16, 0.92, 1.04, 0.16, WALL)
    b.chamfer_prism(ox, oy, 1.07, 2.24, 0.98, 0.07, 0.16, ROOF)
    b.chamfer_curtain_wall(ox, oy, 0.42, 2.16, 0.92, 0.16, 1, 0.52, mullion_step=0.40, frame_swatch=SLATE, spandrel_swatch=GUNMETAL)
    b.entrance_canopy(ox, oy - 0.46, 0.03, w=0.48, h=0.38, canopy_d=0.18, canopy_swatch=ROOF)
    b.loading_dock(1.74, -1.26, 0.02, out_xy=(0, -1), w=0.72, h=0.48, canopy_swatch=TERRACOTTA)
    b.box((1.74, -1.04, 0.36), (1.68, 0.54, 0.68), SLATE)

    _pipe_rack(b, -0.40, 0.38, 1.20, 0.38, 1.12, pipes=3, r=0.055, pipe_sw=ALUM)
    _pipe_rack(b, 0.40, 0.38, 0.40, -1.04, 0.86, pipes=2, r=0.05, pipe_sw=STEEL)
    return b, 3, 2


INDUSTRIAL_SPECS = [
    ("ind_brick_workshop_1x1", "Кирпичная мастерская с фонарём", "INDUSTRIAL", 1, build_ind_brick_workshop_1x1),
    ("ind_boiler_house_1x1", "Котельная с циклоном и трубой", "INDUSTRIAL", 2, build_ind_boiler_house_1x1),
    ("ind_precision_lab_1x1", "Чистый приборостроительный цех", "INDUSTRIAL", 3, build_ind_precision_lab_1x1),
    ("ind_sawtooth_mill_2x1", "Механический цех с шедовой крышей", "INDUSTRIAL", 1, build_ind_sawtooth_mill_2x1),
    ("ind_barrel_hangar_2x1", "Сдвоенный арочный ангар", "INDUSTRIAL", 2, build_ind_barrel_hangar_2x1),
    ("ind_chem_reactor_2x1", "Химреакторный узел с цистерной", "INDUSTRIAL", 3, build_ind_chem_reactor_2x1),
    ("ind_red_foundry_3x1", "Краснокирпичный литейный завод", "INDUSTRIAL", 2, build_ind_red_foundry_3x1),
    ("ind_silo_elevator_3x1", "Силосный элеватор с конвейером", "INDUSTRIAL", 2, build_ind_silo_elevator_3x1),
    ("ind_assembly_plant_4x1", "Конвейерный машиностроительный завод", "INDUSTRIAL", 2, build_ind_assembly_plant_4x1),
    ("ind_logistics_hub_5x1", "Логистический терминал с краном", "INDUSTRIAL", 3, build_ind_logistics_hub_5x1),
    ("ind_heavy_works_7x1", "Металлургический комбинат с домной", "INDUSTRIAL", 3, build_ind_heavy_works_7x1),
    ("ind_tank_depot_2x2", "Нефтебаза в обваловании", "INDUSTRIAL", 1, build_ind_tank_depot_2x2),
    ("ind_clean_fab_2x2", "Микроэлектронная фабрика (Clean Fab)", "INDUSTRIAL", 3, build_ind_clean_fab_2x2),
    ("ind_thermo_plant_3x2", "Энергокомбинат с градирней", "INDUSTRIAL", 2, build_ind_thermo_plant_3x2),
    ("ind_refinery_complex_3x2", "Нефтехимический комбинат крекинга", "INDUSTRIAL", 3, build_ind_refinery_complex_3x2),
]
