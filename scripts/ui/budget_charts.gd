class_name BudgetCharts
extends RefCounted
## Графики вкладки «Бюджет»: кольцо долей статей (Donut) и история по игровым часам (TimeChart:
## казна линией с заливкой или доходы и расходы столбиками с итогом линией). Рисуются в _draw,
## при наведении — подсветка и подсказка.


## «$12 340», «−$80».
static func money_text(value: float, signed: bool = false) -> String:
	var rounded: int = roundi(value)
	var prefix: String = "−" if rounded < 0 else ("+" if rounded > 0 and signed else "")
	return prefix + "$" + Utilities.digits(absi(rounded))


## Подпись оси: «$800», «$12 тыс.», «$1,2 млн».
static func short_money(value: float) -> String:
	var a: float = absf(value)
	var minus: String = "−" if value < -0.5 else ""
	if a >= 1_000_000.0:
		return minus + ("$%.1f млн" % (a / 1_000_000.0)).replace(".", ",")
	if a >= 10_000.0:
		return minus + "$%d тыс." % roundi(a / 1000.0)
	return minus + "$" + Utilities.digits(roundi(a))


## Круглый шаг сетки: 1, 2, 5 × 10^n, чтобы линий было около count.
static func nice_step(span: float, count: int) -> float:
	if span <= 0.0:
		return 1.0
	var raw: float = span / count
	var power: float = pow(10.0, floor(log(raw) / log(10.0)))
	for mult: float in [1.0, 2.0, 5.0, 10.0]:
		if raw <= mult * power:
			return mult * power
	return 10.0 * power


## «День 3, 14:00» по номеру часа от начала игры.
static func hour_text(hour: int) -> String:
	return "День %d, %02d:00" % [GameTime.day_of(hour * GameTime.MINUTES_PER_HOUR), hour % GameTime.HOURS_PER_DAY]


