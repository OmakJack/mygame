class_name Advisor
extends PanelContainer
## Советник — вместо плашки подсказок: кнопка в верхней панели со счётчиком записей, по клику — список,
## что мешает городу (Hints.collect), и у записи кнопка «Показать»: камера летит к месту (ещё раз — к
## следующему), включается нужный слой карты или открывается вкладка. Новая тревога — кнопка вспыхивает,
## под ней на несколько секунд всплывает строчка (клик по ней открывает список). Окна не закрывают карту.
## Состояние не меняет: Events.camera_focus_requested / cell_inspected и сигнал entry_opened для HUD.

## HUD открывает вкладку или слой карты записи.
signal entry_opened(entry: Hints.Entry)

const WIDTH: float = 440.0
## Доля высоты окна, выше которой список прокручивается.
const MAX_HEIGHT_SHARE: float = 0.62
## Сколько секунд висит строчка о новой записи (первые шаги — дольше).
const BUBBLE_SECONDS: float = 5.0
const STEP_BUBBLE_SECONDS: float = 9.0
## Запись, которая пропала и вернулась раньше этого (мс), не всплывает снова (пробки то есть, то нет).
const ANNOUNCE_COOLDOWN_MS: int = 120000
const LEVEL_COLORS: Dictionary[int, Color] = {
	Hints.Level.STEP: Color(0.25, 0.5, 0.9),
	Hints.Level.ALERT: UiTheme.BAD,
	Hints.Level.WARNING: Color(0.93, 0.6, 0.1),
	Hints.Level.TIP: UiTheme.GOOD,
}
## Отступ окон от кнопки, px.
const GAP: float = 6.0

## Кнопка «Советник» — HUD ставит её в верхнюю панель.
var button := Button.new()
## Строчка о новой записи под кнопкой — HUD кладёт её рядом со списком.
var bubble := PanelContainer.new()
## Под этой панелью открываются список и строчка (верхняя панель HUD).
var anchor_bar: Control
## Записи последнего обновления, по срочности.
var entries: Array[Hints.Entry] = []

var _badge := PanelContainer.new()
var _badge_style := UiTheme.box(UiTheme.BAD, Color.WHITE, 2, 10, Vector4(5, 0, 5, 1))
var _badge_label := Label.new()
var _count_label := Label.new()
var _scroll := ScrollContainer.new()
var _rows := VBoxContainer.new()
var _empty := Label.new()
var _bubble_icon := TextureRect.new()
var _bubble_label := Label.new()
var _bubble_style := UiTheme.box(UiTheme.PAPER, Color(UiTheme.LINE, 0.4), 1, 10, Vector4(12, 8, 12, 8))
## Ключи записей прошлого обновления: новой записи — вспышка и строчка.
var _known: Dictionary[String, bool] = {}
## Когда запись всплывала (мс): не повторять чаще ANNOUNCE_COOLDOWN_MS.
var _announced_at: Dictionary[String, int] = {}
## Какое место записи показано последним (ключ → индекс): «Показать» перебирает места по кругу.
var _spot_index: Dictionary[String, int] = {}
## Ключ → кнопка «Показать» строки (подпись «2/5»).
var _actions: Dictionary[String, Button] = {}
## Ключи и тексты списка: строки не пересобираются, если ничего не поменялось.
var _signature: String = "-"
## Сколько кадров подгонять высоту списка (переносы строк считаются после раскладки).
var _fit_frames: int = 0
var _bubble_serial: int = 0
var _flash: Tween


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	column.add_child(head)
	var head_icon := TextureRect.new()
	head_icon.texture = make_icon(24)
	head_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(head_icon)
	var title := Label.new()
	title.text = "Советник"
	title.theme_type_variation = &"Title"
	head.add_child(title)
	_count_label.theme_type_variation = &"Caption"
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count_label)
	var close := Button.new()
	close.text = "✕"
	close.theme_type_variation = &"Small"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Свернуть"
	close.pressed.connect(close_list)
	head.add_child(close)
	column.add_child(HSeparator.new())
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_rows)
	_empty.text = "Всё спокойно: городу ничего не мешает расти"
	_empty.add_theme_color_override(&"font_color", UiTheme.GOOD)
	column.add_child(_empty)
	var help := Label.new()
	help.text = "«Показать» — к месту на карте, ещё раз — к следующему"
	help.theme_type_variation = &"Caption"
	column.add_child(help)

	# Только значок: верхняя панель и так почти во всю ширину (1152 px по умолчанию).
	button.icon = make_icon(24)
	button.custom_minimum_size = Vector2(44, 0)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.theme_type_variation = &"Small"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(func(on: bool) -> void:
		if on:
			open_list()
		else:
			close_list())
	# Счётчик записей — кружок в правом верхнем углу кнопки, цвет — самой срочной записи.
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override(&"panel", _badge_style)
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.offset_left = -12.0
	_badge.offset_right = 9.0
	_badge.offset_top = -9.0
	_badge.offset_bottom = 9.0
	_badge_label.add_theme_font_size_override(&"font_size", 11)
	_badge_label.add_theme_color_override(&"font_color", Color.WHITE)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_label)
	button.add_child(_badge)

	bubble.visible = false
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	bubble.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bubble.tooltip_text = "Открыть советника"
	_bubble_style.border_width_left = 5
	_bubble_style.border_width_top = 0
	_bubble_style.border_width_right = 0
	_bubble_style.border_width_bottom = 0
	_bubble_style.shadow_color = UiTheme.SHADOW
	_bubble_style.shadow_size = 8
	_bubble_style.shadow_offset = Vector2(0, 3)
	bubble.add_theme_stylebox_override(&"panel", _bubble_style)
	bubble.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			open_list())
	var bubble_row := HBoxContainer.new()
	bubble_row.add_theme_constant_override(&"separation", 8)
	bubble_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(bubble_row)
	_bubble_icon.custom_minimum_size = Vector2(26, 26)
	_bubble_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bubble_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bubble_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bubble_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_row.add_child(_bubble_icon)
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.custom_minimum_size = Vector2(380, 0)
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_row.add_child(_bubble_label)


