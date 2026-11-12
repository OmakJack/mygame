"""Процедурные генераторы low-poly моделей пешеходов (8 видов) и велосипедистов (4 вида) в палитре Kenney.

Все модели строятся в реальном масштабе человека (~1.72..1.84 м высотой), лицом на −Y (в glTF +Z,
в Godot с CAR_MODEL_TURNS = 2 — вперёд на −Z, масштаб PEOPLE_SCALE = 0.22 в PeopleVisualizer).
Акцентные образцы палитры (ROOF, ROOF_LITE, ROOF_WARM, ROOF_DEEP) автоматически перекрашиваются
шейдером BuildingPalette через INSTANCE_CUSTOM — каждый прохожий и велосипедист получает свой цвет
куртки/платья/рамы, сохраняя фиксированные цвета джинсов, кожи, волос, обуви, сумок, стаканчика кофе и колёс.
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

SKIN_WARM = TERRACOTTA
SKIN_LIGHT = COPPER
DENIM_DARK = GLASS_DARK
DENIM_LITE = GLASS_LITE


def _finalize_character(b: ArchBuilder) -> ArchBuilder:
    """Ставит подошву ровно на Z = 0.0 и центрирует модель по осям X и Y."""
    if not b.verts:
        return b
    xs = [v[0] for v in b.verts]
    ys = [v[1] for v in b.verts]
    zs = [v[2] for v in b.verts]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    min_z = min(zs)
    b.verts = [((x - cx), (y - cy), (z - min_z)) for (x, y, z) in b.verts]
    return b


def _add_head(
    b: ArchBuilder,
    cx: float,
    cy: float,
    z_neck: float,
    skin=SKIN_WARM,
    hair_swatch=IRON,
    hair_style="short",
    hat_swatch=None,
    glasses=False,
    pitch_x=0.0,
):
    """Выразительная low-poly голова с шеей, ушами, носом, причёской и головным убором."""
    # Шея
    b.cylinder((cx, cy, z_neck + 0.035), 0.055, 0.058, 0.07, skin, segments=8)
    hz = z_neck + 0.165
    # Основной объём головы со скошенными углами
    b.chamfer_prism(cx, cy, z_neck + 0.055, 0.22, 0.23, 0.22, 0.045, skin)
    # Нос (смотрит вперёд на −Y) и уши
    b.box((cx, cy - 0.122, hz - 0.005), (0.042, 0.036, 0.052), skin)
    for sx in (-1, 1):
        b.box((cx + sx * 0.114, cy + 0.005, hz), (0.026, 0.045, 0.055), skin)
    # Солнцезащитные или обычные очки
    if glasses:
        b.box((cx, cy - 0.118, hz + 0.022), (0.19, 0.025, 0.042), CHARCOAL)
        for sx in (-1, 1):
            b.box((cx + sx * 0.048, cy - 0.122, hz + 0.022), (0.068, 0.02, 0.032), GLASS_DARK)

    z_top = z_neck + 0.275
    if hair_style == "short":
        b.chamfer_prism(cx, cy + 0.012, z_top - 0.03, 0.236, 0.244, 0.065, 0.045, hair_swatch)
        b.box((cx, cy + 0.095, hz + 0.01), (0.228, 0.065, 0.16), hair_swatch)
        b.box((cx, cy - 0.095, z_top - 0.015), (0.21, 0.06, 0.042), hair_swatch)
    elif hair_style == "parted":
        b.chamfer_prism(cx, cy + 0.01, z_top - 0.03, 0.24, 0.246, 0.068, 0.045, hair_swatch)
        b.box((cx - 0.03, cy - 0.10, z_top - 0.01), (0.16, 0.065, 0.048), hair_swatch)
        b.box((cx, cy + 0.098, hz + 0.015), (0.23, 0.06, 0.15), hair_swatch)
    elif hair_style == "long":
        b.chamfer_prism(cx, cy + 0.01, z_top - 0.032, 0.242, 0.25, 0.072, 0.05, hair_swatch)
        # Длинные пряди по бокам и на спине
        b.box((cx, cy + 0.095, hz - 0.05), (0.246, 0.085, 0.30), hair_swatch)
        for sx in (-1, 1):
            b.box((cx + sx * 0.108, cy + 0.01, hz - 0.03), (0.045, 0.16, 0.24), hair_swatch)
    elif hair_style == "bob":
        b.chamfer_prism(cx, cy + 0.01, z_top - 0.03, 0.244, 0.248, 0.07, 0.05, hair_swatch)
        b.box((cx, cy + 0.092, hz - 0.01), (0.244, 0.08, 0.21), hair_swatch)
        for sx in (-1, 1):
            b.box((cx + sx * 0.11, cy - 0.01, hz - 0.01), (0.042, 0.18, 0.19), hair_swatch)
    elif hair_style == "bun":
        b.chamfer_prism(cx, cy + 0.01, z_top - 0.03, 0.238, 0.244, 0.068, 0.045, hair_swatch)
        b.box((cx, cy + 0.095, hz + 0.01), (0.23, 0.065, 0.16), hair_swatch)
        b.cylinder((cx, cy + 0.085, z_top + 0.055), 0.068, 0.055, 0.075, hair_swatch, segments=8)

    if hat_swatch == "cap":
        # Бейсболка козырьком вперёд (−Y)
        b.chamfer_prism(cx, cy + 0.005, z_top - 0.02, 0.246, 0.25, 0.075, 0.05, ROOF_DEEP)
        b.tilted_box((cx, cy - 0.155, z_top - 0.008), (0.19, 0.12, 0.024), ROOF_DEEP, pitch_x=0.12)
    elif hat_swatch == "boater":
        # Летняя шляпка-канотье с лентой
        b.cylinder((cx, cy, z_top + 0.005), 0.195, 0.195, 0.024, CREAM, segments=12)
        b.cylinder((cx, cy, z_top + 0.048), 0.118, 0.114, 0.072, CREAM, segments=12)
        b.cylinder((cx, cy, z_top + 0.028), 0.122, 0.122, 0.025, ROOF_DEEP, segments=12)
    elif hat_swatch == "beret":
        # Французский берет (акцент)
        b.cylinder((cx + 0.02, cy + 0.01, z_top + 0.025), 0.135, 0.11, 0.058, ROOF_WARM, segments=10)
        b.box((cx + 0.02, cy + 0.01, z_top + 0.06), (0.025, 0.025, 0.025), ROOF_DEEP)
    elif hat_swatch == "sunhat":
        # Туристическая панама
        b.cylinder((cx, cy, z_top + 0.005), 0.175, 0.145, 0.032, SANDSTONE, segments=10)
        b.cylinder((cx, cy, z_top + 0.045), 0.115, 0.102, 0.065, SANDSTONE, segments=10)
    elif hat_swatch == "helmet_aero":
        # Спортивный велошлем с вентиляционными рёбрами
        b.chamfer_prism(cx, cy + 0.01, z_top - 0.015, 0.255, 0.295, 0.088, 0.06, ROOF_LITE)
        b.box((cx, cy - 0.135, z_top - 0.005), (0.21, 0.06, 0.028), CHARCOAL)
        for sx in (-0.06, 0.0, 0.06):
            b.box((cx + sx, cy + 0.01, z_top + 0.036), (0.024, 0.22, 0.022), SLATE)
    elif hat_swatch == "helmet_city":
        # Городской котелок-велошлем
        b.chamfer_prism(cx, cy + 0.005, z_top - 0.018, 0.252, 0.27, 0.085, 0.055, WALL)
        b.box((cx, cy - 0.13, z_top - 0.008), (0.19, 0.055, 0.024), ROOF_DEEP)


def _add_walking_legs(
    b: ArchBuilder,
    stride_deg: float = 16.0,
    pants_swatch=DENIM_DARK,
    shoe_swatch=CHARCOAL,
    sole_swatch=WALL,
    skirt_swatch=None,
    skin_swatch=None,
):
    """Ноги в естественном шаге (левая впереди на −Y, правая позади на +Y) с ботинками и подошвой."""
    ang = math.radians(stride_deg)
    hip_z = 0.78
    leg_len = 0.72
    for side, sign in ((-0.095, 1.0), (0.095, -1.0)):
        pitch = sign * ang
        # Центр бедра/голени с учётом наклона вокруг таза
        mid_y = -math.sin(pitch) * (leg_len * 0.46)
        mid_z = hip_z - math.cos(pitch) * (leg_len * 0.46)
        if skin_swatch is not None:
            # Верхняя часть голени/шорт и открытая икра
            b.tilted_box((side, mid_y * 0.55, hip_z - 0.18), (0.125, 0.135, 0.34), pants_swatch, pitch_x=pitch)
            b.tilted_box((side, mid_y * 1.12, hip_z - 0.46), (0.096, 0.105, 0.36), skin_swatch, pitch_x=pitch)
        else:
            b.tilted_box((side, mid_y, mid_z), (0.132, 0.148, leg_len), pants_swatch, pitch_x=pitch)

        # Стопа и ботинок у земли
        foot_y = -math.sin(pitch) * (leg_len * 0.90) - 0.035
        foot_z = max(0.042, hip_z - math.cos(pitch) * (leg_len * 0.92))
        b.tilted_box((side, foot_y, foot_z), (0.136, 0.23, 0.082), shoe_swatch, pitch_x=pitch * 0.35)
        b.tilted_box((side, foot_y, foot_z - 0.032), (0.140, 0.236, 0.026), sole_swatch, pitch_x=pitch * 0.35)

    # Тазовый пояс
    b.box((0.0, 0.0, hip_z + 0.02), (0.35, 0.21, 0.12), skirt_swatch or pants_swatch)
    if skirt_swatch is not None:
        # Трапециевидная юбка / подол платья или пальто
        b.cylinder((0.0, 0.0, 0.68), 0.26, 0.19, 0.38, skirt_swatch, segments=10)


def _add_swinging_arms(
    b: ArchBuilder,
    z_shoulder: float = 1.34,
    span_x: float = 0.245,
    left_pitch_deg: float = -18.0,
    right_pitch_deg: float = 18.0,
    sleeve_swatch=ROOF,
    skin_swatch=SKIN_WARM,
    short_sleeve=False,
):
    """Руки в противофазе шага; возвращает координаты левой и правой кисти (для сумок/кофе/портфеля)."""
    arm_len = 0.50
    hands = []
    for side, deg in ((-span_x, left_pitch_deg), (span_x, right_pitch_deg)):
        pitch = math.radians(deg)
        mid_y = -math.sin(pitch) * (arm_len * 0.48)
        mid_z = z_shoulder - math.cos(pitch) * (arm_len * 0.48)
        if short_sleeve:
            b.tilted_box((side, mid_y * 0.45, z_shoulder - 0.11), (0.108, 0.118, 0.22), sleeve_swatch, pitch_x=pitch)
            b.tilted_box((side, mid_y * 1.05, z_shoulder - 0.32), (0.088, 0.095, 0.28), skin_swatch, pitch_x=pitch)
        else:
            b.tilted_box((side, mid_y, mid_z), (0.106, 0.118, arm_len), sleeve_swatch, pitch_x=pitch)
        hx = side
        hy = -math.sin(pitch) * (arm_len * 0.98)
        hz = z_shoulder - math.cos(pitch) * (arm_len * 0.98)
        b.box((hx, hy, hz), (0.084, 0.092, 0.092), skin_swatch)
        hands.append((hx, hy, hz))
    return hands[0], hands[1]


# ===========================================================================
# 8 ПЕШЕХОДОВ (CITIZENS)
# ===========================================================================

def build_citizen_casual_m() -> ArchBuilder:
    """1. Горожанин в расстёгнутой куртке (акцент), белой футболке, джинсах, кроссовках и с рюкзаком."""
    clear_scene()
    b = ArchBuilder("citizen_casual_m")
    _add_walking_legs(b, stride_deg=17.0, pants_swatch=DENIM_DARK, shoe_swatch=SLATE, sole_swatch=WALL)
    # Торс: куртка (ROOF_DEEP — перекрашивается) + белая футболка на груди
    b.chamfer_prism(0.0, 0.0, 0.82, 0.39, 0.23, 0.58, 0.045, ROOF_DEEP)
    b.box((0.0, -0.108, 1.10), (0.15, 0.03, 0.54), WALL)
    # Воротник куртки
    b.box((0.0, 0.01, 1.40), (0.26, 0.20, 0.05), ROOF_WARM)
    # Городской рюкзак за спиной (+Y)
    b.chamfer_prism(0.0, 0.165, 0.92, 0.27, 0.14, 0.38, 0.035, CHARCOAL)
    b.box((0.0, 0.225, 1.02), (0.21, 0.04, 0.16), SANDSTONE)
    _add_swinging_arms(b, 1.34, 0.245, -18.0, 18.0, sleeve_swatch=ROOF_DEEP, skin_swatch=SKIN_WARM)
    _add_head(b, 0.0, 0.0, 1.41, skin=SKIN_WARM, hair_swatch=BRICK, hair_style="parted")
    return _finalize_character(b)


def build_citizen_dress_f() -> ArchBuilder:
    """2. Горожанка в расклешённом летнем платье (акцент) с белым воротничком и сумочкой через плечо."""
    clear_scene()
    b = ArchBuilder("citizen_dress_f")
    _add_walking_legs(
        b, stride_deg=15.0, pants_swatch=ROOF_WARM, shoe_swatch=BRICK, sole_swatch=CREAM,
        skirt_swatch=ROOF_WARM, skin_swatch=SKIN_LIGHT,
    )
    # Приталенный лиф платья (перекрашивается) + светлый поясок и воротничок
    b.chamfer_prism(0.0, 0.0, 0.86, 0.35, 0.21, 0.50, 0.045, ROOF_LITE)
    b.box((0.0, 0.0, 0.87), (0.365, 0.222, 0.055), CREAM)
    b.box((0.0, -0.095, 1.33), (0.20, 0.06, 0.05), WALL)
    # Дамская сумочка на правом боку
    b.tilted_box((0.03, 0.0, 1.10), (0.37, 0.225, 0.03), BRICK, roll_y=0.62)
    b.box((0.21, 0.03, 0.84), (0.08, 0.19, 0.16), BRICK)
    b.box((0.25, 0.03, 0.86), (0.02, 0.06, 0.05), CREAM)
    _add_swinging_arms(
        b, 1.31, 0.225, -15.0, 14.0, sleeve_swatch=ROOF_LITE, skin_swatch=SKIN_LIGHT, short_sleeve=True
    )
    _add_head(b, 0.0, 0.0, 1.37, skin=SKIN_LIGHT, hair_swatch=CLAY, hair_style="long")
    return _finalize_character(b)


def build_citizen_business_m() -> ArchBuilder:
    """3. Деловой горожанин в костюме, белой рубашке, ярком галстуке/жилете (акцент) и с портфелем."""
    clear_scene()
    b = ArchBuilder("citizen_business_m")
    _add_walking_legs(b, stride_deg=15.0, pants_swatch=CHARCOAL, shoe_swatch=IRON, sole_swatch=SLATE)
    # Пиджак с акцентом (жилет + галстук перекрашиваются, лацканы тёмные)
    b.chamfer_prism(0.0, 0.0, 0.82, 0.40, 0.23, 0.58, 0.045, GUNMETAL)
    b.box((0.0, -0.106, 1.16), (0.16, 0.032, 0.44), WALL)
    b.box((0.0, -0.114, 1.00), (0.15, 0.032, 0.26), ROOF_DEEP)
    b.box((0.0, -0.118, 1.15), (0.052, 0.034, 0.34), ROOF_LITE)
    # Акцентный нагрудный платок и плечевая кокетка, чтобы фигурка сверху тоже имела свой тон
    b.box((0.0, 0.0, 1.36), (0.39, 0.22, 0.06), ROOF_DEEP)
    left_h, right_h = _add_swinging_arms(
        b, 1.34, 0.25, -16.0, 8.0, sleeve_swatch=GUNMETAL, skin_swatch=SKIN_WARM
    )
    # Кожаный портфель в правой руке
    bx, by, bz = right_h
    b.box((bx + 0.04, by, bz - 0.04), (0.04, 0.12, 0.06), IRON)
    b.box((bx + 0.04, by, bz - 0.18), (0.075, 0.32, 0.24), BRICK)
    b.box((bx + 0.042, by, bz - 0.10), (0.082, 0.06, 0.04), SANDSTONE)
    _add_head(b, 0.0, 0.0, 1.41, skin=SKIN_WARM, hair_swatch=IRON, hair_style="short", glasses=True)
    return _finalize_character(b)


def build_citizen_shopper_f() -> ArchBuilder:
    """4. Покупательница в модном жакете (акцент), светлых брюках, шляпке-канотье и с 2 пакетами покупок."""
    clear_scene()
    b = ArchBuilder("citizen_shopper_f")
    _add_walking_legs(b, stride_deg=15.0, pants_swatch=CREAM, shoe_swatch=CLAY, sole_swatch=WALL)
    b.chamfer_prism(0.0, 0.0, 0.84, 0.37, 0.22, 0.54, 0.045, ROOF_WARM)
    b.box((0.0, -0.105, 1.12), (0.13, 0.028, 0.46), WALL)
    left_h, right_h = _add_swinging_arms(
        b, 1.32, 0.235, -10.0, 10.0, sleeve_swatch=ROOF_WARM, skin_swatch=SKIN_LIGHT
    )
    # Два ярких шоппинг-пакета в обеих руках
    for (hx, hy, hz), bag_sw, trim_sw in ((left_h, SANDSTONE, ROOF_LITE), (right_h, WALL, ROOF_DEEP)):
        sign_x = -1.0 if hx < 0 else 1.0
        bx = hx + sign_x * 0.045
        b.box((bx, hy, hz - 0.04), (0.03, 0.10, 0.07), IRON)
        b.box((bx, hy, hz - 0.19), (0.11, 0.24, 0.26), bag_sw)
        b.box((bx, hy, hz - 0.13), (0.116, 0.244, 0.06), trim_sw)
    _add_head(b, 0.0, 0.0, 1.39, skin=SKIN_LIGHT, hair_swatch=SANDSTONE, hair_style="bob", hat_swatch="boater")
    return _finalize_character(b)


def build_citizen_student_m() -> ArchBuilder:
    """5. Студент в худи с капюшоном (акцент), бейсболке, светлых джинсах и с рюкзаком."""
    clear_scene()
    b = ArchBuilder("citizen_student_m")
    _add_walking_legs(b, stride_deg=18.0, pants_swatch=DENIM_LITE, shoe_swatch=WALL, sole_swatch=CHARCOAL)
    # Объёмное худи (ROOF — перекрашивается) с карманом-кенгуру и капюшоном на плечах
    b.chamfer_prism(0.0, 0.0, 0.80, 0.40, 0.24, 0.59, 0.05, ROOF)
    b.box((0.0, -0.115, 0.94), (0.24, 0.035, 0.18), ROOF_LITE)
    b.chamfer_prism(0.0, 0.085, 1.34, 0.28, 0.16, 0.09, 0.04, ROOF_LITE)
    # Рюкзак со скейтом/тубусом
    b.chamfer_prism(0.0, 0.17, 0.92, 0.28, 0.15, 0.39, 0.04, SLATE)
    b.box((0.0, 0.23, 1.08), (0.22, 0.035, 0.06), WALL)
    _add_swinging_arms(b, 1.33, 0.245, -20.0, 20.0, sleeve_swatch=ROOF, skin_swatch=SKIN_WARM)
    _add_head(b, 0.0, 0.0, 1.40, skin=SKIN_WARM, hair_swatch=IRON, hair_style="short", hat_swatch="cap")
    return _finalize_character(b)


def build_citizen_coffee_f() -> ArchBuilder:
    """6. Горожанка в бежевом тренче с ярким шарфом и беретом (акцент) и стаканчиком кофе из кофейни."""
    clear_scene()
    b = ArchBuilder("citizen_coffee_f")
    _add_walking_legs(
        b, stride_deg=14.0, pants_swatch=CHARCOAL, shoe_swatch=IRON, sole_swatch=SLATE, skirt_swatch=CREAM
    )
    # Тренчкот + объёмный шарф (ROOF_WARM — перекрашивается)
    b.chamfer_prism(0.0, 0.0, 0.84, 0.37, 0.22, 0.53, 0.045, CREAM)
    b.box((0.0, 0.0, 0.94), (0.385, 0.232, 0.055), ROOF_DEEP)
    b.cylinder((0.0, -0.01, 1.35), 0.145, 0.135, 0.09, ROOF_WARM, segments=10)
    b.box((-0.06, -0.115, 1.20), (0.075, 0.04, 0.26), ROOF_WARM)
    # Правая рука согнута вперёд и держит стаканчик кофе навынос
    left_h, right_h = _add_swinging_arms(
        b, 1.31, 0.235, -14.0, -38.0, sleeve_swatch=CREAM, skin_swatch=SKIN_LIGHT
    )
    cx, cy, cz = right_h
    b.cylinder((cx, cy - 0.04, cz + 0.04), 0.036, 0.048, 0.13, WALL, segments=8)
    b.cylinder((cx, cy - 0.04, cz + 0.04), 0.043, 0.046, 0.055, SANDSTONE, segments=8)
    b.cylinder((cx, cy - 0.04, cz + 0.112), 0.052, 0.050, 0.022, CHARCOAL, segments=8)
    _add_head(b, 0.0, 0.0, 1.38, skin=SKIN_LIGHT, hair_swatch=BRICK, hair_style="long", hat_swatch="beret")
    return _finalize_character(b)


def build_citizen_hiker_m() -> ArchBuilder:
    """7. Турист / активный горожанин в двухцветной ветровке (акцент), шортах, панаме и с большим рюкзаком."""
    clear_scene()
    b = ArchBuilder("citizen_hiker_m")
    _add_walking_legs(
        b, stride_deg=19.0, pants_swatch=SANDSTONE, shoe_swatch=CLAY, sole_swatch=CHARCOAL, skin_swatch=SKIN_WARM
    )
    b.chamfer_prism(0.0, 0.0, 0.82, 0.39, 0.23, 0.57, 0.045, ROOF_LITE)
    b.box((0.0, 0.0, 1.26), (0.40, 0.236, 0.18), ROOF_DEEP)
    # Большой туристический рюкзак со свёрнутым ковриком сверху
    b.chamfer_prism(0.0, 0.185, 0.88, 0.30, 0.18, 0.46, 0.04, ROOF_DEEP)
    b.cylinder((0.0, 0.185, 1.38), 0.065, 0.065, 0.32, SANDSTONE, axis="x", segments=8)
    _add_swinging_arms(
        b, 1.34, 0.245, -20.0, 20.0, sleeve_swatch=ROOF_DEEP, skin_swatch=SKIN_WARM, short_sleeve=True
    )
    _add_head(b, 0.0, 0.0, 1.40, skin=SKIN_WARM, hair_swatch=CLAY, hair_style="short", hat_swatch="sunhat")
    return _finalize_character(b)


def build_citizen_coat_f() -> ArchBuilder:
    """8. Горожанка в длинном пальто (акцент) с высокой причёской-пучком и пакетом со свежим багетом."""
    clear_scene()
    b = ArchBuilder("citizen_coat_f")
    _add_walking_legs(
        b, stride_deg=14.0, pants_swatch=IRON, shoe_swatch=IRON, sole_swatch=CHARCOAL, skirt_swatch=ROOF_DEEP
    )
    b.chamfer_prism(0.0, 0.0, 0.84, 0.36, 0.22, 0.54, 0.045, ROOF_DEEP)
    # Отложной воротник и пуговицы пальто
    b.box((0.0, -0.105, 1.28), (0.22, 0.04, 0.14), CREAM)
    for zb in (0.96, 1.08, 1.20):
        b.box((0.0, -0.115, zb), (0.035, 0.02, 0.035), CREAM)
    left_h, right_h = _add_swinging_arms(
        b, 1.32, 0.23, -28.0, 14.0, sleeve_swatch=ROOF_DEEP, skin_swatch=SKIN_LIGHT
    )
    # Бумажный пакет из булочной с двумя золотистыми багетами в левой руке
    lx, ly, lz = left_h
    b.box((lx - 0.03, ly - 0.02, lz + 0.06), (0.12, 0.16, 0.22), SANDSTONE)
    b.tilted_box((lx - 0.02, ly - 0.03, lz + 0.22), (0.055, 0.055, 0.22), COPPER, pitch_x=0.18)
    b.tilted_box((lx - 0.05, ly + 0.01, lz + 0.20), (0.052, 0.052, 0.19), TERRACOTTA, pitch_x=-0.12)
    _add_head(b, 0.0, 0.0, 1.39, skin=SKIN_LIGHT, hair_swatch=IRON, hair_style="bun")
    return _finalize_character(b)


# ===========================================================================
# 4 ВЕЛОСИПЕДИСТА (CYCLISTS)
# ===========================================================================

def _add_bicycle_base(
    b: ArchBuilder,
    frame_swatch=ROOF,
    step_through: bool = False,
    fenders: bool = False,
    drop_bars: bool = False,
):
    """Строит детализированный low-poly велосипед вдоль оси Y (переднее колесо на −Y, заднее на +Y)."""
    wheel_r = 0.33
    y_front, y_rear = -0.52, 0.52
    for wy in (y_front, y_rear):
        # Покрышка, серебристый обод, втулка и крестовина спиц
        b.cylinder((0.0, wy, wheel_r), wheel_r, wheel_r, 0.052, IRON, axis="x", segments=14)
        b.cylinder((0.0, wy, wheel_r), wheel_r * 0.76, wheel_r * 0.76, 0.056, ALUM, axis="x", segments=12)
        b.cylinder((0.0, wy, wheel_r), wheel_r * 0.62, wheel_r * 0.62, 0.060, CHARCOAL, axis="x", segments=10)
        b.cylinder((0.0, wy, wheel_r), 0.058, 0.058, 0.095, STEEL, axis="x", segments=8)
        for ang in (0.0, math.pi * 0.25, math.pi * 0.5, math.pi * 0.75):
            b.tilted_box((0.0, wy, wheel_r), (0.022, wheel_r * 1.48, 0.028), STEEL, pitch_x=ang)
        if fenders:
            # Аккуратное верхнее крыло-щиток над колесом (не закрывает серебристый обод сбоку!)
            b.tilted_box((0.0, wy - 0.06, wheel_r * 1.98), (0.062, 0.24, 0.026), SLATE, pitch_x=0.18)
            b.tilted_box((0.0, wy + 0.12, wheel_r * 1.86), (0.062, 0.24, 0.026), SLATE, pitch_x=-0.42)

    # Кареточный узел и педали
    bb_y, bb_z = 0.06, 0.34
    b.cylinder((0.0, bb_y, bb_z), 0.075, 0.075, 0.11, STEEL, axis="x", segments=10)
    b.box((-0.11, bb_y - 0.07, bb_z + 0.09), (0.09, 0.12, 0.035), IRON)
    b.box((0.11, bb_y + 0.07, bb_z - 0.09), (0.09, 0.12, 0.035), IRON)

    # Передняя вилка и рулевая колонка
    for sx in (-0.042, 0.042):
        b.tilted_box((sx, -0.48, 0.56), (0.034, 0.042, 0.48), STEEL, pitch_x=-0.16)
    b.tilted_box((0.0, -0.42, 0.80), (0.048, 0.048, 0.32), frame_swatch, pitch_x=-0.16)

    # Подседельная труба и седло
    b.tilted_box((0.0, 0.20, 0.61), (0.048, 0.048, 0.56), frame_swatch, pitch_x=0.24)
    b.box((0.0, 0.27, 0.90), (0.14, 0.24, 0.055), CHARCOAL)

    # Перья заднего треугольника и главные трубы рамы
    for sx in (-0.042, 0.042):
        b.box((sx, 0.29, 0.335), (0.030, 0.48, 0.035), frame_swatch)
        b.tilted_box((sx, 0.38, 0.56), (0.028, 0.48, 0.032), frame_swatch, pitch_x=-0.78)
    b.tilted_box((0.0, -0.18, 0.54), (0.052, 0.62, 0.052), frame_swatch, pitch_x=-0.56)
    if step_through:
        # Заниженная изогнутая труба городского круизера
        b.tilted_box((0.0, -0.14, 0.46), (0.048, 0.56, 0.048), frame_swatch, pitch_x=-0.38)
    else:
        # Горизонтальная верхняя труба
        b.tilted_box((0.0, -0.09, 0.78), (0.048, 0.66, 0.048), frame_swatch, pitch_x=-0.06)

    # Руль и фара
    hb_y, hb_z = -0.40, 0.98
    if drop_bars:
        b.box((0.0, hb_y, hb_z - 0.03), (0.44, 0.048, 0.048), CHARCOAL)
        for sx in (-0.21, 0.21):
            b.box((sx, hb_y - 0.06, hb_z - 0.08), (0.042, 0.14, 0.12), CHARCOAL)
    else:
        b.box((0.0, hb_y, hb_z), (0.52, 0.048, 0.048), STEEL)
        for sx in (-0.23, 0.23):
            b.box((sx, hb_y + 0.04, hb_z), (0.055, 0.12, 0.055), IRON)
    b.cylinder((0.0, -0.46, 0.84), 0.042, 0.035, 0.07, GLASS_LITE, axis="y", segments=8)


def _add_cyclist_rider(
    b: ArchBuilder,
    jersey_swatch=ROOF,
    pants_swatch=CHARCOAL,
    skin_swatch=SKIN_WARM,
    lean_deg: float = 24.0,
    hair_swatch=IRON,
    hair_style="short",
    hat_swatch="helmet_aero",
):
    """Сажает велосипедиста в динамичную позу на седло с руками на руле и ногами на педалях."""
    # Асимметричное положение ног на педалях (левая выше, правая ниже)
    b.tilted_box((-0.105, 0.09, 0.68), (0.125, 0.14, 0.44), pants_swatch, pitch_x=-0.52)
    b.tilted_box((-0.105, -0.02, 0.48), (0.11, 0.12, 0.28), pants_swatch, pitch_x=0.15)
    b.tilted_box((0.105, 0.14, 0.58), (0.125, 0.14, 0.48), pants_swatch, pitch_x=-0.18)
    b.tilted_box((0.105, 0.12, 0.36), (0.11, 0.12, 0.28), pants_swatch, pitch_x=0.08)

    # Торс с наклоном вперёд к рулю
    lean = math.radians(lean_deg)
    ty = 0.22 - math.sin(lean) * 0.28
    tz = 0.92 + math.cos(lean) * 0.28
    b.tilted_box((0.0, ty, tz), (0.37, 0.23, 0.56), jersey_swatch, pitch_x=-lean)

    # Руки тянутся от плеч к грипсам руля
    sh_y = 0.22 - math.sin(lean) * 0.50
    sh_z = 0.92 + math.cos(lean) * 0.50
    for sx in (-0.21, 0.21):
        b.tilted_box((sx, (sh_y - 0.38) * 0.5, (sh_z + 0.96) * 0.5), (0.098, 0.11, 0.48), jersey_swatch, pitch_x=-0.88)
        b.box((sx, -0.38, 0.96), (0.082, 0.09, 0.085), skin_swatch)

    # Голова смотрит строго вперёд (−Y)
    _add_head(
        b, 0.0, sh_y - 0.05, sh_z + 0.03,
        skin=skin_swatch, hair_swatch=hair_swatch, hair_style=hair_style, hat_swatch=hat_swatch,
    )
    return (0.0, ty, tz, lean)


def build_cyclist_road() -> ArchBuilder:
    """9. Шоссейный велосипедист в спортивном джерси (акцент) и велошлеме на байке с рулём-бараном."""
    clear_scene()
    b = ArchBuilder("cyclist_road")
    _add_bicycle_base(b, frame_swatch=ROOF, step_through=False, fenders=False, drop_bars=True)
    _add_cyclist_rider(
        b, jersey_swatch=ROOF_LITE, pants_swatch=CHARCOAL, skin_swatch=SKIN_WARM,
        lean_deg=30.0, hair_swatch=IRON, hair_style="short", hat_swatch="helmet_aero",
    )
    # Белая спортивная полоса на спине джерси
    b.tilted_box((0.0, 0.16, 1.22), (0.14, 0.04, 0.44), WALL, pitch_x=-math.radians(30.0))
    return _finalize_character(b)


def build_cyclist_city_cruiser() -> ArchBuilder:
    """10. Горожанка на прогулочном сити-байке (акцент) с прямой посадкой, передней корзиной и шляпкой."""
    clear_scene()
    b = ArchBuilder("cyclist_city_cruiser")
    _add_bicycle_base(b, frame_swatch=ROOF_WARM, step_through=True, fenders=True, drop_bars=False)
    # Плетёная корзина с покупками и цветами спереди руля
    b.chamfer_prism(0.0, -0.54, 0.72, 0.28, 0.22, 0.20, 0.04, SANDSTONE)
    b.box((-0.05, -0.54, 0.94), (0.08, 0.08, 0.10), WALL)
    b.box((0.05, -0.54, 0.93), (0.09, 0.09, 0.08), ROOF_LITE)
    _add_cyclist_rider(
        b, jersey_swatch=CREAM, pants_swatch=DENIM_LITE, skin_swatch=SKIN_LIGHT,
        lean_deg=12.0, hair_swatch=BRICK, hair_style="long", hat_swatch="boater",
    )
    # Яркий кардиган/жилет (акцент) поверх светлой блузки
    b.tilted_box((0.0, 0.16, 1.20), (0.38, 0.24, 0.42), ROOF_WARM, pitch_x=-math.radians(12.0))
    return _finalize_character(b)


def build_cyclist_courier() -> ArchBuilder:
    """11. Велокурьер доставки еды с большим квадратным термо-коробом (акцент) за спиной и на багажнике."""
    clear_scene()
    b = ArchBuilder("cyclist_courier")
    _add_bicycle_base(b, frame_swatch=CHARCOAL, step_through=False, fenders=True, drop_bars=False)
    _add_cyclist_rider(
        b, jersey_swatch=ROOF_DEEP, pants_swatch=DENIM_DARK, skin_swatch=SKIN_WARM,
        lean_deg=22.0, hair_swatch=IRON, hair_style="short", hat_swatch="cap",
    )
    # Задний багажник и крупный кубический термо-короб доставки (перекрашивается!)
    b.box((0.0, 0.50, 0.69), (0.20, 0.34, 0.035), STEEL)
    b.chamfer_prism(0.0, 0.34, 0.96, 0.38, 0.34, 0.38, 0.04, ROOF_LITE)
    # Белая светоотражающая полоса и логотип на коробе курьера
    b.box((0.0, 0.34, 1.15), (0.39, 0.35, 0.06), WALL)
    b.box((0.0, 0.34, 1.35), (0.26, 0.24, 0.025), CHARCOAL)
    return _finalize_character(b)


def build_cyclist_commuter() -> ArchBuilder:
    """12. Офисный вело-коммьютер в куртке (акцент) и городском шлеме, с дорожными велосумками на багажнике."""
    clear_scene()
    b = ArchBuilder("cyclist_commuter")
    _add_bicycle_base(b, frame_swatch=ROOF_DEEP, step_through=False, fenders=True, drop_bars=False)
    # Задний багажник и две боковые сумки-велоштаны (panniers)
    b.box((0.0, 0.48, 0.70), (0.22, 0.38, 0.035), STEEL)
    for sx in (-0.15, 0.15):
        b.chamfer_prism(sx, 0.48, 0.42, 0.11, 0.30, 0.28, 0.025, SANDSTONE)
        b.box((sx, 0.48, 0.62), (0.12, 0.31, 0.05), ROOF_WARM)
    _add_cyclist_rider(
        b, jersey_swatch=ROOF_DEEP, pants_swatch=SLATE, skin_swatch=SKIN_WARM,
        lean_deg=18.0, hair_swatch=CLAY, hair_style="short", hat_swatch="helmet_city",
    )
    # Рюкзак для ноутбука за спиной
    b.tilted_box((0.0, 0.26, 1.22), (0.26, 0.11, 0.34), GUNMETAL, pitch_x=-math.radians(18.0))
    return _finalize_character(b)


PEOPLE_SPECS = [
    # (id, kind, display_name, legacy_alias, fn)
    ("citizen_casual_m", "walker", "Горожанин в куртке с рюкзаком", "person-a", build_citizen_casual_m),
    ("citizen_dress_f", "walker", "Горожанка в летнем платье с сумочкой", "person-b", build_citizen_dress_f),
    ("citizen_business_m", "walker", "Офисный работник в костюме с портфелем", None, build_citizen_business_m),
    ("citizen_shopper_f", "walker", "Покупательница в шляпке с пакетами", None, build_citizen_shopper_f),
    ("citizen_student_m", "walker", "Студент в худи и кепке с рюкзаком", None, build_citizen_student_m),
    ("citizen_coffee_f", "walker", "Девушка в тренче и берете со стаканчиком кофе", None, build_citizen_coffee_f),
    ("citizen_hiker_m", "walker", "Турист в ветровке и панаме с ранцем", None, build_citizen_hiker_m),
    ("citizen_coat_f", "walker", "Дама в пальто с пакетом и французским багетом", None, build_citizen_coat_f),
    ("cyclist_road", "cyclist", "Шоссейный велосипедист в велошлеме", "cyclist", build_cyclist_road),
    ("cyclist_city_cruiser", "cyclist", "Горожанка на сити-байке с корзиной", None, build_cyclist_city_cruiser),
    ("cyclist_courier", "cyclist", "Велокурьер с термо-коробом доставки", None, build_cyclist_courier),
    ("cyclist_commuter", "cyclist", "Вело-коммьютер с багажными велосумками", None, build_cyclist_commuter),
]
