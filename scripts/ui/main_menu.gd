class_name MainMenu
extends CanvasLayer
## Главное меню поверх игры. При запуске за ним — последний город (или пустая карта),
## камера медленно облетает его. В игре Esc (без инструмента в руке) открывает то же меню как паузу.
## Пока меню открыто — пауза, HUD спрятан, клики и клавиши в мир не проходят.

const GAME_TITLE: String = "CityBuilder"
const SUBTITLE: String = "Уютный градострой"
## Скорость облёта камеры за меню, градусов в секунду.
const ORBIT_DEGREES: float = 4.0
const BUTTON_SIZE := Vector2(316, 52)
## Какую долю ширины экрана город сдвинут вправо — из-под карточки меню.
const VIEW_SHIFT: float = 0.17
const SHADE_SHADER: String = """
shader_type canvas_item;
uniform vec4 tint : source_color;
void fragment() {
	COLOR = vec4(tint.rgb, tint.a * pow(1.0 - UV.x, 1.6));
}
"""

@export var camera: Node3D
@export var hud: Hud

var _root := Control.new()
var _continue_button: Button
var _save_dialog := SaveDialog.new()
var _speed_before: int = 1
## Меню открыто (в том числе пока поверх него окно «Города»).
var _active: bool = false
var _tool_mode: int = BuildTool.Mode.NONE
var _modal_open: bool = false
## Меню открыто при запуске: город за ним только что загружен, изменений нет.
var _at_start: bool = true


func _ready() -> void:
	layer = 10
	_build()
	# В тестах (сцену добавили скриптом, а не запустили) меню само не открывается.
	if get_tree().current_scene == get_parent():
		_load_latest()
		open()
	else:
		_at_start = false
		_root.visible = false
	Events.load_done.connect(func(_name: String, _warnings: int) -> void:
		if _active:
			close())


func _process(delta: float) -> void:
	if _root.visible and not _save_dialog.visible and camera != null:
		camera.rotation.y += deg_to_rad(ORBIT_DEGREES) * delta


## Esc — раньше инструмента (_shortcut_input идёт до _unhandled_input): с инструментом в руке
## Esc его снимает, без инструмента — открывает меню. Окна сами закрываются по Esc в _input.
func _shortcut_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"tool_cancel") or _save_dialog.visible:
		return
	if _active:
		if not _at_start:
			close()
		get_viewport().set_input_as_handled()
	elif _tool_mode == BuildTool.Mode.NONE and not _modal_open:
		open()
		get_viewport().set_input_as_handled()


## Пока меню открыто, клавиши не доходят до инструмента, часов и слоёв карты.
func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event is InputEventKey:
		get_viewport().set_input_as_handled()


func open() -> void:
	_speed_before = SimClock.speed if SimClock.speed > 0 else 1
	SimClock.set_speed(0)
	Events.tool_requested.emit(BuildTool.Mode.NONE)
	_refresh_continue()
	if _at_start:
		_aim_camera()
	_active = true
	_root.visible = true
	_shift_view(true)
	if hud != null:
		hud.visible = false
	Events.modal_changed.emit(true)


func close() -> void:
	_active = false
	_root.visible = false
	_shift_view(false)
	_at_start = false
	if hud != null:
		hud.visible = true
	SimClock.set_speed(_speed_before)
	Events.modal_changed.emit(false)


func is_open() -> bool:
	return _active


# --- Действия ---

func _on_new_city() -> void:
	if _at_start or SaveManager.is_city_empty():
		SaveManager.new_city()
		close()
		return
	# Город мог измениться — спросит HUD: сохранить или нет.
	close()
	hud.request_new_city()


func _on_cities() -> void:
	_root.visible = false
	_save_dialog.open()


func _on_quit() -> void:
	# Как при закрытии окна: автосохранение, затем выход.
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


## Самое свежее целое сохранение — за меню (список уже отсортирован: новые первыми).
func _load_latest() -> void:
	for save: Dictionary in SaveManager.list_saves():
		if not save.broken and SaveManager.load_city(save.file):
			return


func _refresh_continue() -> void:
	var has_city: bool = not SaveManager.is_city_empty()
	_continue_button.visible = has_city or not _at_start
	if has_city:
		_continue_button.text = "Продолжить\n%s · день %d, %s" % [GameState.city_name, GameState.day,
				GameTime.clock(GameState.hours)]
	else:
		_continue_button.text = "Продолжить"