func _process(_delta: float) -> void:
	if _fit_frames > 0:
		_fit_frames -= 1
		_fit()
	# Верхняя панель переносит плашки при смене ширины окна — окна следуют за кнопкой.
	if visible:
		_place_under_button(self)
	if bubble.visible:
		_place_under_button(bubble)


## Пересчитать записи (HUD зовёт с каждым обновлением показателей).
func refresh() -> void:
	entries = Hints.collect()
	var signature: String = ""
	for entry: Hints.Entry in entries:
		signature += entry.id + "\t" + entry.text + "\n"
	_update_badge()
	_announce_new()
	if signature != _signature:
		_signature = signature
		_rebuild_rows()


## Тексты записей (для проверок).
func texts() -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Hints.Entry in entries:
		result.append(entry.text)
	return result


func open_list() -> void:
	button.set_pressed_no_signal(true)
	_hide_bubble()
	visible = true
	_place_under_button(self)
	_fit_frames = 3


func close_list() -> void:
	button.set_pressed_no_signal(false)
	visible = false


## «Показать» у записи: следующее её место на карте (камера летит, у зданий — карточка «Инфо»), слой или вкладка.
## Возвращает номер показанного места или −1, если мест нет.
func show_entry(id: String) -> int:
	var entry: Hints.Entry = null
	for candidate: Hints.Entry in entries:
		if candidate.id == id:
			entry = candidate
	if entry == null:
		return -1
	var index: int = -1
	if not entry.cells.is_empty():
		index = (_spot_index.get(id, -1) + 1) % entry.cells.size()
		_spot_index[id] = index
		var cell: Vector2i = entry.cells[index]
		Events.camera_focus_requested.emit(cell)
		if entry.inspect:
			Events.cell_inspected.emit(cell)
		if _actions.has(id) and entry.cells.size() > 1:
			_actions[id].text = "Показать %d/%d" % [index + 1, entry.cells.size()]
	entry_opened.emit(entry)
	return index


func _update_badge() -> void:
	_badge.visible = not entries.is_empty()
	if entries.is_empty():
		button.tooltip_text = "Советник: проблем нет — городу ничего не мешает"
		return
	_badge_label.text = str(entries.size())
	_badge_style.bg_color = LEVEL_COLORS[entries[0].level]
	button.tooltip_text = "Советник: %s — что мешает городу и где это на карте (клик)" % _records(entries.size())


## «1 запись», «3 записи», «7 записей».
static func _records(count: int) -> String:
	var word: String = "записей"
	if count % 10 == 1 and count % 100 != 11:
		word = "запись"
	elif count % 10 in [2, 3, 4] and not (count % 100 in [12, 13, 14]):
		word = "записи"
	return "%d %s" % [count, word]


## Новая тревога или шаг — кнопка вспыхивает, строчка с самой срочной (если список закрыт).
func _announce_new() -> void:
	var fresh: Array[Hints.Entry] = []
	var known: Dictionary[String, bool] = {}
	var now: int = Time.get_ticks_msec()
	for entry: Hints.Entry in entries:
		known[entry.id] = true
		if _known.has(entry.id) or entry.level == Hints.Level.TIP:
			continue
		if _announced_at.has(entry.id) and now - _announced_at[entry.id] < ANNOUNCE_COOLDOWN_MS:
			continue
		_announced_at[entry.id] = now
		fresh.append(entry)
	_known = known
	if fresh.is_empty() or not is_inside_tree():
		return
	_flash_button()
	if not visible:
		_show_bubble(fresh[0], fresh.size() - 1)


func _flash_button() -> void:
	if _flash != null and _flash.is_valid():
		_flash.kill()
	_flash = create_tween()
	for i: int in 3:
		_flash.tween_property(button, ^"self_modulate", Color(1.0, 0.72, 0.5), 0.16)
		_flash.tween_property(button, ^"self_modulate", Color.WHITE, 0.26)


