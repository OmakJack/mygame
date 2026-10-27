class_name UiTheme
extends RefCounted
## Тема интерфейса в духе CityRT: светлые «бумажные» панели, скруглённые углы, тёплый акцент.
## Собирается кодом — цвета и отступы в одном месте.
## Вариации (theme_type_variation): Title, Caption, Chip, Card, Tab, Small.

const PAPER := Color(0.985, 0.965, 0.92, 0.96)
const PAPER_DARK := Color(0.93, 0.9, 0.83, 1.0)
const PAPER_HOVER := Color(0.96, 0.93, 0.86, 1.0)
const INK := Color(0.21, 0.18, 0.15)
const INK_SOFT := Color(0.45, 0.4, 0.34)
const LINE := Color(0.33, 0.27, 0.21)
const ACCENT := Color(0.89, 0.45, 0.28)
const ACCENT_DARK := Color(0.74, 0.33, 0.19)
const BAD := Color(0.84, 0.22, 0.18)
const RADIUS: int = 12

## Цвета категорий инструментов (полоска карточки и вкладка).
const CATEGORY_COLORS: Dictionary[String, Color] = {
	"roads": Color(0.45, 0.5, 0.6),
	"zones": Color(0.33, 0.68, 0.36),
	"utilities": Color(0.92, 0.7, 0.18),
	"services": Color(0.82, 0.3, 0.27),
	"bulldoze": Color(0.62, 0.32, 0.25),
}


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.7

	# Панели.
	theme.set_stylebox(&"panel", &"PanelContainer", box(PAPER, LINE, 2, RADIUS, Vector4(14, 10, 14, 10)))
	theme.set_stylebox(&"panel", &"Panel", box(PAPER, LINE, 2, RADIUS))
	# Плашка показателя.
	theme.set_type_variation(&"Chip", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Chip", box(PAPER_DARK, Color(LINE, 0.25), 1, 9, Vector4(10, 4, 10, 4)))

	# Текст.
	theme.set_color(&"font_color", &"Label", INK)
	theme.set_type_variation(&"Title", &"Label")
	theme.set_font(&"font", &"Title", bold)
	theme.set_font_size(&"font_size", &"Title", 17)
	theme.set_type_variation(&"Caption", &"Label")
	theme.set_color(&"font_color", &"Caption", INK_SOFT)
	theme.set_font_size(&"font_size", &"Caption", 12)

	# Кнопки.
	_button_styles(theme, &"Button", PAPER_DARK, ACCENT, Vector4(10, 5, 10, 5))
	theme.set_type_variation(&"Small", &"Button")
	_button_styles(theme, &"Small", PAPER_DARK, ACCENT, Vector4(8, 2, 8, 2))
	theme.set_font_size(&"font_size", &"Small", 14)
	# Вкладка: скругление только сверху.
	theme.set_type_variation(&"Tab", &"Button")
	_button_styles(theme, &"Tab", PAPER_DARK, ACCENT, Vector4(16, 6, 16, 6))
	theme.set_font(&"font", &"Tab", bold)
	# Карточка инструмента (цвет полоски задаёт card_styles).
	theme.set_type_variation(&"Card", &"Button")
	_button_styles(theme, &"Card", PAPER, ACCENT, Vector4(12, 8, 12, 8))
	theme.set_font_size(&"font_size", &"Card", 14)

	# Поля, списки, подсказки, окна.
	theme.set_stylebox(&"normal", &"LineEdit", box(Color.WHITE, Color(LINE, 0.5), 1, 8, Vector4(8, 5, 8, 5)))
	theme.set_stylebox(&"focus", &"LineEdit", box(Color(0, 0, 0, 0), ACCENT, 2, 8))
	theme.set_color(&"font_color", &"LineEdit", INK)
	theme.set_color(&"font_placeholder_color", &"LineEdit", INK_SOFT)
	theme.set_stylebox(&"panel", &"ItemList", box(Color.WHITE, Color(LINE, 0.4), 1, 8, Vector4(6, 6, 6, 6)))
	theme.set_stylebox(&"selected", &"ItemList", box(Color(ACCENT, 0.25), ACCENT, 1, 6))
	theme.set_stylebox(&"selected_focus", &"ItemList", box(Color(ACCENT, 0.3), ACCENT, 1, 6))
	theme.set_stylebox(&"hovered", &"ItemList", box(PAPER_HOVER, Color(0, 0, 0, 0), 0, 6))
	theme.set_color(&"font_color", &"ItemList", INK)
	theme.set_color(&"font_selected_color", &"ItemList", INK)
	theme.set_color(&"font_hovered_color", &"ItemList", INK)
	theme.set_stylebox(&"panel", &"TooltipPanel", box(Color(0.22, 0.19, 0.16, 0.96), Color(0, 0, 0, 0), 0, 8, Vector4(10, 6, 10, 6)))
	theme.set_color(&"font_color", &"TooltipLabel", Color(0.98, 0.95, 0.9))
	theme.set_stylebox(&"embedded_border", &"Window", box(PAPER, LINE, 2, RADIUS, Vector4(16, 36, 16, 12)))
	theme.set_stylebox(&"embedded_unfocused_border", &"Window", box(PAPER, LINE, 2, RADIUS, Vector4(16, 36, 16, 12)))
	theme.set_color(&"title_color", &"Window", INK)
	theme.set_font(&"title_font", &"Window", bold)
	theme.set_stylebox(&"panel", &"AcceptDialog", box(PAPER, Color(0, 0, 0, 0), 0, RADIUS))
	theme.set_stylebox(&"separator", &"VSeparator", line_box(Color(LINE, 0.25), true))
	return theme


## Карточка инструмента категории: светлая с цветной полоской снизу; выбранная — залита цветом.
static func card_styles(button: Button, category: String) -> void:
	var color: Color = CATEGORY_COLORS[category]
	var normal := box(PAPER, Color(LINE, 0.3), 1, 10, Vector4(12, 8, 12, 10))
	normal.border_width_bottom = 5
	normal.border_color = color
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER_HOVER
	var pressed := box(color, color.darkened(0.25), 2, 10, Vector4(12, 8, 12, 10))
	for state: StringName in [&"normal", &"focus"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)


## Вкладка категории: снизу полоска цвета категории.
static func tab_styles(button: Button, category: String) -> void:
	var color: Color = CATEGORY_COLORS[category]
	var normal := box(PAPER_DARK, Color(LINE, 0.3), 1, 10, Vector4(16, 6, 16, 8))
	normal.border_width_bottom = 4
	normal.border_color = color
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER_HOVER
	var pressed := box(color, color.darkened(0.25), 2, 10, Vector4(16, 6, 16, 8))
	for state: StringName in [&"normal", &"focus"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)


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
	line.thickness = 2
	return line


static func _button_styles(theme: Theme, type: StringName, bg: Color, accent: Color, padding: Vector4) -> void:
	theme.set_stylebox(&"normal", type, box(bg, Color(LINE, 0.3), 1, 9, padding))
	theme.set_stylebox(&"hover", type, box(PAPER_HOVER, Color(LINE, 0.45), 1, 9, padding))
	theme.set_stylebox(&"pressed", type, box(accent, ACCENT_DARK, 1, 9, padding))
	theme.set_stylebox(&"hover_pressed", type, box(accent.lightened(0.08), ACCENT_DARK, 1, 9, padding))
	theme.set_stylebox(&"disabled", type, box(Color(bg, 0.5), Color(LINE, 0.15), 1, 9, padding))
	theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())
	theme.set_color(&"font_color", type, INK)
	theme.set_color(&"font_hover_color", type, INK)
	theme.set_color(&"font_pressed_color", type, Color.WHITE)
	theme.set_color(&"font_hover_pressed_color", type, Color.WHITE)
	theme.set_color(&"font_disabled_color", type, Color(INK, 0.35))
