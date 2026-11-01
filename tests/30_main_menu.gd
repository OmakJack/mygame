extends SceneTree
## Главное меню: запуск как настоящей сцены на копии сохранений; снимки и проверки Esc.
const OUT := "res://tests/out/"

func esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE; e.physical_keycode = KEY_ESCAPE; e.pressed = true
	root.push_input(e)
	var up := e.duplicate(); up.pressed = false
	root.push_input(up)

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var fails: Array[String] = []
	var check := func(name: String, ok: bool) -> void:
		if not ok: fails.append(name)
	var sm: Node = root.get_node("SaveManager")
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("SimClock")
	var ev: Node = root.get_node("Events")
	var dir := OUT + "menu_saves/"
	DirAccess.make_dir_recursive_absolute(dir)
	var src := OS.get_user_data_dir() + "/saves/"
	for f in DirAccess.get_files_at(src):
		DirAccess.copy_absolute(src + f, dir + f)
	sm.save_dir = dir
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30: await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node("MainMenu")
	var hud: CanvasLayer = main.get_node("HUD")
	var has_saves: bool = not sm.list_saves().is_empty()
	print("saves=%s city=%s day=%d" % [has_saves, gs.city_name, gs.day])
	check.call("menu open at start", menu.is_open() and not hud.visible and clock.speed == 0)
	root.get_texture().get_image().save_png(OUT + "menu_start.png")
	esc(); for i in 3: await process_frame
	check.call("esc at start keeps menu", menu.is_open())
	menu.close(); for i in 3: await process_frame
	check.call("continue", not menu.is_open() and hud.visible and clock.speed == 1)
	ev.tool_requested.emit(1)
	esc(); for i in 3: await process_frame
	check.call("esc drops tool, no menu", not menu.is_open())
	esc(); for i in 3: await process_frame
	check.call("esc opens pause menu", menu.is_open() and clock.speed == 0)
	root.get_texture().get_image().save_png(OUT + "menu_pause.png")
	esc(); for i in 3: await process_frame
	check.call("esc closes pause menu", not menu.is_open() and clock.speed == 1)
	ev.menu_requested.emit(); for i in 3: await process_frame
	check.call("menu button", menu.is_open())
	menu._on_cities(); for i in 3: await process_frame
	check.call("cities over menu", menu._save_dialog.visible and menu.is_open())
	menu._save_dialog.close(); for i in 3: await process_frame
	check.call("back to menu", menu._root.visible and clock.speed == 0)
	if has_saves:
		menu._on_cities(); await process_frame
		menu._save_dialog._list.select(0); menu._save_dialog._load_selected()
		for i in 3: await process_frame
		check.call("load closes menu, runs", not menu.is_open() and hud.visible and clock.speed == 1)
	ev.menu_requested.emit(); await process_frame
	menu._on_new_city(); for i in 5: await process_frame
	check.call("new city asks via hud", not menu.is_open() and (hud._new_city_confirm.visible or sm.is_city_empty()))
	print("ALL OK" if fails.is_empty() else "FAIL: " + ", ".join(fails))
	quit()
