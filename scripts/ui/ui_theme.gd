class_name UiTheme
extends RefCounted
## Тема интерфейса в духе уютного изометрического градостроя:
## тёплые «бумажные» панели с мягкими тенями, 3D-иконки из Blender, цветные акценты категорий.
## Вариации (theme_type_variation): Title, Caption, Chip, Card, Tab, Small.

const PAPER := Color(0.985, 0.968, 0.928, 0.97)
const PAPER_DARK := Color(0.945, 0.918, 0.855, 1.0)
const PAPER_HOVER := Color(0.972, 0.948, 0.892, 1.0)
const INK := Color(0.19, 0.16, 0.13)
const INK_SOFT := Color(0.44, 0.39, 0.33)
const LINE := Color(0.32, 0.26, 0.20)
const ACCENT := Color(0.89, 0.45, 0.28)
const ACCENT_DARK := Color(0.72, 0.31, 0.17)
const BAD := Color(0.82, 0.20, 0.16)
const GOOD := Color(0.20, 0.62, 0.30)
const SHADOW := Color(0.10, 0.08, 0.05, 0.20)
const RADIUS: int = 12
const ICONS_DIR := "res://assets/ui/icons/"

## Цвета категорий инструментов (полоска карточки и вкладка).
const CATEGORY_COLORS: Dictionary[String, Color] = {
	"roads": Color(0.42, 0.49, 0.60),
	"zones": Color(0.28, 0.66, 0.36),
	"utilities": Color(0.90, 0.66, 0.14),
	"services": Color(0.82, 0.30, 0.26),
	"parks": Color(0.18, 0.62, 0.52),
	"bulldoze": Color(0.68, 0.34, 0.24),
	"filters": Color(0.36, 0.42, 0.78),
	"budget": Color(0.27, 0.62, 0.36),
}

## Иконки вкладок категорий.
const TAB_ICONS: Dictionary[String, String] = {
	"roads": "tool_road",
	"zones": "tool_zone_r",
	"utilities": "power_plant_01",
	"services": "health_01",
	"parks": "park_plaza",
	"filters": "tool_overlay",
	"budget": "stat_money",
}

## Имя → иконка; null — иконки нет (запомнено, чтобы не искать файл на каждом обновлении).
static var _icon_cache: Dictionary[String, Texture2D] = {}


