class_name SaveDialog
extends Control
## Окно сохранений: список городов, имя, «Сохранить», «Загрузить», «Удалить».
## Пока окно открыто — пауза, инструмент выключен, клики и клавиши в мир не проходят.

signal closed

var _list := ItemList.new()
var _name_edit := LineEdit.new()
var _confirm := ConfirmationDialog.new()
var _saves: Array[Dictionary] = []
## Что сделать после «Да» в окне подтверждения.
var _pending: Callable
var _speed_before: int = 1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Города"
	column.add_child(title)
	_list.custom_minimum_size = Vector2(520, 240)
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(func(_index: int) -> void: _load_selected())
	column.add_child(_list)

	var save_row := HBoxContainer.new()
	column.add_child(save_row)
	_name_edit.placeholder_text = "Имя города"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_text: String) -> void: _save())
	save_row.add_child(_name_edit)
	save_row.add_child(_make_button("Сохранить", _save))

	var actions := HBoxContainer.new()
	column.add_child(actions)
	actions.add_child(_make_button("Загрузить", _load_selected))
	actions.add_child(_make_button("Удалить", _delete_selected))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_make_button("Закрыть", close))

	_confirm.confirmed.connect(func() -> void: _pending.call())
	add_child(_confirm)


func open() -> void:
	_speed_before = SimClock.speed
	SimClock.set_speed(0)
	Events.tool_requested.emit(BuildTool.Mode.NONE)
	_name_edit.text = GameState.city_name
	_refresh()
	visible = true
	Events.modal_changed.emit(true)
	_name_edit.grab_focus()


func close() -> void:
	visible = false
	_name_edit.release_focus()
	SimClock.set_speed(_speed_before)
	Events.modal_changed.emit(false)
	closed.emit()


## Esc — здесь, а не в _unhandled_input: иначе первое нажатие съедает поле ввода.
func _input(event: InputEvent) -> void:
	if visible and not _confirm.visible and event.is_action_pressed(&"tool_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Пока окно открыто, клавиши не доходят до инструмента, часов и слоёв карты.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_list.clear()
	_saves = SaveManager.list_saves()
	for save: Dictionary in _saves:
		if save.broken:
			_list.add_item("%s (повреждено)" % save.file)
			continue
		var when: String = str(save.saved_at).replace("T", " ").left(16)
		_list.add_item("%s — день %d, жителей %d, $%d · %s" % [save.name, save.day, save.population, save.money, when])


func _on_item_selected(index: int) -> void:
	var save: Dictionary = _saves[index]
	# В поле — имя города без пометки «Автосохранение: ».
	if not save.broken:
		_name_edit.text = save.city_name


func _save() -> void:
	var city_name: String = _name_edit.text.strip_edges()
	if city_name.is_empty():
		return
	var file_id: String = SaveManager.file_id_for(city_name)
	var exists: bool = _saves.any(func(save: Dictionary) -> bool: return save.file == file_id)
	var do_save := func() -> void:
		if SaveManager.save_city(city_name):
			_refresh()
	if exists:
		_ask("Перезаписать сохранение «%s»?" % city_name, do_save)
	else:
		do_save.call()


func _load_selected() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return
	if SaveManager.load_city(_saves[selected[0]].file):
		close()


func _delete_selected() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return
	var save: Dictionary = _saves[selected[0]]
	_ask("Удалить сохранение «%s»? Его нельзя будет вернуть." % save.name, func() -> void:
		SaveManager.delete_save(save.file)
		_refresh())


func _ask(question: String, action: Callable) -> void:
	_pending = action
	_confirm.dialog_text = question
	_confirm.popup_centered()


func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
