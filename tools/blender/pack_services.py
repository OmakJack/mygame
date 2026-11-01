"""Генераторы служебных зданий и анимированных ветрогенераторов (Blender 5.2, палитра Kenney).

Состав набора:
  Службы (статические меши 1×1 и 2×1, у служебных зданий zone == NONE → BuildingPalette не перекрашивает
  образец палитры, поэтому красный, полицейский синий, золотой и изумрудный цвета сохраняются один-в-один):
    1. police_station_1x1   — Полицейский участок 1×1 (щит со звездой, патрульная машина под навесом, мачта связи)
    2. police_precinct_2x1  — Полицейское управление 2×1 (колоннада, 2 гаражных бокса, 2 патрульные машины, гелипад)
    3. fire_station_1x1     — Пожарное депо 1×1 (остеклённые красные ворота, нос пожарной машины, каланча для рукавов)
    4. fire_depot_2x1       — Пожарная часть 2×1 (3 красных выездных бокса, пожарная машина с лестницей, каланча с сиреной)
    5. clinic_1x1           — Поликлиника 1×1 (белый корпус, 3D красные кресты, навес и карета скорой помощи)
    6. clinic_center_2x1    — Медицинский центр 2×1 (панорамный корпус, крытый бокс скорой помощи, гелипад, кислородная станция)

  Ветроэнергетика (составные сцены Base + Rotor с зацикленной glTF-анимацией вращения «spin-loop»):
    7. wind_turbine_hawt_1x1 — Классический трёхлопастной горизонтально-осевой ветряк (HAWT, 1×1)
    8. wind_turbine_vawt_1x1 — Спиральный вертикально-осевой ветрогенератор Дарье/Горлова (VAWT, 1×1)
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arch_kit import (  # noqa: E402
    ALUM,
    BRICK,
    CHARCOAL,
    CONCRETE,
    CREAM,
    GUNMETAL,
    IRON,
    SANDSTONE,
    SLATE,
    STEEL,
    STONE,
    WALL,
    ArchBuilder,
    clear_scene,
)

# Точные цвета строки 1 палитры Kenney (у служб и электростанций zone == NONE → custom.a == 0,
# поэтому BuildingPalette выводит их исходные цвета из colormap.png без замены оттенка):
EMERALD = (0, 1)     # свежий изумрудно-зелёный (газоны, эко-пояса ветряков, клумбы клиники)
GOLD = (1, 1)        # яркое золото / сигнальный жёлтый (звезда полиции, шевроны, фары)
ORANGE = (2, 1)      # сигнальный оранжевый (проблесковые маячки, сирены)
CRIMSON = (3, 1)     # насыщенный алый (ворота пожарного депо, красный крест, законцовки лопастей)
ROYAL_BLUE = (4, 1)  # глубокий полицейский синий / тёмный сапфир
SKY_BLUE = (5, 1)    # чистое голубое остекление / проблесковые балки


# ---------------------------------------------------------------------------
# Общие 3D-эмблемы, спецтранспорт и инженерные элементы
# ---------------------------------------------------------------------------

def _police_shield(b: ArchBuilder, x: float, y_wall: float, zc: float, scale: float = 1.0):
    """Объёмный полицейский щит с золотой звездой и крыльями на лицевом фасаде (−Y)."""
    s = scale
    # Тёмная подложка и синий восьмигранный щит
    b.facade_box((x, y_wall - 0.016, zc), (0.34 * s, 0.028, 0.38 * s), SLATE, (0, -1))
    b.facade_box((x, y_wall - 0.030, zc), (0.28 * s, 0.026, 0.32 * s), ROYAL_BLUE, (0, -1))
    # Боковые золотые «крылья» шеврона
    for sign in (-1, 1):
        b.facade_box((x + sign * 0.22 * s, y_wall - 0.022, zc + 0.02 * s), (0.14 * s, 0.022, 0.06 * s), GOLD, (0, -1))
        b.facade_box((x + sign * 0.19 * s, y_wall - 0.022, zc - 0.05 * s), (0.10 * s, 0.022, 0.045 * s), GOLD, (0, -1))
    # Золотая восьмилучевая звезда в центре щита (два скрещённых квадрата)
    b.facade_box((x, y_wall - 0.045, zc + 0.01 * s), (0.13 * s, 0.024, 0.13 * s), GOLD, (0, -1), grad=False)
    b.tilted_box((x, y_wall - 0.046, zc + 0.01 * s), (0.13 * s, 0.024, 0.13 * s), GOLD, roll_y=math.pi * 0.25, grad=False)
    b.facade_box((x, y_wall - 0.056, zc + 0.01 * s), (0.05 * s, 0.018, 0.05 * s), WALL, (0, -1), grad=False)


def _medical_cross(b: ArchBuilder, x: float, y: float, zc: float, out_xy=(0, -1), size: float = 0.38):
    """Рельефный медицинский красный крест на белом круглом медальоне."""
    ox, oy = out_xy
    along_x = abs(oy) > 0.5
    axis = "y" if along_x else "x"
    # Белый медальон с тонким серым кантом
    b.cylinder((x + ox * 0.015, y + oy * 0.015, zc), size * 0.58, size * 0.58, 0.026, SLATE, axis=axis, segments=14)
    b.cylinder((x + ox * 0.026, y + oy * 0.026, zc), size * 0.52, size * 0.52, 0.026, WALL, axis=axis, segments=14, grad=False)
    # Два перекрещенных алых бруса
    arm = size * 0.72
    thick = size * 0.24
    cx = x + ox * 0.042
    cy = y + oy * 0.042
    if along_x:
        b.facade_box((cx, cy, zc), (arm, 0.026, thick), CRIMSON, out_xy, grad=False)
        b.facade_box((cx, cy, zc), (thick, 0.026, arm), CRIMSON, out_xy, grad=False)
    else:
        b.facade_box((cx, cy, zc), (0.026, arm, thick), CRIMSON, out_xy, grad=False)
        b.facade_box((cx, cy, zc), (0.026, thick, arm), CRIMSON, out_xy, grad=False)


def _fire_emblem(b: ArchBuilder, x: float, y_wall: float, zc: float, scale: float = 1.0):
    """Рельефная пожарная эмблема (алый ромб + золотой мальтийский крест) на каланче/фасаде."""
    s = scale
    b.tilted_box((x, y_wall - 0.022, zc), (0.25 * s, 0.028, 0.25 * s), CRIMSON, roll_y=math.pi * 0.25, grad=False)
    b.facade_box((x, y_wall - 0.036, zc), (0.20 * s, 0.022, 0.075 * s), GOLD, (0, -1), grad=False)
    b.facade_box((x, y_wall - 0.036, zc), (0.075 * s, 0.022, 0.20 * s), GOLD, (0, -1), grad=False)
    b.facade_box((x, y_wall - 0.046, zc), (0.07 * s, 0.018, 0.07 * s), WALL, (0, -1), grad=False)


def _fire_bay_door(b: ArchBuilder, x: float, y_wall: float, z0: float, w: float = 0.62, h: float = 0.68):
    """Высокие секционные алые ворота пожарного бокса с панорамным остеклением и тумбами."""
    # Портал ворот
    b.facade_box((x, y_wall - 0.016, z0 + h * 0.5), (w + 0.08, 0.034, h + 0.04), SLATE, (0, -1))
    # 4 секции подъёмных ворот: нижняя и верхняя — алые, две средние — со смотровыми окнами
    sh = (h - 0.04) / 4.0
    for idx in range(4):
        sz = z0 + 0.02 + (idx + 0.5) * sh
        b.facade_box((x, y_wall - 0.028, sz), (w - 0.02, 0.024, sh * 0.88), CRIMSON, (0, -1))
        if idx in (1, 2):
            for px in (-w * 0.26, 0.0, w * 0.26):
                b.facade_quad(x + px, y_wall - 0.041, sz, (0, -1), w * 0.21, sh * 0.58, SKY_BLUE, grad=False)
    # Защитные жёлто-чёрные колесоотбойники по бокам выезда и сигнальная лампа сверху
    for sign in (-1, 1):
        bx = x + sign * (w * 0.5 + 0.055)
        b.box((bx, y_wall - 0.07, z0 + 0.08), (0.05, 0.05, 0.16), GOLD, skip_bottom=True)
        b.box((bx, y_wall - 0.07, z0 + 0.18), (0.052, 0.052, 0.05), IRON)
    b.box((x, y_wall - 0.045, z0 + h + 0.07), (0.10, 0.06, 0.06), ORANGE)


def _comms_mast(b: ArchBuilder, x: float, y: float, z0: float, h: float = 1.05):
    """Ажурная радиомачта экстренной связи с релейной тарелкой и маячком."""
    b.box((x, y, z0 + 0.04), (0.24, 0.24, 0.08), GUNMETAL, skip_bottom=True)
    # Четыре наклонные стойки решётчатой башни
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.tilted_box(
                (x + sx * 0.055, y + sy * 0.055, z0 + h * 0.38),
                (0.026, 0.026, h * 0.68),
                ALUM,
                pitch_x=sy * 0.09,
                roll_y=-sx * 0.09,
            )
    for frac in (0.22, 0.45, 0.66):
        w_ring = 0.16 * (1.0 - frac * 0.55)
        b.box((x, y, z0 + h * frac), (w_ring, w_ring, 0.024), STEEL)
    # Релейная барабанная антенна (смотрит на −Y) и шпиль с красным огнём
    b.cylinder((x, y - 0.09, z0 + h * 0.56), 0.11, 0.11, 0.06, WALL, axis="y", segments=12, grad=False)
    b.cylinder((x, y - 0.125, z0 + h * 0.56), 0.035, 0.035, 0.02, ROYAL_BLUE, axis="y", segments=10, grad=False)
    b.cylinder((x, y, z0 + h * 0.84), 0.018, 0.010, h * 0.36, ALUM, segments=8)
    b.box((x, y, z0 + h + 0.03), (0.048, 0.048, 0.048), CRIMSON, grad=False)


def _police_cruiser(b: ArchBuilder, cx: float, cy: float, z0: float):
    """Миниатюрный low-poly полицейский автомобиль (смотрит капотом на −Y к улице)."""
    # Колёса
    for sx in (-0.145, 0.145):
        for dy in (-0.19, 0.19):
            b.cylinder((cx + sx, cy + dy, z0 + 0.065), 0.065, 0.065, 0.055, IRON, axis="x", segments=10)
            b.cylinder((cx + sx * 1.06, cy + dy, z0 + 0.065), 0.032, 0.032, 0.058, ALUM, axis="x", segments=8)
    # Синий кузов с белыми дверями и крышей
    b.box((cx, cy, z0 + 0.115), (0.31, 0.64, 0.11), ROYAL_BLUE)
    b.box((cx, cy, z0 + 0.120), (0.316, 0.28, 0.105), WALL, grad=False)
    # Салон со скошенным лобовым стеклом
    b.chamfer_prism(cx, cy + 0.03, z0 + 0.17, 0.27, 0.34, 0.10, 0.05, WALL, grad=False)
    b.facade_quad(cx, cy - 0.142, z0 + 0.215, (0, -1), 0.22, 0.075, SKY_BLUE, grad=False)
    for sx in (-1, 1):
        b.facade_quad(cx + sx * 0.137, cy + 0.03, z0 + 0.215, (sx, 0), 0.22, 0.07, SKY_BLUE, grad=False)
    # Фары и красно-синяя люстра на крыше
    for sx in (-0.095, 0.095):
        b.facade_box((cx + sx, cy - 0.322, z0 + 0.115), (0.06, 0.018, 0.038), GOLD, (0, -1), grad=False)
    b.box((cx - 0.055, cy + 0.02, z0 + 0.285), (0.09, 0.048, 0.032), CRIMSON, grad=False)
    b.box((cx + 0.055, cy + 0.02, z0 + 0.285), (0.09, 0.048, 0.032), SKY_BLUE, grad=False)


def _fire_engine(b: ArchBuilder, cx: float, cy: float, z0: float, cab_only: bool = False):
    """Миниатюрная low-poly пожарная машина с хромированным бампером и лестницей (смотрит на −Y)."""
    if cab_only:
        # Выступающая из ворот кабина готового к выезду пожарного расчёта
        for sx in (-0.17, 0.17):
            b.cylinder((cx + sx, cy - 0.05, z0 + 0.075), 0.075, 0.075, 0.06, IRON, axis="x", segments=10)
        b.box((cx, cy, z0 + 0.20), (0.38, 0.34, 0.26), CRIMSON)
        b.box((cx, cy, z0 + 0.34), (0.37, 0.32, 0.05), WALL, grad=False)
        b.facade_box((cx, cy - 0.175, z0 + 0.09), (0.40, 0.04, 0.06), ALUM, (0, -1))
        b.facade_box((cx, cy - 0.172, z0 + 0.16), (0.22, 0.024, 0.07), ALUM, (0, -1))
        b.facade_quad(cx, cy - 0.172, z0 + 0.255, (0, -1), 0.31, 0.09, SKY_BLUE, grad=False)
        for sx in (-0.13, 0.13):
            b.facade_box((cx + sx, cy - 0.174, z0 + 0.155), (0.055, 0.02, 0.04), GOLD, (0, -1), grad=False)
        b.box((cx - 0.09, cy - 0.08, z0 + 0.38), (0.10, 0.05, 0.035), CRIMSON, grad=False)
        b.box((cx + 0.09, cy - 0.08, z0 + 0.38), (0.10, 0.05, 0.035), ORANGE, grad=False)
        return

    # Полноразмерный пожарный автомобиль с выдвижной лестницей на крыше
    for sx in (-0.175, 0.175):
        for dy in (-0.25, 0.22):
            b.cylinder((cx + sx, cy + dy, z0 + 0.075), 0.075, 0.075, 0.06, IRON, axis="x", segments=10)
            b.cylinder((cx + sx * 1.06, cy + dy, z0 + 0.075), 0.036, 0.036, 0.062, ALUM, axis="x", segments=8)
    b.box((cx, cy - 0.20, z0 + 0.21), (0.38, 0.32, 0.27), CRIMSON)
    b.box((cx, cy - 0.20, z0 + 0.355), (0.37, 0.30, 0.045), WALL, grad=False)
    b.box((cx, cy + 0.14, z0 + 0.20), (0.38, 0.40, 0.25), CRIMSON)
    # Серебристые шторки отсеков оборудования по бортам
    for sx in (-1, 1):
        b.facade_box((cx + sx * 0.192, cy + 0.14, z0 + 0.20), (0.02, 0.30, 0.16), ALUM, (sx, 0))
    b.facade_box((cx, cy - 0.365, z0 + 0.095), (0.40, 0.04, 0.06), ALUM, (0, -1))
    b.facade_box((cx, cy - 0.362, z0 + 0.165), (0.22, 0.024, 0.07), ALUM, (0, -1))
    b.facade_quad(cx, cy - 0.362, z0 + 0.26, (0, -1), 0.31, 0.09, SKY_BLUE, grad=False)
    for sx in (-0.13, 0.13):
        b.facade_box((cx + sx, cy - 0.364, z0 + 0.16), (0.055, 0.02, 0.04), GOLD, (0, -1), grad=False)
    # Алюминиевая пожарная лестница на крыше и проблесковая балка
    for sx in (-0.075, 0.075):
        b.box((cx + sx, cy + 0.05, z0 + 0.365), (0.026, 0.62, 0.03), ALUM)
    for ry in (-0.20, -0.08, 0.04, 0.16, 0.28):
        b.box((cx, cy + ry, z0 + 0.365), (0.15, 0.022, 0.022), ALUM)
    b.box((cx, cy - 0.28, z0 + 0.395), (0.24, 0.05, 0.035), ORANGE, grad=False)


def _ambulance_van(b: ArchBuilder, cx: float, cy: float, z0: float):
    """Миниатюрная low-poly машина скорой помощи (белый кузов с алой полосой и маячками)."""
    for sx in (-0.155, 0.155):
        for dy in (-0.20, 0.20):
            b.cylinder((cx + sx, cy + dy, z0 + 0.068), 0.068, 0.068, 0.055, IRON, axis="x", segments=10)
    # Белый медицинский фургон и кабина
    b.box((cx, cy + 0.07, z0 + 0.205), (0.34, 0.46, 0.25), WALL, grad=False)
    b.box((cx, cy - 0.22, z0 + 0.165), (0.32, 0.16, 0.17), WALL, grad=False)
    # Алая сигнальная полоса по периметру
    b.box((cx, cy + 0.07, z0 + 0.155), (0.348, 0.465, 0.055), CRIMSON, grad=False)
    b.facade_quad(cx, cy - 0.162, z0 + 0.255, (0, -1), 0.27, 0.08, SKY_BLUE, grad=False)
    for sx in (-0.10, 0.10):
        b.facade_box((cx + sx, cy - 0.302, z0 + 0.125), (0.055, 0.018, 0.038), GOLD, (0, -1), grad=False)
    b.box((cx - 0.07, cy - 0.11, z0 + 0.345), (0.09, 0.048, 0.034), CRIMSON, grad=False)
    b.box((cx + 0.07, cy - 0.11, z0 + 0.345), (0.09, 0.048, 0.034), SKY_BLUE, grad=False)


# ---------------------------------------------------------------------------
# 1. Полицейский участок 1×1 (service_police_1x1)
# ---------------------------------------------------------------------------

def build_police_station_1x1():
    clear_scene()
    b = ArchBuilder("police_station_1x1")
    b.pave_base(1.74, 1.74, swatch=STONE, border_swatch=GUNMETAL)
    # Асфальтовый карман справа для патрульной машины и зелёная клумба слева у входа
    b.box((0.50, -0.14, 0.034), (0.64, 1.38, 0.016), SLATE, skip_bottom=True)
    b.box((-0.64, -0.68, 0.06), (0.32, 0.22, 0.07), STONE, skip_bottom=True)
    b.box((-0.64, -0.68, 0.105), (0.26, 0.16, 0.04), EMERALD, skip_bottom=True)

    # Основной двухэтажный корпус участка со строгим сине-белым фасадом
    cx, cy = -0.22, 0.08
    w, d, h = 1.16, 1.28, 1.38
    b.box((cx, cy, 0.18), (w + 0.04, d + 0.04, 0.36), GUNMETAL, skip_bottom=True)
    b.box((cx, cy, 0.36 + (h - 0.36) * 0.5), (w, d, h - 0.36), WALL, skip_bottom=True)
    # Фирменный полицейский синий фриз под карнизом + повышенный центральный аттик под щит со звездой
    b.box((cx, cy, h + 0.07), (w + 0.06, d + 0.06, 0.14), ROYAL_BLUE)
    b.box((cx, cy, h + 0.165), (w + 0.10, d + 0.10, 0.05), STONE)
    y_front = cy - d * 0.5
    b.box((cx, y_front - 0.01, h + 0.14), (0.58, 0.14, 0.30), ROYAL_BLUE)
    b.box((cx, y_front - 0.015, h + 0.30), (0.62, 0.16, 0.045), STONE)
    _police_shield(b, cx, y_front - 0.06, h + 0.13, scale=0.76)

    # Угловой стеклянный пилон дежурной части и окна второго этажа
    b.curtain_wall_4sides(cx, cy, 0.74, w, d, 1, 0.52, mullion_step=0.34,
                          frame_swatch=ALUM, spandrel_swatch=SLATE, corner_pilasters=True, pilaster_swatch=WALL)
    # Входной портал с синим козырьком и проблесковыми маячками
    b.entrance_canopy(cx, y_front, 0.03, w=0.50, h=0.42, canopy_d=0.22, canopy_swatch=ROYAL_BLUE)
    for sx in (-0.26, 0.26):
        b.box((cx + sx, y_front - 0.20, 0.545), (0.055, 0.055, 0.036), SKY_BLUE, grad=False)

    # Боковой навес автопарка и патрульная машина на выезде
    b.box((0.50, 0.06, 0.64), (0.62, 0.88, 0.06), ROYAL_BLUE)
    b.box((0.77, 0.06, 0.32), (0.07, 0.78, 0.62), SLATE, skip_bottom=True)
    _police_cruiser(b, 0.50, -0.22, 0.04)

    # Ажурная радиомачта диспетчерской и вентиляция на крыше (сбоку, чтобы центр крыши оставался чистым)
    _comms_mast(b, cx - 0.30, cy + 0.28, h + 0.19, h=0.98)
    b.rooftop_hvac(cx + 0.26, cy + 0.26, h + 0.19, scale=0.68)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 2. Полицейское управление 2×1 (service_police_2x1)
# ---------------------------------------------------------------------------

def build_police_precinct_2x1():
    clear_scene()
    b = ArchBuilder("police_precinct_2x1")
    b.pave_base(3.74, 1.76, swatch=STONE, border_swatch=GUNMETAL)
    # Широкий асфальтовый двор спецтранспорта справа + газоны у парадного крыльца
    b.box((1.08, -0.06, 0.034), (1.42, 1.50, 0.016), SLATE, skip_bottom=True)
    for gx in (-1.56, 0.04):
        b.box((gx, -0.68, 0.06), (0.34, 0.22, 0.07), STONE, skip_bottom=True)
        b.box((gx, -0.68, 0.105), (0.28, 0.16, 0.04), EMERALD, skip_bottom=True)

    # Главный 3-этажный административно-командный корпус слева/в центре
    mx, my = -0.76, 0.08
    mw, md, mh = 2.08, 1.32, 1.88
    b.chamfer_prism(mx, my, 0.03, mw + 0.04, md + 0.04, 0.38, 0.18, GUNMETAL)
    b.chamfer_prism(mx, my, 0.41, mw, md, mh - 0.38, 0.18, WALL)
    b.chamfer_prism(mx, my, mh + 0.03, mw + 0.06, md + 0.06, 0.15, 0.18, ROYAL_BLUE)
    b.chamfer_prism(mx, my, mh + 0.18, mw + 0.10, md + 0.10, 0.05, 0.18, STONE)
    b.chamfer_curtain_wall(mx, my, 0.48, mw, md, 0.18, 2, 0.64, mullion_step=0.38,
                           frame_swatch=ALUM, spandrel_swatch=SLATE)

    # Выступающий парадный портик с колоннами, синим козырьком и крупным полицейским щитом со звездой
    yf = my - md * 0.5
    b.box((mx, yf - 0.08, 0.52), (0.86, 0.18, 0.98), ROYAL_BLUE, skip_bottom=True)
    for sx in (-0.34, 0.34):
        b.box((mx + sx, yf - 0.16, 0.48), (0.09, 0.09, 0.90), STONE, skip_bottom=True)
    b.entrance_canopy(mx, yf - 0.16, 0.03, w=0.52, h=0.44, canopy_d=0.22, canopy_swatch=ROYAL_BLUE)
    _police_shield(b, mx, yf - 0.17, 0.78, scale=0.88)

    # Крытый гаражный блок перехватчиков справа на 2 выездных бокса + шлагбаум и 2 патрульные машины
    gx_c, gy_c = 1.06, 0.24
    gw, gd, gh = 1.38, 0.98, 1.02
    b.box((gx_c, gy_c, gh * 0.5 + 0.03), (gw, gd, gh), SLATE, skip_bottom=True)
    b.box((gx_c, gy_c, gh + 0.07), (gw + 0.06, gd + 0.08, 0.09), ROYAL_BLUE)
    for bx in (gx_c - 0.34, gx_c + 0.34):
        b.facade_box((bx, gy_c - gd * 0.5 - 0.015, 0.38), (0.50, 0.03, 0.58), ALUM, (0, -1))
        b.facade_quad(bx, gy_c - gd * 0.5 - 0.032, 0.48, (0, -1), 0.40, 0.16, SKY_BLUE, grad=False)
    _police_cruiser(b, gx_c - 0.34, -0.44, 0.04)
    _police_cruiser(b, gx_c + 0.36, -0.36, 0.04)

    # Вертолётная площадка и радиомачта координационного центра на крыше
    b.helipad(mx + 0.42, my + 0.02, mh + 0.23, size=0.92)
    _comms_mast(b, mx - 0.64, my + 0.24, mh + 0.23, h=1.06)
    b.rooftop_hvac(gx_c, gy_c + 0.12, gh + 0.12, scale=0.78)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 3. Пожарное депо 1×1 (service_fire_1x1)
# ---------------------------------------------------------------------------

def build_fire_station_1x1():
    clear_scene()
    b = ArchBuilder("fire_station_1x1")
    b.pave_base(1.74, 1.74, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Асфальтовый выездной пандус с жёлтой разметкой перед воротами бокса
    b.box((-0.18, -0.58, 0.034), (1.02, 0.52, 0.016), SLATE, skip_bottom=True)
    for sx in (-0.42, 0.06):
        b.box((sx, -0.78, 0.044), (0.28, 0.05, 0.01), GOLD, grad=False)

    # Главный кирпичный гараж-бокс пожарной машины с алым карнизом и высоким остеклённым проёмом
    hx, hy = -0.18, 0.12
    hw, hd, hh = 1.14, 1.24, 1.34
    b.box((hx, hy, 0.16), (hw + 0.04, hd + 0.04, 0.32), GUNMETAL, skip_bottom=True)
    b.box((hx, hy, 0.32 + (hh - 0.32) * 0.5), (hw, hd, hh - 0.32), BRICK, skip_bottom=True)
    b.box((hx, hy, hh + 0.06), (hw + 0.08, hd + 0.08, 0.12), CRIMSON)
    b.box((hx, hy, hh + 0.145), (hw + 0.12, hd + 0.12, 0.05), STONE)

    yf = hy - hd * 0.5
    _fire_bay_door(b, hx, yf, 0.03, w=0.72, h=0.78)
    # Нос готовой к выезду пожарной машины у открытой рампы и широкий козырёк
    b.box((hx, yf - 0.13, 0.94), (0.92, 0.24, 0.05), CRIMSON)
    _fire_engine(b, hx, yf - 0.16, 0.04, cab_only=True)
    # Боковые окна караульного помещения на 2-м ярусе
    for dy in (-0.28, 0.28):
        b.window_unit(hx - hw * 0.5, hy + dy, 0.98, (-1, 0), 0.28, 0.34, frame_swatch=STONE, sill_swatch=STONE)

    # Узнаваемая высокая пожарная каланча (башня сушки рукавов + сирена) в правом углу!
    tx, ty = 0.54, 0.22
    tw, td, th = 0.52, 0.56, 2.58
    b.box((tx, ty, 0.20), (tw + 0.04, td + 0.04, 0.40), GUNMETAL, skip_bottom=True)
    b.box((tx, ty, 0.40 + (th - 0.40) * 0.5), (tw, td, th - 0.40), BRICK, skip_bottom=True)
    # Белые угловые пилястры, жалюзи сушки рукавов, смотровая площадка и шатровая алая крыша со шпилем-сиреной
    for z_win in (0.95, 1.55, 2.12):
        b.window_unit(tx, ty - td * 0.5, z_win, (0, -1), 0.20, 0.30, frame_swatch=STONE, sill_swatch=STONE)
        b.window_unit(tx + tw * 0.5, ty, z_win, (1, 0), 0.20, 0.30, frame_swatch=STONE, sill_swatch=STONE)
    _fire_emblem(b, tx, ty - td * 0.5, 0.52, scale=0.82)
    b.entrance_canopy(tx, ty - td * 0.5, 0.03, w=0.30, h=0.34, canopy_d=0.14, canopy_swatch=CRIMSON)
    b.hip_roof(tx, ty, th, tw + 0.04, td + 0.04, 0.28, roof_swatch=CRIMSON, fascia_swatch=STONE, overhang=0.06, ridge_frac=0.0)
    # Сирена гражданской обороны на маковке каланчи
    b.cylinder((tx, ty, th + 0.44), 0.025, 0.02, 0.24, ALUM, segments=8)
    b.cylinder((tx, ty, th + 0.58), 0.09, 0.05, 0.08, ORANGE, segments=10, grad=False)

    b.rooftop_hvac(hx - 0.18, hy + 0.24, hh + 0.17, scale=0.70)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 4. Пожарная часть 2×1 (service_fire_2x1)
# ---------------------------------------------------------------------------

def build_fire_depot_2x1():
    clear_scene()
    b = ArchBuilder("fire_depot_2x1")
    b.pave_base(3.74, 1.76, swatch=CONCRETE, border_swatch=GUNMETAL)
    # Широкая выездная площадка на 3 пожарных расчёта
    b.box((-0.52, -0.58, 0.034), (2.28, 0.54, 0.016), SLATE, skip_bottom=True)
    for bx in (-1.26, -0.52, 0.22):
        b.box((bx, -0.80, 0.044), (0.44, 0.05, 0.01), GOLD, grad=False)

    # 1) Просторный 3-боксовый машинный зал слева/в центре с алыми остеклёнными воротами и зенитным фонарём
    hx, hy = -0.52, 0.16
    hw, hd, hh = 2.28, 1.18, 1.36
    b.box((hx, hy, 0.16), (hw + 0.04, hd + 0.04, 0.32), GUNMETAL, skip_bottom=True)
    b.box((hx, hy, 0.32 + (hh - 0.32) * 0.5), (hw, hd, hh - 0.32), BRICK, skip_bottom=True)
    b.box((hx, hy, hh + 0.065), (hw + 0.08, hd + 0.08, 0.13), CRIMSON)
    b.box((hx, hy, hh + 0.155), (hw + 0.12, hd + 0.12, 0.05), STONE)

    yf = hy - hd * 0.5
    for bx in (-1.26, -0.52, 0.22):
        _fire_bay_door(b, bx, yf, 0.03, w=0.58, h=0.76)
    b.box((hx, yf - 0.12, 0.92), (hw - 0.06, 0.22, 0.045), CRIMSON)
    # Пожарный автомобиль с лестницей, выезжающий из центрального бокса на площадку!
    _fire_engine(b, -0.52, -0.44, 0.04, cab_only=False)

    # Солнечные батареи и световой фонарь на крыше машинного зала
    b.solar_bank(hx - 0.42, hy + 0.12, hh + 0.18, rows=1, cols=3, panel_w=0.38, panel_d=0.28)
    b.rooftop_hvac(hx + 0.68, hy + 0.16, hh + 0.18, scale=0.78)

    # 2) Двухэтажный дежурно-диспетчерский корпус справа + высокая тренировочная/рукавная каланча
    qx, qy = 1.16, 0.04
    qw, qd, qh = 1.06, 1.32, 1.66
    b.box((qx, qy, 0.16), (qw + 0.04, qd + 0.04, 0.32), GUNMETAL, skip_bottom=True)
    b.box((qx, qy, 0.32 + (qh - 0.32) * 0.5), (qw, qd, qh - 0.32), CREAM, skip_bottom=True)
    b.box((qx, qy, qh + 0.05), (qw + 0.08, qd + 0.08, 0.10), CRIMSON)
    b.box_windows_4sides(qx, qy, 0.46, qw, qd, 2, 0.56, win_w=0.24, win_h=0.28, step=0.40, start_floor=0,
                         frame_swatch=SLATE, sill_swatch=STONE, belt_swatch=STONE)
    b.entrance_canopy(qx - 0.06, qy - qd * 0.5, 0.03, w=0.44, h=0.40, canopy_d=0.20, canopy_swatch=CRIMSON)

    # Башня-каланча на стыке зала и караульного корпуса
    tx, ty, th = 0.82, 0.40, 2.96
    b.box((tx, ty, th * 0.5 + 0.03), (0.58, 0.58, th), BRICK, skip_bottom=True)
    for z_w in (1.92, 2.48):
        b.window_unit(tx, ty - 0.29, z_w, (0, -1), 0.22, 0.30, frame_swatch=STONE, sill_swatch=STONE)
        b.window_unit(tx + 0.29, ty, z_w, (1, 0), 0.22, 0.30, frame_swatch=STONE, sill_swatch=STONE)
    _fire_emblem(b, qx + 0.26, qy - qd * 0.5, 0.50, scale=0.84)
    b.hip_roof(tx, ty, th + 0.03, 0.62, 0.62, 0.30, roof_swatch=CRIMSON, fascia_swatch=STONE, overhang=0.06, ridge_frac=0.0)
    b.cylinder((tx, ty, th + 0.50), 0.025, 0.02, 0.28, ALUM, segments=8)
    b.cylinder((tx, ty, th + 0.66), 0.095, 0.05, 0.08, ORANGE, segments=10, grad=False)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 5. Поликлиника 1×1 (service_clinic_1x1)
# ---------------------------------------------------------------------------

def build_clinic_1x1():
    clear_scene()
    b = ArchBuilder("clinic_1x1")
    b.pave_base(1.74, 1.74, swatch=STONE, border_swatch=CONCRETE)
    # Изумрудная аллея-клумба слева и карман приёмного покоя скорой помощи справа
    b.box((-0.68, -0.10, 0.055), (0.24, 1.24, 0.06), STONE, skip_bottom=True)
    b.box((-0.68, -0.10, 0.095), (0.18, 1.16, 0.035), EMERALD, skip_bottom=True)
    b.box((0.50, -0.16, 0.034), (0.62, 1.32, 0.016), SLATE, skip_bottom=True)

    # Светлый белоснежный 2-этажный медицинский корпус со скошенными углами и панорамным остеклением
    cx, cy = -0.14, 0.10
    w, d, h = 1.14, 1.26, 1.44
    b.chamfer_prism(cx, cy, 0.03, w + 0.04, d + 0.04, 0.30, 0.16, CONCRETE)
    b.chamfer_prism(cx, cy, 0.33, w, d, h - 0.30, 0.16, WALL)
    b.chamfer_prism(cx, cy, h + 0.03, w + 0.06, d + 0.06, 0.08, 0.16, CRIMSON)
    b.chamfer_prism(cx, cy, h + 0.11, w + 0.08, d + 0.08, 0.04, 0.16, WALL)
    b.chamfer_curtain_wall(cx, cy, 0.44, w, d, 0.16, 2, 0.46, mullion_step=0.34,
                           frame_swatch=ALUM, spandrel_swatch=WALL)

    # Угловой белый пилон-башенка с двумя крупными 3D красными крестами (выступает вперёд и влево от парапета)
    px, py, ph = cx - 0.35, cy - 0.40, 2.08
    b.box((px, py, ph * 0.5 + 0.03), (0.48, 0.50, ph), WALL, skip_bottom=True)
    b.box((px, py, ph + 0.06), (0.52, 0.54, 0.07), CRIMSON)
    _medical_cross(b, px, py - 0.25, 1.78, out_xy=(0, -1), size=0.36)
    _medical_cross(b, px - 0.24, py, 1.78, out_xy=(-1, 0), size=0.34)

    # Главный вход поликлиники с бело-красным козырьком + крытый навес и карета скорой помощи справа
    b.entrance_canopy(cx + 0.18, cy - d * 0.5, 0.03, w=0.46, h=0.40, canopy_d=0.22, canopy_swatch=CRIMSON)
    b.box((0.50, 0.04, 0.68), (0.62, 0.88, 0.06), WALL)
    b.box((0.50, -0.39, 0.715), (0.64, 0.06, 0.05), CRIMSON)
    b.box((0.77, 0.04, 0.34), (0.06, 0.76, 0.64), ALUM, skip_bottom=True)
    _ambulance_van(b, 0.50, -0.20, 0.04)

    # Чистый медицинский блок фильтрации воздуха и солнечная панель на крыше
    b.rooftop_hvac(cx + 0.22, cy + 0.26, h + 0.15, scale=0.72)
    b.solar_bank(cx + 0.20, cy - 0.12, h + 0.15, rows=1, cols=2, panel_w=0.30, panel_d=0.24)
    return b, 1, 1


# ---------------------------------------------------------------------------
# 6. Медицинский центр / Поликлиника 2×1 (service_clinic_2x1)
# ---------------------------------------------------------------------------

def build_clinic_center_2x1():
    clear_scene()
    b = ArchBuilder("clinic_center_2x1")
    b.pave_base(3.74, 1.76, swatch=STONE, border_swatch=CONCRETE)
    # Озеленённый сквер выздоровления слева у входа и сквозной проезд скорой помощи справа
    for gx in (-1.56, -0.08):
        b.box((gx, -0.66, 0.06), (0.38, 0.24, 0.07), STONE, skip_bottom=True)
        b.box((gx, -0.66, 0.105), (0.32, 0.18, 0.04), EMERALD, skip_bottom=True)
    b.box((1.08, -0.06, 0.034), (1.36, 1.48, 0.016), SLATE, skip_bottom=True)

    # 1) Главный 3-этажный лечебно-диагностический корпус со светлым витражным фасадом
    mx, my = -0.78, 0.10
    mw, md, mh = 2.06, 1.30, 1.86
    b.chamfer_prism(mx, my, 0.03, mw + 0.04, md + 0.04, 0.32, 0.20, CONCRETE)
    b.chamfer_prism(mx, my, 0.35, mw, md, mh - 0.32, 0.20, WALL)
    b.chamfer_prism(mx, my, mh + 0.03, mw + 0.06, md + 0.06, 0.09, 0.20, CRIMSON)
    b.chamfer_prism(mx, my, mh + 0.12, mw + 0.08, md + 0.08, 0.05, 0.20, WALL)
    b.chamfer_curtain_wall(mx, my, 0.42, mw, md, 0.20, 2, 0.64, mullion_step=0.36,
                           frame_swatch=ALUM, spandrel_swatch=WALL)

    # Поднятая угловая башня с рельефными красными крестами на двух фасадах (выступает за линию карниза!)
    tx, ty, th = mx - 0.72, my - 0.39, 2.52
    b.box((tx, ty, th * 0.5 + 0.03), (0.58, 0.58, th), WALL, skip_bottom=True)
    b.box((tx, ty, th + 0.065), (0.62, 0.62, 0.08), CRIMSON)
    _medical_cross(b, tx, ty - 0.29, 2.18, out_xy=(0, -1), size=0.42)
    _medical_cross(b, tx - 0.29, ty, 2.18, out_xy=(-1, 0), size=0.40)

    b.entrance_canopy(mx + 0.14, my - md * 0.5, 0.03, w=0.58, h=0.44, canopy_d=0.24, canopy_swatch=CRIMSON)

    # 2) Приёмное отделение скорой помощи справа с навесом-порталом, каретой скорой и криотанками кислорода
    ex, ey = 0.86, 0.24
    ew, ed, eh = 1.18, 0.96, 1.12
    b.box((ex, ey, eh * 0.5 + 0.03), (ew, ed, eh), WALL, skip_bottom=True)
    b.box((ex, ey, eh + 0.06), (ew + 0.06, ed + 0.06, 0.08), CRIMSON)
    b.curtain_wall_4sides(ex, ey, 0.34, ew, ed, 1, 0.62, mullion_step=0.36,
                          frame_swatch=ALUM, spandrel_swatch=WALL, corner_pilasters=False)
    # Широкий портал-навес для заезда реанимобилей
    b.box((1.06, -0.36, 0.74), (1.26, 0.64, 0.07), WALL)
    b.box((1.06, -0.66, 0.785), (1.28, 0.06, 0.06), CRIMSON)
    for sx in (0.50, 1.62):
        b.box((sx, -0.60, 0.38), (0.08, 0.08, 0.72), ALUM, skip_bottom=True)
    _ambulance_van(b, 1.06, -0.38, 0.04)

    # Два белых криогенных резервуара медицинского кислорода справа сзади
    for ox_t in (1.56, 1.74):
        b.cylinder((ox_t, 0.44, 0.48), 0.075, 0.075, 0.88, WALL, segments=10, grad=False)
        b.cylinder((ox_t, 0.44, 0.94), 0.075, 0.02, 0.07, ALUM, segments=10)

    # Санитарная вертолётная площадка и чиллеры на крыше главного корпуса
    b.helipad(mx + 0.42, my + 0.04, mh + 0.17, size=0.92)
    b.rooftop_hvac(ex - 0.10, ey + 0.10, eh + 0.10, scale=0.78)
    return b, 2, 1


# ---------------------------------------------------------------------------
# 7. Горизонтально-осевой ветряк 1×1 с вращающимся ротором (wind_turbine_hawt_1x1)
# ---------------------------------------------------------------------------

HAWT_HUB_BLENDER = (0.0, -0.44, 3.38)


def build_wind_hawt_1x1():
    """Возвращает (base_builder, rotor_builder, anim_spec) для классического трёхлопастного ветряка."""
    clear_scene()
    base = ArchBuilder("Base")
    # Симметричное основание 1.74 × 1.74 м с Z_min = 0.0 — ModelLoader не сдвигает центр и не меняет масштаб!
    base.box((0.0, 0.0, 0.015), (1.74, 1.74, 0.03), CONCRETE)
    base.box((0.0, 0.0, 0.034), (1.60, 1.60, 0.016), EMERALD, skip_bottom=True)
    # Восьмигранный железобетонный пьедестал и стальной анкерный фланец башни
    base.chamfer_prism(0.0, 0.0, 0.03, 1.04, 1.04, 0.14, 0.26, STONE)
    base.cylinder((0.0, 0.0, 0.21), 0.31, 0.28, 0.08, GUNMETAL, segments=16)
    # Сервисная дверь и лесенка со стороны улицы (−Y) + трансформаторная подстанция сзади справа
    base.box((0.0, -0.34, 0.09), (0.28, 0.18, 0.06), STONE, skip_bottom=True)
    base.facade_box((0.0, -0.25, 0.38), (0.18, 0.04, 0.34), SLATE, (0, -1))
    base.facade_box((0.0, -0.27, 0.38), (0.13, 0.02, 0.29), ALUM, (0, -1))

    # Компактный повышающий трансформаторный шкаф и инвертор на площадке сзади
    base.box((0.46, 0.44, 0.24), (0.42, 0.34, 0.42), ALUM, skip_bottom=True)
    base.box((0.46, 0.44, 0.465), (0.46, 0.38, 0.04), SLATE)
    base.facade_box((0.46, 0.265, 0.28), (0.10, 0.02, 0.10), GOLD, (0, -1), grad=False)
    for rz in (0.18, 0.28):
        base.facade_box((0.245, 0.44, rz), (0.02, 0.20, 0.04), GUNMETAL, (-1, 0))

    # Стройная коническая стальная мачта (высота до гондолы 3.24 м) с фланцевыми кольцами и сигнальной полосой
    base.cylinder((0.0, 0.0, 1.74), 0.245, 0.135, 3.00, WALL, segments=16)
    for z_flange, r_fl in ((1.18, 0.212), (2.18, 0.178)):
        base.cylinder((0.0, 0.0, z_flange), r_fl, r_fl, 0.04, ALUM, segments=16)
    base.cylinder((0.0, 0.0, 2.94), 0.152, 0.146, 0.18, CRIMSON, segments=16, grad=False)
    # Поворотный подшипник (yaw ring) под гондолой
    base.cylinder((0.0, 0.0, 3.25), 0.16, 0.16, 0.06, GUNMETAL, segments=16)

    # Обтекаемая гондола генератора (nacelle) с радиатором охлаждения, анемометром и красным маяком
    _, hy, hz = HAWT_HUB_BLENDER
    # Переднее кольцо гондолы заканчивается на y = -0.355 (зазор 1.5 см до вращающегося кока ротора)
    base.cylinder((0.0, -0.30, hz), 0.155, 0.175, 0.11, ALUM, axis="y", segments=16)
    base.chamfer_prism(0.0, 0.08, hz - 0.18, 0.38, 0.68, 0.36, 0.09, WALL)
    base.chamfer_prism(0.0, 0.44, hz - 0.15, 0.32, 0.16, 0.30, 0.08, ALUM)
    # Боковая зелёная эко-полоса на гондоле
    for sx in (-1, 1):
        base.facade_box((sx * 0.192, 0.08, hz), (0.018, 0.44, 0.065), EMERALD, (sx, 0), grad=False)
    # Анемометр и заградительный авиационный огонь на корме гондолы
    base.cylinder((0.0, 0.34, hz + 0.24), 0.016, 0.012, 0.14, STEEL, segments=8)
    base.box((0.0, 0.34, hz + 0.33), (0.055, 0.055, 0.05), CRIMSON, grad=False)

    # --- Вращающийся ротор (локальный (0, 0, 0) = центр втулки HAWT_HUB_BLENDER) ---
    rotor = ArchBuilder("Rotor")
    # Обтекаемый кок-обтекатель (spinner) вдоль оси Y (вперёд на −Y)
    rotor.cylinder((0.0, 0.058, 0.0), 0.140, 0.148, 0.05, ALUM, axis="y", segments=16)
    rotor.cylinder((0.0, -0.035, 0.0), 0.082, 0.140, 0.14, WALL, axis="y", segments=16, grad=False)
    rotor.cylinder((0.0, -0.145, 0.0), 0.014, 0.082, 0.08, CRIMSON, axis="y", segments=14, grad=False)

    # 3 аэродинамические скрученные лопасти (радиус 0.98 м → диаметр 1.96 м < 2.0 м клетки,
    # в позе покоя 0°/120°/240° ширина по X = 2 * 0.98 * sin(60°) = 1.70 м < 1.74 м плиты!)
    stations = [
        # (радиус, хорда, толщина, угол установки в градусах, вынос вперёд по -Y, цвет)
        (0.130, 0.125, 0.058, 24.0, 0.000, WALL),
        (0.260, 0.188, 0.048, 18.0, -0.010, WALL),
        (0.460, 0.156, 0.036, 12.0, -0.022, WALL),
        (0.660, 0.118, 0.025, 8.0, -0.034, WALL),
        (0.790, 0.092, 0.019, 6.0, -0.042, WALL),
        (0.890, 0.070, 0.014, 5.0, -0.048, CRIMSON),
        (0.980, 0.040, 0.009, 4.0, -0.054, CRIMSON),
    ]

    for b_idx in range(3):
        theta = b_idx * (2.0 * math.pi / 3.0)
        st, ct = math.sin(theta), math.cos(theta)
        # Единичные векторы лопасти: радиальный ur, хордовый в плоскости вращения ut (по ходу часовой стрелки), осевой ua (-Y)
        ur = (st, 0.0, ct)
        ut = (ct, 0.0, -st)

        # Цилиндрический комель лопасти (pitch bearing)
        rc = 0.105
        rotor.tilted_box(
            (ur[0] * rc, -0.005, ur[2] * rc),
            (0.076, 0.076, 0.095),
            ALUM,
            roll_y=theta,
        )

        # Профили вдоль размаха лопасти (4 вершины ромбовидного аэродинамического профиля на каждом сечении)
        rings = []
        for rad, chord, thick, pitch_deg, y_cone, _sw in stations:
            pa = math.radians(pitch_deg)
            cp, sp = math.cos(pa), math.sin(pa)
            # Вектор вдоль хорды (с учётом крутки на ветер −Y) и перпендикуляр толщины профиля
            cx_v = (ut[0] * cp, -sp, ut[2] * cp)
            th_v = (ut[0] * sp, cp, ut[2] * sp)
            bx = ur[0] * rad
            by = y_cone
            bz = ur[2] * rad

            p_lead = (bx + cx_v[0] * (chord * 0.36), by + cx_v[1] * (chord * 0.36), bz + cx_v[2] * (chord * 0.36))
            p_up = (bx + th_v[0] * (thick * 0.56), by - th_v[1] * (thick * 0.56), bz + th_v[2] * (thick * 0.56))
            p_trail = (bx - cx_v[0] * (chord * 0.64), by - cx_v[1] * (chord * 0.64), bz - cx_v[2] * (chord * 0.64))
            p_down = (bx - th_v[0] * (thick * 0.44), by + th_v[1] * (thick * 0.44), bz - th_v[2] * (thick * 0.44))
            rings.append((p_lead, p_up, p_trail, p_down, (bx, by, bz)))

        for s_i in range(len(rings) - 1):
            r0 = rings[s_i]
            r1 = rings[s_i + 1]
            sw = stations[s_i + 1][5]
            c_mid = (
                (r0[4][0] + r1[4][0]) * 0.5,
                (r0[4][1] + r1[4][1]) * 0.5,
                (r0[4][2] + r1[4][2]) * 0.5,
            )
            for k in range(4):
                kn = (k + 1) % 4
                quad = [r0[k], r0[kn], r1[kn], r1[k]]
                qm = (
                    sum(p[0] for p in quad) * 0.25 - c_mid[0],
                    sum(p[1] for p in quad) * 0.25 - c_mid[1],
                    sum(p[2] for p in quad) * 0.25 - c_mid[2],
                )
                rotor.add_poly(quad, sw, qm, grad=False)

        # Заглушки корня и законцовки лопасти
        rotor.add_poly([rings[0][3], rings[0][2], rings[0][1], rings[0][0]], WALL, (-ur[0], 0.0, -ur[2]), grad=False)
        rotor.add_poly([rings[-1][0], rings[-1][1], rings[-1][2], rings[-1][3]], CRIMSON, ur, grad=False)

    anim_spec = {
        "pivot_blender": list(HAWT_HUB_BLENDER),
        # После glTF (+Y up) и model_turns = 2 (фасад −Z): (x, y, z)_godot = (-x_b, z_b, y_b)
        "pivot_godot_turns_2": [0.0, HAWT_HUB_BLENDER[2], HAWT_HUB_BLENDER[1]],
        "pivot_godot_scene": [0.0, HAWT_HUB_BLENDER[2], -HAWT_HUB_BLENDER[1]],
        "axis_blender": "Y",
        "axis_sign": 1.0,
        "axis_godot": "Z",
        "frames": 120,
        "fps": 30,
        "clip_name": "spin-loop",
        "part_prefix": "wind_hawt",
    }
    return base, rotor, anim_spec, 1, 1


# ---------------------------------------------------------------------------
# 8. Вертикально-осевой ветрогенератор 1×1 с анимацией (wind_turbine_vawt_1x1)
# ---------------------------------------------------------------------------

VAWT_PIVOT_BLENDER = (0.0, 0.0, 1.04)


def build_wind_vawt_1x1():
    """Возвращает (base_builder, rotor_builder, anim_spec) для спирального генератора VAWT."""
    clear_scene()
    base = ArchBuilder("Base")
    # Симметричная эко-площадка 1.74 × 1.74 м с Z_min = 0.0
    base.box((0.0, 0.0, 0.015), (1.74, 1.74, 0.03), STONE)
    for sx in (-0.54, 0.54):
        for sy in (-0.54, 0.54):
            base.box((sx, sy, 0.034), (0.44, 0.44, 0.016), EMERALD, skip_bottom=True)

    # Многогранный статор прямого магнитного привода с изумрудным световым кольцом и рёбрами охлаждения
    base.chamfer_prism(0.0, 0.0, 0.03, 1.12, 1.12, 0.16, 0.30, CONCRETE)
    base.cylinder((0.0, 0.0, 0.42), 0.42, 0.36, 0.46, GUNMETAL, segments=16)
    base.cylinder((0.0, 0.0, 0.70), 0.375, 0.375, 0.09, EMERALD, segments=16, grad=False)
    base.cylinder((0.0, 0.0, 0.88), 0.35, 0.24, 0.28, WALL, segments=16)
    base.cylinder((0.0, 0.0, 1.03), 0.16, 0.15, 0.04, SLATE, segments=16)
    # 8 вертикальных радиаторных рёбер вокруг статора
    for i in range(8):
        ang = i * (math.pi * 0.25)
        rx, ry = 0.39 * math.cos(ang), 0.39 * math.sin(ang)
        base.box((rx, ry, 0.42), (0.05, 0.08, 0.40), ALUM, angle_z=ang + math.pi * 0.5, skip_bottom=True)

    # Передний дисплей мониторинга выработки (−Y) и задний инверторный модуль с солнечной панелью
    base.box((0.0, -0.52, 0.22), (0.36, 0.18, 0.36), SLATE, skip_bottom=True)
    base.facade_quad(0.0, -0.612, 0.26, (0, -1), 0.26, 0.14, SKY_BLUE, grad=False)
    base.box((0.0, 0.58, 0.25), (0.58, 0.28, 0.42), ALUM, skip_bottom=True)
    base.tilted_box((0.0, 0.58, 0.50), (0.56, 0.30, 0.03), ROYAL_BLUE, pitch_x=0.32)

    # --- Вращающийся спиральный ротор Дарье-Горлова (локальный (0, 0, 0) = VAWT_PIVOT_BLENDER) ---
    rotor = ArchBuilder("Rotor")
    # Центральный алюминиевый вал-колонна и аэродинамический оголовок с маяком
    rotor.cylinder((0.0, 0.0, 1.10), 0.095, 0.085, 2.20, ALUM, segments=14)
    rotor.cylinder((0.0, 0.0, 2.28), 0.095, 0.020, 0.18, WALL, segments=14, grad=False)
    rotor.cylinder((0.0, 0.0, 2.40), 0.032, 0.016, 0.07, CRIMSON, segments=10, grad=False)

    # Внутренний трёхзаходный стартерный ротор Савониуса (голубые скрученные лопатки вокруг вала)
    sav_steps = 8
    z_sav0, h_sav = 0.38, 1.38
    for v_idx in range(3):
        base_ang = v_idx * (2.0 * math.pi / 3.0) + 0.5
        for k in range(sav_steps):
            t0 = k / sav_steps
            t1 = (k + 1) / sav_steps
            a0 = base_ang + 1.35 * t0
            a1 = base_ang + 1.35 * t1
            zz0 = z_sav0 + h_sav * t0
            zz1 = z_sav0 + h_sav * t1
            r_in, r_out = 0.088, 0.225
            for sign_n, sw_sav in ((1.0, SKY_BLUE), (-1.0, ROYAL_BLUE)):
                off = sign_n * 0.012
                nx0, ny0 = -math.sin(a0), math.cos(a0)
                nx1, ny1 = -math.sin(a1), math.cos(a1)
                q = [
                    (r_in * math.cos(a0) + nx0 * off, r_in * math.sin(a0) + ny0 * off, zz0),
                    (r_out * math.cos(a0) + nx0 * off, r_out * math.sin(a0) + ny0 * off, zz0),
                    (r_out * math.cos(a1) + nx1 * off, r_out * math.sin(a1) + ny1 * off, zz1),
                    (r_in * math.cos(a1) + nx1 * off, r_in * math.sin(a1) + ny1 * off, zz1),
                ]
                rotor.add_poly(q, sw_sav, (nx0 * sign_n, ny0 * sign_n, 0.0), grad=False)

    # 3 внешние бочкообразные геликоидальные лопасти Дарье (закрутка 120° снизу вверх!)
    seg_n = 14
    z_bot = 0.14
    blade_h = 1.94
    twist_total = 2.0 * math.pi / 3.0

    def barrel_radius(t: float) -> float:
        return 0.45 + 0.20 * math.sin(math.pi * t)

    # Три яруса обтекаемых радиальных спиц-траверс (нижний, средний, верхний), точно приходящих в лопасти!
    for t_strut in (0.08, 0.50, 0.92):
        zs = z_bot + blade_h * t_strut
        rs = barrel_radius(t_strut)
        rotor.cylinder((0.0, 0.0, zs), 0.125, 0.125, 0.055, SLATE, segments=14)
        for b_idx in range(3):
            phi_s = b_idx * (2.0 * math.pi / 3.0) + twist_total * t_strut
            mx = (rs * 0.52) * math.cos(phi_s)
            my = (rs * 0.52) * math.sin(phi_s)
            rotor.box((mx, my, zs), (rs - 0.06, 0.052, 0.028), ALUM, angle_z=phi_s)

    for b_idx in range(3):
        phi0 = b_idx * (2.0 * math.pi / 3.0)
        rings = []
        for k in range(seg_n + 1):
            t = k / seg_n
            phi = phi0 + twist_total * t
            rad = barrel_radius(t)
            zk = z_bot + blade_h * t
            cp, sp = math.cos(phi), math.sin(phi)
            # Радиальный наружный вектор (cp, sp) и касательный (-sp, cp)
            chord = 0.210 - 0.035 * abs(2.0 * t - 1.0)
            thick = 0.048
            cx_k, cy_k = rad * cp, rad * sp
            p_lead = (cx_k - sp * (chord * 0.42), cy_k + cp * (chord * 0.42), zk)
            p_out = (cx_k + cp * (thick * 0.58), cy_k + sp * (thick * 0.58), zk)
            p_trail = (cx_k + sp * (chord * 0.58), cy_k - cp * (chord * 0.58), zk)
            p_in = (cx_k - cp * (thick * 0.42), cy_k - sp * (thick * 0.42), zk)
            rings.append((p_lead, p_out, p_trail, p_in, (cx_k, cy_k, zk)))

        for k in range(seg_n):
            r0 = rings[k]
            r1 = rings[k + 1]
            c_mid = (
                (r0[4][0] + r1[4][0]) * 0.5,
                (r0[4][1] + r1[4][1]) * 0.5,
                (r0[4][2] + r1[4][2]) * 0.5,
            )
            # Внешние грани спирали — белоснежные с непрерывным изумрудным кантом передней кромки
            face_swatches = (EMERALD, WALL, WALL, ALUM)
            for f_i in range(4):
                fn = (f_i + 1) % 4
                quad = [r0[f_i], r0[fn], r1[fn], r1[f_i]]
                qm = (
                    sum(p[0] for p in quad) * 0.25 - c_mid[0],
                    sum(p[1] for p in quad) * 0.25 - c_mid[1],
                    sum(p[2] for p in quad) * 0.25 - c_mid[2],
                )
                rotor.add_poly(quad, face_swatches[f_i], qm, grad=False)

        rotor.add_poly([rings[0][3], rings[0][2], rings[0][1], rings[0][0]], EMERALD, (0, 0, -1), grad=False)
        rotor.add_poly([rings[-1][0], rings[-1][1], rings[-1][2], rings[-1][3]], EMERALD, (0, 0, 1), grad=False)

    anim_spec = {
        "pivot_blender": list(VAWT_PIVOT_BLENDER),
        "pivot_godot_turns_2": [0.0, VAWT_PIVOT_BLENDER[2], 0.0],
        "pivot_godot_scene": [0.0, VAWT_PIVOT_BLENDER[2], 0.0],
        "axis_blender": "Z",
        "axis_sign": -1.0,
        "axis_godot": "Y",
        "frames": 90,
        "fps": 30,
        "clip_name": "spin-loop",
        "part_prefix": "wind_vawt",
    }
    return base, rotor, anim_spec, 1, 1


CIVIC_SPECS = [
    ("police_station_1x1", "Полицейский участок (1×1)", "POLICE", "police_01", build_police_station_1x1),
    ("police_precinct_2x1", "Полицейское управление (2×1)", "POLICE", "police_02", build_police_precinct_2x1),
    ("fire_station_1x1", "Пожарное депо (1×1)", "FIRE", "fire_01", build_fire_station_1x1),
    ("fire_depot_2x1", "Пожарная часть на 3 выезда (2×1)", "FIRE", "fire_02", build_fire_depot_2x1),
    ("clinic_1x1", "Городская поликлиника (1×1)", "HEALTH", "health_01", build_clinic_1x1),
    ("clinic_center_2x1", "Медицинский центр со скорой (2×1)", "HEALTH", "health_02", build_clinic_center_2x1),
]

WIND_SPECS = [
    ("wind_turbine_hawt_1x1", "Ветрогенератор трёхлопастной (HAWT)", "POWER_WIND_HAWT", build_wind_hawt_1x1),
    ("wind_turbine_vawt_1x1", "Вертикально-осевой ветрогенератор (VAWT)", "POWER_WIND_VAWT", build_wind_vawt_1x1),
]