## Кольцо долей: сегменты [значение, цвет, подпись]; в середине — итог.
class Donut extends Control:
	signal hovered(index: int)

	const THICKNESS: float = 0.2
	const GAP: float = 0.035
	## [[value, color, name], …]
	var segments: Array[Array] = []
	var center_text: String = ""
	var center_caption: String = ""
	## Подсвеченный сегмент (наведение здесь или на строке списка); −1 — никакой.
	var highlight: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(124, 124)

	func set_data(new_segments: Array[Array], text: String, caption: String) -> void:
		segments = new_segments
		center_text = text
		center_caption = caption
		queue_redraw()

	func set_highlight(index: int) -> void:
		if index != highlight:
			highlight = index
			queue_redraw()

	func total() -> float:
		var sum: float = 0.0
		for segment: Array in segments:
			sum += maxf(0.0, segment[0])
		return sum

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var outer: float = minf(size.x, size.y) * 0.5 - 4.0
		var inner: float = outer * (1.0 - THICKNESS * 2.0)
		var sum: float = total()
		if sum <= 0.0:
			_ring(center, inner, outer, 0.0, TAU, Color(UiTheme.LINE, 0.14))
		else:
			var start: float = -PI * 0.5
			var gap: float = GAP if segments.size() > 1 else 0.0
			for i: int in segments.size():
				var share: float = maxf(0.0, segments[i][0]) / sum
				if share <= 0.0:
					continue
				var sweep: float = share * TAU
				var grow: float = 4.0 if i == highlight else 0.0
				var color: Color = segments[i][1]
				if highlight >= 0 and i != highlight:
					color = color.lerp(Color(UiTheme.PAPER, 1.0), 0.45)
				_ring(center, inner - grow * 0.5, outer + grow, start + gap * 0.5, start + sweep - gap * 0.5, color)
				start += sweep
		var font: Font = get_theme_font(&"font", &"Title")
		var small: Font = get_theme_font(&"font", &"Label")
		var text_size: int = 15 if center_text.length() < 8 else 13
		var width: float = font.get_string_size(center_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		draw_string(font, center + Vector2(-width * 0.5, 4.0), center_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, UiTheme.INK)
		var cap_width: float = small.get_string_size(center_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(small, center + Vector2(-cap_width * 0.5, 19.0), center_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				UiTheme.INK_SOFT)

	## Сектор кольца с гладкими краями.
	func _ring(center: Vector2, inner: float, outer: float, from: float, to: float, color: Color) -> void:
		if to <= from:
			return
		var steps: int = maxi(2, ceili((to - from) / TAU * 96.0))
		var points := PackedVector2Array()
		for k: int in steps + 1:
			var angle: float = lerpf(from, to, float(k) / steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * outer)
		for k: int in range(steps, -1, -1):
			var angle: float = lerpf(from, to, float(k) / steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * inner)
		draw_colored_polygon(points, color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, color, 1.0, true)

	## Сегмент под точкой (−1 — мимо кольца).
	func segment_at(point: Vector2) -> int:
		var offset: Vector2 = point - size * 0.5
		var outer: float = minf(size.x, size.y) * 0.5 - 4.0
		var inner: float = outer * (1.0 - THICKNESS * 2.0)
		if offset.length() < inner or offset.length() > outer + 4.0:
			return -1
		var sum: float = total()
		if sum <= 0.0:
			return -1
		var angle: float = fposmod(offset.angle() + PI * 0.5, TAU)
		var start: float = 0.0
		for i: int in segments.size():
			start += maxf(0.0, segments[i][0]) / sum * TAU
			if angle <= start:
				return i
		return segments.size() - 1

	func _gui_input(event: InputEvent) -> void:
		var motion := event as InputEventMouseMotion
		if motion != null:
			var index: int = segment_at(motion.position)
			set_highlight(index)
			hovered.emit(index)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			set_highlight(-1)
			hovered.emit(-1)

	func _get_tooltip(at_position: Vector2) -> String:
		var index: int = segment_at(at_position)
		if index < 0:
			return ""
		var share: float = maxf(0.0, segments[index][0]) / maxf(total(), 0.001)
		return "%s: %s/ч, %d%%" % [segments[index][2], BudgetCharts.money_text(segments[index][0]), roundi(share * 100.0)]


## История по часам: казна (MONEY) или доходы и расходы (FLOW). Последняя точка — текущий час.
class TimeChart extends Control:
	enum Mode { MONEY, FLOW }

	const INCOME_COLOR := Color(0.27, 0.66, 0.36)
	const EXPENSE_COLOR := Color(0.85, 0.33, 0.27)
	const MONEY_COLOR := Color(0.89, 0.55, 0.20)
	const PAD_LEFT: float = 64.0
	const PAD_RIGHT: float = 14.0
	const PAD_TOP: float = 12.0
	const PAD_BOTTOM: float = 24.0

	var mode: Mode = Mode.MONEY
	## Сколько последних часов показать.
	var span_hours: int = 24
	var history: Budget.History = null
	## Текущий час: казна сейчас, доход и расход с начала часа, сколько минут прошло.
	var live_money: int = 0
	var live_income: int = 0
	var live_expenses: int = 0
	var live_hour: int = 0
	var live_minutes: int = 0
	var _hover: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(0, 122)

	func set_data(new_history: Budget.History, money_now: int, minutes_now: int) -> void:
		history = new_history
		live_money = money_now
		live_income = new_history.hour_income
		live_expenses = new_history.hour_expenses
		live_hour = minutes_now / GameTime.MINUTES_PER_HOUR
		live_minutes = minutes_now % GameTime.MINUTES_PER_HOUR
		queue_redraw()

	## Точки графика: [час, доход, расход, казна, текущий ли] — история за span_hours и текущий час.
	func points() -> Array[Array]:
		var result: Array[Array] = []
		if history == null:
			return result
		var first: int = maxi(0, history.size() - (span_hours - 1))
		for k: int in range(first, history.size()):
			result.append([history.hours[k], history.income[k], history.expenses[k], history.money[k], false])
		result.append([live_hour, live_income, live_expenses, live_money, true])
		return result

	func _plot_rect() -> Rect2:
		return Rect2(PAD_LEFT, PAD_TOP, maxf(10.0, size.x - PAD_LEFT - PAD_RIGHT), maxf(10.0, size.y - PAD_TOP - PAD_BOTTOM))

	func _draw() -> void:
		var rect: Rect2 = _plot_rect()
		var font: Font = get_theme_font(&"font", &"Label")
		var data: Array[Array] = points()
		draw_rect(rect, Color(1, 1, 1, 0.35))
		# Диапазон значений.
		var low: float = 0.0
		var high: float = 0.0
		for p: Array in data:
			if mode == Mode.MONEY:
				low = minf(low, p[3])
				high = maxf(high, p[3])
			else:
				high = maxf(high, p[1])
				low = minf(low, -float(p[2]))
		if high - low < 10.0:
			high = low + 10.0
		var step: float = BudgetCharts.nice_step(high - low, 4)
		low = floorf(low / step) * step
		high = ceilf(high / step) * step
		var to_y := func(value: float) -> float:
			return rect.end.y - (value - low) / (high - low) * rect.size.y
		# Сетка и подписи оси Y.
		var value: float = low
		while value <= high + step * 0.01:
			var y: float = to_y.call(value)
			var zero: bool = absf(value) < step * 0.01
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(UiTheme.LINE, 0.35 if zero else 0.10),
					1.5 if zero else 1.0)
			var label: String = BudgetCharts.short_money(value)
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(rect.position.x - w - 6.0, y + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					UiTheme.INK_SOFT)
			value += step
		var slots: int = maxi(span_hours, 2)
		var slot: float = rect.size.x / slots
		# Последняя точка — у правого края; до начала истории — пусто.
		var x_of := func(k: int) -> float:
			return rect.position.x + (slots - data.size() + k + 0.5) * slot
		# Подписи оси X: каждые 6 часов, полночь — «День N».
		for k: int in data.size():
			var hour: int = data[k][0]
			var live: bool = data[k][4]
			# Не теснимся у «сейчас»: круглый час ближе трёх столбиков к нему не подписываем.
			if not live and (hour % 6 != 0 or data.size() - 1 - k < 3):
				continue
			var text: String = "сейчас" if live else ("День %d" % GameTime.day_of(hour * GameTime.MINUTES_PER_HOUR)
					if hour % GameTime.HOURS_PER_DAY == 0 else "%02d:00" % (hour % GameTime.HOURS_PER_DAY))
			var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var x: float = x_of.call(k)
			draw_line(Vector2(x, rect.end.y), Vector2(x, rect.end.y + 4.0), Color(UiTheme.LINE, 0.4))
			draw_string(font, Vector2(clampf(x - tw * 0.5, rect.position.x, rect.end.x - tw), rect.end.y + 16.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.INK if live else UiTheme.INK_SOFT)
		if _hover >= data.size():
			_hover = -1
		if _hover >= 0:
			draw_rect(Rect2(x_of.call(_hover) - slot * 0.5, rect.position.y, slot, rect.size.y), Color(UiTheme.ACCENT, 0.10))
		var zero_y: float = to_y.call(0.0)
		if mode == Mode.MONEY:
			_draw_money(data, x_of, to_y, rect)
		else:
			var bar: float = clampf(slot * 0.36, 1.5, 14.0)
			var line := PackedVector2Array()
			for k: int in data.size():
				var x: float = x_of.call(k)
				# Текущий час — бледнее: он ещё копится.
				var alpha: float = 0.55 if data[k][4] else 1.0
				var top: float = to_y.call(float(data[k][1]))
				var bottom: float = to_y.call(-float(data[k][2]))
				if data[k][1] > 0:
					draw_rect(Rect2(x - bar, top, bar, zero_y - top), Color(INCOME_COLOR, alpha))
				if data[k][2] > 0:
					draw_rect(Rect2(x, zero_y, bar, bottom - zero_y), Color(EXPENSE_COLOR, alpha))
				line.append(Vector2(x, to_y.call(float(data[k][1] - data[k][2]))))
			if line.size() > 1:
				draw_polyline(line, MONEY_COLOR, 2.0, true)
			for p: Vector2 in line:
				draw_circle(p, 2.5, MONEY_COLOR)
		if data.size() == 1:
			var hint: String = "История копится: каждый игровой час — новый столбик"
			var hw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(rect.get_center().x - hw * 0.5, rect.position.y + 20.0), hint,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.INK_SOFT)
		if _hover >= 0:
			_draw_tip(data[_hover], Vector2(x_of.call(_hover), rect.position.y + 6.0), rect, font)

	func _draw_money(data: Array[Array], x_of: Callable, to_y: Callable, rect: Rect2) -> void:
		var line := PackedVector2Array()
		for k: int in data.size():
			line.append(Vector2(x_of.call(k), to_y.call(float(data[k][3]))))
		var base: float = clampf(to_y.call(0.0), rect.position.y, rect.end.y)
		if line.size() > 1:
			# Заливка под линией — от насыщенной к прозрачной.
			var poly := PackedVector2Array(line)
			poly.append(Vector2(line[line.size() - 1].x, base))
			poly.append(Vector2(line[0].x, base))
			var colors := PackedColorArray()
			for p: Vector2 in line:
				colors.append(Color(MONEY_COLOR, 0.32))
			colors.append(Color(MONEY_COLOR, 0.04))
			colors.append(Color(MONEY_COLOR, 0.04))
			draw_polygon(poly, colors)
			draw_polyline(line, MONEY_COLOR, 2.5, true)
		var last: Vector2 = line[line.size() - 1]
		draw_circle(last, 5.0, Color.WHITE)
		draw_circle(last, 3.5, MONEY_COLOR)

	func _draw_tip(p: Array, at: Vector2, rect: Rect2, font: Font) -> void:
		var lines: PackedStringArray = [
			("Сейчас (%d мин часа)" % live_minutes) if p[4] else BudgetCharts.hour_text(p[0]),
			"Доход  " + BudgetCharts.money_text(p[1], true),
			"Расход  " + BudgetCharts.money_text(-float(p[2]), true),
			"Итог  " + BudgetCharts.money_text(float(p[1] - p[2]), true),
			"Казна  " + BudgetCharts.money_text(p[3]),
		]
		var width: float = 0.0
		for line: String in lines:
			width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		var box := Rect2(Vector2.ZERO, Vector2(width + 20.0, lines.size() * 16.0 + 10.0))
		box.position = Vector2(at.x + 12.0, at.y)
		if box.end.x > rect.end.x:
			box.position.x = at.x - 12.0 - box.size.x
		draw_style_box(UiTheme.box(Color(0.16, 0.13, 0.10, 0.92), Color(0, 0, 0, 0), 0, 8), box)
		var colors: Array[Color] = [Color(1, 0.95, 0.88), INCOME_COLOR.lightened(0.35), EXPENSE_COLOR.lightened(0.3),
			MONEY_COLOR.lightened(0.25), Color(1, 0.95, 0.88)]
		for i: int in lines.size():
			draw_string(font, box.position + Vector2(10.0, 18.0 + i * 16.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					colors[i])

	## Точка под мышью (номер в points()), −1 — мимо.
	func index_at(point: Vector2) -> int:
		var rect: Rect2 = _plot_rect()
		if not rect.grow(2.0).has_point(point):
			return -1
		var count: int = points().size()
		var slots: int = maxi(span_hours, 2)
		var k: int = floori((point.x - rect.position.x) / (rect.size.x / slots)) - (slots - count)
		return k if k >= 0 and k < count else -1

	func _gui_input(event: InputEvent) -> void:
		var motion := event as InputEventMouseMotion
		if motion != null:
			var index: int = index_at(motion.position)
			if index != _hover:
				_hover = index
				queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
			_hover = -1
			queue_redraw()

	## Наведение — для проверок и снимков.
	func hover_at(index: int) -> void:
		_hover = index
		queue_redraw()