## Загружает 3D-иконку из assets/ui/icons/<name>.png (с кэшем и прямым чтением PNG без ожидания импорта).
static func icon(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var res_path: String = ICONS_DIR + icon_name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = load(res_path) as Texture2D
	if tex == null:
		var abs_path: String = ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
	_icon_cache[icon_name] = tex
	return tex


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.65

	# Панели с мягкой тенью.
	var main_panel := box(PAPER, Color(LINE, 0.78), 2, RADIUS, Vector4(12, 8, 12, 8))
	main_panel.shadow_color = SHADOW
	main_panel.shadow_size = 8
	main_panel.shadow_offset = Vector2(0, 3)
	theme.set_stylebox(&"panel", &"PanelContainer", main_panel)
	theme.set_stylebox(&"panel", &"Panel", box(PAPER, Color(LINE, 0.78), 2, RADIUS))

	# Плашка показателя в верхней панели.
	theme.set_type_variation(&"Chip", &"PanelContainer")
	var chip_box := box(PAPER_DARK, Color(LINE, 0.24), 1, 9, Vector4(8, 3, 10, 3))
	chip_box.border_width_bottom = 2
	theme.set_stylebox(&"panel", &"Chip", chip_box)

	# Текст.
	theme.set_color(&"font_color", &"Label", INK)
	theme.set_type_variation(&"Title", &"Label")
	theme.set_font(&"font", &"Title", bold)
	theme.set_font_size(&"font_size", &"Title", 16)
	theme.set_type_variation(&"Caption", &"Label")
	theme.set_color(&"font_color", &"Caption", INK_SOFT)
	theme.set_font_size(&"font_size", &"Caption", 12)

	# Кнопки.
	_button_styles(theme, &"Button", PAPER_DARK, ACCENT, Vector4(10, 5, 10, 5))
	theme.set_type_variation(&"Small", &"Button")
	_button_styles(theme, &"Small", PAPER_DARK, ACCENT, Vector4(9, 3, 9, 3))
	theme.set_font_size(&"font_size", &"Small", 13)
	# Вкладка нижней панели.
	theme.set_type_variation(&"Tab", &"Button")
	_button_styles(theme, &"Tab", PAPER_DARK, ACCENT, Vector4(14, 6, 14, 6))
	theme.set_font(&"font", &"Tab", bold)
	theme.set_font_size(&"font_size", &"Tab", 14)
	# Карточка инструмента (цвет полоски задаёт card_styles).
	theme.set_type_variation(&"Card", &"Button")
	_button_styles(theme, &"Card", PAPER, ACCENT, Vector4(10, 6, 10, 8))
	theme.set_font_size(&"font_size", &"Card", 13)

	# Поля, списки, подсказки, окна, разделители.
	theme.set_stylebox(&"normal", &"LineEdit", box(Color.WHITE, Color(LINE, 0.45), 1, 8, Vector4(10, 6, 10, 6)))
	theme.set_stylebox(&"focus", &"LineEdit", box(Color.WHITE, ACCENT, 2, 8, Vector4(10, 6, 10, 6)))
	theme.set_color(&"font_color", &"LineEdit", INK)
	theme.set_color(&"font_placeholder_color", &"LineEdit", INK_SOFT)
	theme.set_stylebox(&"panel", &"ItemList", box(Color.WHITE, Color(LINE, 0.35), 1, 9, Vector4(8, 8, 8, 8)))
	theme.set_stylebox(&"selected", &"ItemList", box(Color(ACCENT, 0.22), ACCENT, 1, 6))
	theme.set_stylebox(&"selected_focus", &"ItemList", box(Color(ACCENT, 0.28), ACCENT, 1, 6))
	theme.set_stylebox(&"hovered", &"ItemList", box(PAPER_HOVER, Color(0, 0, 0, 0), 0, 6))
	theme.set_color(&"font_color", &"ItemList", INK)
	theme.set_color(&"font_selected_color", &"ItemList", INK)
	theme.set_color(&"font_hovered_color", &"ItemList", INK)
	var tip_box := box(Color(0.18, 0.15, 0.12, 0.96), Color(LINE, 0.5), 1, 8, Vector4(10, 6, 10, 6))
	tip_box.shadow_color = SHADOW
	tip_box.shadow_size = 6
	tip_box.shadow_offset = Vector2(0, 2)
	theme.set_stylebox(&"panel", &"TooltipPanel", tip_box)
	theme.set_color(&"font_color", &"TooltipLabel", Color(0.98, 0.95, 0.90))
	theme.set_stylebox(&"embedded_border", &"Window", box(PAPER, LINE, 2, RADIUS, Vector4(16, 36, 16, 12)))
	theme.set_stylebox(&"embedded_unfocused_border", &"Window", box(PAPER, LINE, 2, RADIUS, Vector4(16, 36, 16, 12)))
	theme.set_color(&"title_color", &"Window", INK)
	theme.set_font(&"title_font", &"Window", bold)
	theme.set_stylebox(&"panel", &"AcceptDialog", box(PAPER, Color(0, 0, 0, 0), 0, RADIUS))
	theme.set_stylebox(&"separator", &"VSeparator", line_box(Color(LINE, 0.22), true))
	theme.set_stylebox(&"separator", &"HSeparator", line_box(Color(LINE, 0.18), false))
	return theme


## Карточка инструмента категории: светлая с цветной полоской снизу и 3D-иконкой сверху.
static func card_styles(button: Button, category: String, icon_name: String = "", vertical_icon: bool = true) -> void:
	var color: Color = CATEGORY_COLORS.get(category, ACCENT)
	var normal := box(PAPER, Color(LINE, 0.28), 1, 10, Vector4(8, 5, 8, 7))
	normal.border_width_bottom = 5
	normal.border_color = color
	normal.shadow_color = Color(0.10, 0.08, 0.05, 0.10)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER_HOVER
	hover.border_color = color.lightened(0.1)
	var pressed := box(color, color.darkened(0.28), 2, 10, Vector4(8, 5, 8, 7))
	pressed.border_width_bottom = 5
	var disabled := box(Color(PAPER_DARK, 0.55), Color(LINE, 0.15), 1, 10, Vector4(8, 5, 8, 7))
	disabled.border_width_bottom = 4
	for state: StringName in [&"normal", &"focus"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_stylebox_override(&"disabled", disabled)
	button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"icon_normal_color", Color.WHITE)
	button.add_theme_color_override(&"icon_hover_color", Color.WHITE)
	button.add_theme_color_override(&"icon_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"icon_disabled_color", Color(1, 1, 1, 0.45))
	var tex: Texture2D = icon(icon_name)
	if tex != null:
		button.icon = tex
		if vertical_icon:
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.add_theme_constant_override(&"icon_max_width", 38)
			button.add_theme_constant_override(&"h_separation", 2)
		else:
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			button.add_theme_constant_override(&"icon_max_width", 28)
			button.add_theme_constant_override(&"h_separation", 8)


## Вкладка категории: иконка слева и цветная полоска снизу.
static func tab_styles(button: Button, category: String) -> void:
	var color: Color = CATEGORY_COLORS.get(category, ACCENT)
	var normal := box(PAPER_DARK, Color(LINE, 0.28), 1, 10, Vector4(12, 5, 14, 7))
	normal.border_width_bottom = 4
	normal.border_color = color
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER_HOVER
	var pressed := box(color, color.darkened(0.25), 2, 10, Vector4(12, 5, 14, 7))
	pressed.border_width_bottom = 4
	for state: StringName in [&"normal", &"focus"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"icon_normal_color", Color.WHITE)
	button.add_theme_color_override(&"icon_hover_color", Color.WHITE)
	button.add_theme_color_override(&"icon_pressed_color", Color.WHITE)
	var tex: Texture2D = icon(TAB_ICONS.get(category, ""))
	if tex != null:
		button.icon = tex
		button.add_theme_constant_override(&"icon_max_width", 24)
		button.add_theme_constant_override(&"h_separation", 6)


## Создаёт мини-иконку TextureRect для плашек верхней панели.
static func make_chip_icon(icon_name: String, size_px: int = 20) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(icon_name)
	rect.custom_minimum_size = Vector2(size_px, size_px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func box(bg: Color, border: Color, border_width: int, radius: int,
		padding: Vector4 = Vector4(6, 4, 6, 4)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	style.anti_aliasing = true
	return style


static func line_box(color: Color, vertical: bool) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = color
	line.vertical = vertical
	line.thickness = 1 if not vertical else 2
	return line


static func _button_styles(theme: Theme, type: StringName, bg: Color, accent: Color, padding: Vector4) -> void:
	var normal := box(bg, Color(LINE, 0.28), 1, 9, padding)
	normal.border_width_bottom = 2
	var hover := box(PAPER_HOVER, Color(LINE, 0.42), 1, 9, padding)
	hover.border_width_bottom = 2
	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, box(accent, ACCENT_DARK, 1, 9, padding))
	theme.set_stylebox(&"hover_pressed", type, box(accent.lightened(0.08), ACCENT_DARK, 1, 9, padding))
	theme.set_stylebox(&"disabled", type, box(Color(bg, 0.5), Color(LINE, 0.15), 1, 9, padding))
	theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())
	theme.set_color(&"font_color", type, INK)
	theme.set_color(&"font_hover_color", type, INK)
	theme.set_color(&"font_pressed_color", type, Color.WHITE)
	theme.set_color(&"font_hover_pressed_color", type, Color.WHITE)
	theme.set_color(&"font_disabled_color", type, Color(INK, 0.35))