func _show_bubble(entry: Hints.Entry, more: int) -> void:
	_bubble_serial += 1
	var serial: int = _bubble_serial
	_bubble_icon.texture = UiTheme.icon(entry.icon)
	_bubble_label.text = entry.text
	if more > 0:
		_bubble_label.text += "\n+ ещё %d — нажмите сюда или на значок советника" % more
	_bubble_style.border_color = LEVEL_COLORS[entry.level]
	bubble.reset_size()
	_place_under_button(bubble)
	bubble.modulate.a = 0.0
	bubble.visible = true
	create_tween().tween_property(bubble, ^"modulate:a", 1.0, 0.2)
	var seconds: float = STEP_BUBBLE_SECONDS if entry.level == Hints.Level.STEP else BUBBLE_SECONDS
	await get_tree().create_timer(seconds).timeout
	if serial != _bubble_serial or not bubble.visible:
		return
	var fade: Tween = create_tween()
	fade.tween_property(bubble, ^"modulate:a", 0.0, 0.4)
	await fade.finished
	if serial == _bubble_serial:
		bubble.visible = false


func _hide_bubble() -> void:
	_bubble_serial += 1
	bubble.visible = false


func _rebuild_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_actions.clear()
	for entry: Hints.Entry in entries:
		_rows.add_child(_make_row(entry))
	_scroll.visible = not entries.is_empty()
	_empty.visible = entries.is_empty()
	_count_label.text = _records(entries.size()) if not entries.is_empty() else ""
	_fit_frames = 3


func _make_row(entry: Hints.Entry) -> Control:
	var row := PanelContainer.new()
	var style := UiTheme.box(UiTheme.PAPER_DARK, LEVEL_COLORS[entry.level], 0, 8, Vector4(10, 6, 8, 6))
	style.border_width_left = 4
	row.add_theme_stylebox_override(&"panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	row.add_child(line)
	line.add_child(UiTheme.make_chip_icon(entry.icon, 26))
	var label := Label.new()
	label.text = entry.text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(200, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(label)
	var caption: String = ""
	var tip: String = ""
	if not entry.cells.is_empty():
		caption = "Показать"
		tip = "Камера — к месту на карте" + (" (мест: %d, каждый клик — следующее)" % entry.cells.size()
				if entry.cells.size() > 1 else "")
	elif entry.overlay >= 0:
		caption = "На карте"
		tip = "Включить слой «%s»" % ZoneVisualizer.OVERLAY_NAMES[entry.overlay]
	elif not entry.tab.is_empty():
		caption = "Открыть"
		tip = "Открыть вкладку с нужными постройками"
	if caption.is_empty():
		return row
	var action := Button.new()
	action.text = caption
	action.tooltip_text = tip
	action.theme_type_variation = &"Small"
	action.focus_mode = Control.FOCUS_NONE
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id: String = entry.id
	action.pressed.connect(func() -> void: show_entry(id))
	line.add_child(action)
	_actions[id] = action
	return row


## Высота списка — по строкам, но не выше MAX_HEIGHT_SHARE окна (дальше — прокрутка).
func _fit() -> void:
	var limit: float = get_viewport_rect().size.y * MAX_HEIGHT_SHARE
	_scroll.custom_minimum_size = Vector2(0, minf(_rows.get_combined_minimum_size().y, limit))
	reset_size()


## Под кнопкой, ниже верхней панели, не за краем окна.
func _place_under_button(control: Control) -> void:
	var rect: Rect2 = button.get_global_rect()
	var top: float = (anchor_bar.get_global_rect().end.y if anchor_bar != null else rect.end.y) + GAP
	var width: float = get_viewport_rect().size.x
	control.global_position = Vector2(clampf(rect.position.x, GAP, maxf(GAP, width - control.size.x - GAP)), top)


## Значок советника: оранжевое облачко реплики с «!» (рисуется кодом, px × px).
static func make_icon(px: int) -> ImageTexture:
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var scale: float = px / 20.0
	var tail := PackedVector2Array([Vector2(3.5, 12.5), Vector2(9.5, 12.5), Vector2(3.0, 18.8)])
	for y: int in px:
		for x: int in px:
			var inside: int = 0
			var mark: int = 0
			for sy: int in 4:
				for sx: int in 4:
					var p := Vector2((x + (sx + 0.5) / 4.0) / scale, (y + (sy + 0.5) / 4.0) / scale)
					var corner: Vector2 = p.clamp(Vector2(6.0, 6.5), Vector2(14.0, 10.0))
					if p.distance_to(corner) <= 4.8 or Geometry2D.is_point_in_polygon(p, tail):
						inside += 1
						if (p.x >= 9.0 and p.x <= 11.0 and p.y >= 3.6 and p.y <= 9.6) \
								or p.distance_to(Vector2(10.0, 12.0)) <= 1.25:
							mark += 1
			if inside == 0:
				continue
			var color: Color = UiTheme.ACCENT.lerp(Color.WHITE, float(mark) / inside)
			color.a = inside / 16.0
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
