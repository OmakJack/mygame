class_name UtilityMeter
extends VBoxContainer
## Шкала света или воды, как в инфо-видах Cities: Skylines: заливка — сколько город потребляет,
## бегунок — сколько дают станции. Зелёная — с запасом, оранжевая — почти впритык, красная — не хватает.
## Цифры — в кВт и м³ в сутки (Utilities.power_text / water_text). Сама читает GameState.utilities.

enum Kind { POWER, WATER }

## С какой доли мощности шкала оранжевая и пора ставить ещё станцию.
const NEAR_FULL: float = 0.85
const WARN := Color(0.90, 0.56, 0.12)

var kind: Kind

var _value := Label.new()
var _footer := Label.new()
var _bar := Bar.new()


func _init(meter_kind: Kind = Kind.POWER) -> void:
	kind = meter_kind
	add_theme_constant_override(&"separation", 3)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 6)
	head.add_child(UiTheme.make_chip_icon("stat_power" if kind == Kind.POWER else "stat_water", 18))
	var title := Label.new()
	title.text = "Электричество" if kind == Kind.POWER else "Вода"
	title.theme_type_variation = &"Title"
	title.add_theme_font_size_override(&"font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_value)
	add_child(head)
	add_child(_bar)
	_footer.theme_type_variation = &"Caption"
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_footer)
	refresh()


## Цифры с GameState.utilities: потребление, мощность станций, здания без ресурса.
func refresh() -> void:
	var utilities: Utilities = GameState.utilities
	if kind == Kind.POWER:
		show_values(utilities.power_use, utilities.power_supply, utilities.unpowered_count)
	else:
		show_values(utilities.water_use, utilities.water_supply, utilities.no_water_count)


func show_values(use: int, supply: int, unserved: int) -> void:
	var power: bool = kind == Kind.POWER
	var factor: int = Utilities.KW_PER_UNIT if power else Utilities.M3_PER_UNIT
	var unit_text: Callable = func(units: int) -> String:
		return Utilities.power_text(units) if power else Utilities.water_text(units)
	var station: String = "ветростанция" if power else "водозабор"
	var more: String = "ветряки на ветростанции" if power else "насосы на водозаборе"
	_value.text = "%s / %s" % [Utilities.digits(use * factor), unit_text.call(supply)]
	var color: Color = UiTheme.GOOD
	var footer := ""
	if supply == 0:
		color = UiTheme.BAD if use > 0 else UiTheme.INK_SOFT
		footer = ("Нет станций — %s %s" % ["нужна" if power else "нужен", station]) if use > 0 else "Станций пока нет"
	elif use > supply:
		color = UiTheme.BAD
		footer = "Не хватает %s — достройте %s" % [unit_text.call(use - supply), more]
	else:
		footer = "Запас %s" % unit_text.call(supply - use)
		if use >= supply * NEAR_FULL:
			color = WARN
			footer += " — пора достраивать станцию"
	if unserved > 0:
		footer += " · без %s %d зд." % ["света" if power else "воды", unserved]
	_footer.text = footer
	var footer_bad: bool = color == UiTheme.BAD or unserved > 0
	_footer.add_theme_color_override(&"font_color", UiTheme.BAD if footer_bad else UiTheme.INK_SOFT)
	_value.add_theme_color_override(&"font_color", UiTheme.BAD if color == UiTheme.BAD else UiTheme.INK)
	_bar.set_values(use, supply, color)
	tooltip_text = "Потребление: %s\nДают станции: %s\nБез %s: %d зд.\nДомик 1×1 — %s; %s" % [unit_text.call(use),
			unit_text.call(supply), "света" if power else "воды", unserved, unit_text.call(1), _stations_text(power)]


## «Ветростанция — 250 кВт, ветряк — +250 кВт…» — что дают станции из каталога и их модули.
static func _stations_text(power: bool) -> String:
	var parts: PackedStringArray = []
	for data: BuildingData in BuildingCatalog.buildable_types():
		var supply: int = data.power_supply if power else data.water_supply
		if supply > 0:
			parts.append("%s — %s" % [data.display_name.to_lower(),
					Utilities.power_text(supply) if power else Utilities.water_text(supply)])
		for item: StationModules.Module in StationModules.options(data.id):
			var extra: int = item.power if power else item.water
			if extra > 0:
				parts.append("%s — +%s" % [item.name.to_lower(),
						Utilities.power_text(extra) if power else Utilities.water_text(extra)])
	return ", ".join(parts)


## Сама шкала: дорожка, заливка потребления, бегунок на мощности станций (треугольник сверху).
class Bar extends Control:
	const HEIGHT: float = 12.0
	## Место над дорожкой под треугольник бегунка.
	const THUMB: float = 6.0
	## Шкала чуть длиннее большего из чисел — бегунок не прилипает к краю.
	const HEADROOM: float = 1.15
	const TRACK := Color(0.22, 0.19, 0.16, 0.18)
	const TRACK_BORDER := Color(0.22, 0.19, 0.16, 0.35)

	var use_share: float = 0.0
	var supply_share: float = 0.0
	var color: Color = UiTheme.GOOD

	func _init() -> void:
		custom_minimum_size = Vector2(160, HEIGHT + THUMB)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(use: int, supply: int, fill_color: Color) -> void:
		var scale: float = maxf(use, supply) * HEADROOM
		use_share = use / scale if scale > 0.0 else 0.0
		supply_share = supply / scale if scale > 0.0 else 0.0
		color = fill_color
		queue_redraw()

	func _draw() -> void:
		var track := StyleBoxFlat.new()
		track.bg_color = TRACK
		track.border_color = TRACK_BORDER
		track.set_border_width_all(1)
		track.set_corner_radius_all(5)
		draw_style_box(track, Rect2(0.0, THUMB, size.x, HEIGHT))
		var inner: float = size.x - 4.0
		if use_share > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = color
			fill.set_corner_radius_all(4)
			draw_style_box(fill, Rect2(2.0, THUMB + 2.0, maxf(4.0, inner * use_share), HEIGHT - 4.0))
		# Бегунок: риска через всю дорожку и треугольник над ней.
		var x: float = 2.0 + inner * supply_share
		draw_rect(Rect2(x - 1.0, THUMB - 1.0, 2.0, HEIGHT + 2.0), UiTheme.INK)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 5.0, 0.0), Vector2(x + 5.0, 0.0),
				Vector2(x, THUMB)]), UiTheme.INK)