## Сдвиг картинки вбок (Camera3D.h_offset): камера облетает город, а он виден справа от меню.
func _shift_view(on: bool) -> void:
	var view: Camera3D = camera.get_node_or_null(^"Camera3D") if camera != null else null
	if view == null:
		return
	if not on:
		view.h_offset = 0.0
		return
	var distance: float = camera.get(&"_target_distance")
	var size: Vector2 = get_viewport().get_visible_rect().size
	var width: float = 2.0 * distance * tan(deg_to_rad(view.fov) * 0.5) * size.x / size.y
	view.h_offset = -VIEW_SHIFT * width


## При запуске — камера над серединой города (по дорогам и зданиям), чуть дальше обычного.
func _aim_camera() -> void:
	var grid: CityGrid = GameState.grid
	var cells: Array[Vector2i] = grid.road_cells.keys()
	for building: BuildingInstance in grid.buildings.values():
		cells.append_array(building.cells())
	if camera == null or cells.is_empty():
		return
	var sum := Vector2.ZERO
	for cell: Vector2i in cells:
		sum += Vector2(cell)
	var center: Vector3 = grid.grid_to_world(Vector2i(sum / cells.size()))
	camera.position = Vector3(center.x, 0.0, center.z)
	camera.set(&"_target_distance", 42.0)


# --- Внешний вид ---

func _build() -> void:
	var theme: Theme = UiTheme.build()
	_root.theme = theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Тёплая дымка слева направо: город справа виден, текст слева читается.
	var shade := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADE_SHADER
	material.set_shader_parameter(&"tint", Color(UiTheme.INK, 0.5))
	shade.material = material
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 72)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var card_style := UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 2, 18, Vector4(32, 28, 32, 28))
	card_style.shadow_color = Color(0.08, 0.06, 0.04, 0.30)
	card_style.shadow_size = 18
	card_style.shadow_offset = Vector2(0, 6)
	card.add_theme_stylebox_override(&"panel", card_style)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 14)
	column.add_child(header)
	var crest := UiTheme.make_chip_icon("menu_crest", 76)
	header.add_child(crest)
	var title_box := VBoxContainer.new()
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override(&"separation", 2)
	header.add_child(title_box)

	var title := Label.new()
	title.text = GAME_TITLE
	title.theme_type_variation = &"Title"
	title.add_theme_font_size_override(&"font_size", 40)
	title_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = SUBTITLE
	subtitle.theme_type_variation = &"Caption"
	subtitle.add_theme_font_size_override(&"font_size", 16)
	title_box.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	column.add_child(gap)

	_continue_button = _make_button("Продолжить", "zones", "stat_pop", func() -> void: close())
	_continue_button.custom_minimum_size = Vector2(BUTTON_SIZE.x, 62)
	# Главная кнопка — залита цветом.
	var color: Color = UiTheme.CATEGORY_COLORS["zones"]
	var filled := UiTheme.box(color, color.darkened(0.25), 2, 10, Vector4(14, 8, 14, 10))
	var filled_hover := UiTheme.box(color.lightened(0.1), color.darkened(0.25), 2, 10, Vector4(14, 8, 14, 10))
	_continue_button.add_theme_stylebox_override(&"normal", filled)
	_continue_button.add_theme_stylebox_override(&"hover", filled_hover)
	_continue_button.add_theme_color_override(&"font_color", Color.WHITE)
	_continue_button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	column.add_child(_continue_button)
	column.add_child(_make_button("Новый город", "roads", "tool_road", _on_new_city))
	column.add_child(_make_button("Города", "utilities", "stat_rank", _on_cities))
	column.add_child(_make_button("Выход", "services", "tool_dezone", _on_quit))

	var hint := Label.new()
	hint.text = "Esc в игре — это меню"
	hint.theme_type_variation = &"Caption"
	column.add_child(hint)

	_save_dialog.theme = theme
	_save_dialog.closed.connect(func() -> void:
		if _active:
			# Закрыли без загрузки — снова меню (окно вернуло скорость и modal_changed — правим).
			_root.visible = true
			SimClock.set_speed(0)
			Events.modal_changed.emit(true)
		else:
			# Загрузили город: меню уже закрыто, а окно вернуло паузу, что была при открытии.
			SimClock.set_speed(_speed_before))
	add_child(_save_dialog)

	Events.tool_mode_changed.connect(func(mode: int, _type_id: StringName) -> void: _tool_mode = mode)
	Events.modal_changed.connect(func(open_now: bool) -> void: _modal_open = open_now)
	Events.menu_requested.connect(func() -> void:
		if not _active:
			open())


## Широкая кнопка в стиле карточки, с 3D-иконкой слева и цветной полоской категории.
func _make_button(text: String, category: String, icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"Card"
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override(&"font_size", 17)
	UiTheme.card_styles(button, category, icon_name, false)
	button.pressed.connect(action)
	return button
