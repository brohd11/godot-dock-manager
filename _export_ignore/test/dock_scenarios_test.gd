@tool
extends RefCounted
## Drives real docks in the running editor: placing, moving, reload, free, and the engine's own
## context popup. Editor only. Headless has no sub-windows, so engine floats only run in a windowed
## editor; headless covers the fallback instead. godot_versions_test.gd runs this on other versions.

const FixturePlugin = preload("res://addons/_lib/dock_manager/_export_ignore/test/fixtures/fixture_plugin.gd")
const FIXTURE_CONTROL_PATH = "res://addons/_lib/dock_manager/_export_ignore/test/fixtures/fixture_control.gd"
const FixtureControl = preload(FIXTURE_CONTROL_PATH)
const FixtureBare = preload("res://addons/_lib/dock_manager/_export_ignore/test/fixtures/fixture_bare_control.gd")
const EngineBackend = preload("res://addons/_lib/dock_manager/src/backend/engine_backend.gd")

const LEFT_BL = EditorPlugin.DOCK_SLOT_LEFT_BL
const LEFT_UR = EditorPlugin.DOCK_SLOT_LEFT_UR
const RIGHT_UL = EditorPlugin.DOCK_SLOT_RIGHT_UL
const RIGHT_BL = EditorPlugin.DOCK_SLOT_RIGHT_BL
const RIGHT_BR = EditorPlugin.DOCK_SLOT_RIGHT_BR
const FLOATING = DockManager.DOCK_SLOT_NONE
const BOTTOM = DockManager.DOCK_SLOT_BOTTOM
const BOTTOM_L = DockManager.DOCK_SLOT_BOTTOM_L
const BOTTOM_R = DockManager.DOCK_SLOT_BOTTOM_R
const MAIN_SCREEN = DockManager.DOCK_SLOT_MAIN_SCREEN

const READY_TIMEOUT_MS = 20000

static var _failures:int
static var _out:Array
static var _plugin:EditorPlugin


static func run_tests() -> Dictionary:
	if not Engine.is_editor_hint():
		return {"result": 0, "output": ["dock_scenarios: skipped (editor only)"]}
	_failures = 0
	_out = []
	if not await _wait_for_node_refs():
		return {"result": 1, "output": ["dock_scenarios: EditorNodeRef never became ready"]}
	
	_plugin = FixturePlugin.new()
	EditorInterface.get_base_control().add_child(_plugin)
	DirAccess.remove_absolute(DockManager.get_layout_file_path(_plugin))
	
	await _test_placing()
	await _test_popup()
	await _test_reload()
	await _test_our_float()
	await _test_no_dock_button()
	await _test_migration()
	if _minor() >= 6:
		await _test_engine_backend()
	if _minor() >= 8:
		await _test_engine_slots()
		await _test_engine_close()
	if EditorInterface.is_multi_window_enabled():
		await _test_engine_float()
		if _minor() >= 8:
			await _test_float_close()
	else:
		_out.append("skipped: engine floats need a windowed editor")
	
	DirAccess.remove_absolute(DockManager.get_layout_file_path(_plugin))
	_plugin.queue_free()
	_plugin = null
	return {"result": _failures, "output": _out}


static func _check(label:String, condition:bool) -> void:
	if not condition:
		_failures += 1
	_out.append("%s: %s" % ["PASS" if condition else "FAIL", label])

static func _minor() -> int:
	return Engine.get_version_info().minor

static func _frames(count:=4) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	for i in count:
		await tree.process_frame

static func _wait_for_node_refs() -> bool:
	var ready = [false]
	EditorNodeRef.call_on_ready(func(): ready[0] = true)
	var deadline = Time.get_ticks_msec() + READY_TIMEOUT_MS
	while not ready[0] and Time.get_ticks_msec() < deadline:
		await _frames(1)
	return ready[0]

static func _new_dock(slot:int, can_be_freed:=false) -> DockManager:
	var dock_manager = DockManager.new(_plugin, FixtureControl.new(), slot, null, false)
	dock_manager.can_be_freed = can_be_freed
	await dock_manager.add_to_tree()
	await _frames(6)
	return dock_manager

static func _free_dock(dock_manager:DockManager) -> void:
	if is_instance_valid(dock_manager):
		await dock_manager.free_instance()
		await _frames(6)

static func _action(dock_manager:DockManager, text:String):
	for action in dock_manager.get_popup_actions():
		if action.text == text:
			return action
	return null

static func _find_popup():
	for node in EditorInterface.get_base_control().get_children():
		if node.get_script() == DockManager.DockPopup:
			return node
	return null

## 4.7 only emits closed from the context popup's Close button, 4.8 from close_dock itself.
static func _close(dock) -> void:
	if _minor() < 8:
		dock.closed.emit()
	dock.close()

## The node the engine treats as the dock on this version.
static func _engine_dock(dock_manager:DockManager):
	if _minor() >= 8:
		return dock_manager._backend.dock
	if _minor() >= 6:
		return dock_manager._backend.editor_dock
	return dock_manager.plugin_control

## Presses a button in the engine's own dock context popup.
static func _press_engine_button(dock, text:String) -> bool:
	var tabs:TabContainer = dock.get_parent()
	if _minor() < 6:
		tabs.current_tab = tabs.get_tab_idx_from_control(dock)
		tabs.pre_popup_pressed.emit()
	else:
		tabs.get_tab_bar().tab_rmb_clicked.emit(tabs.get_tab_idx_from_control(dock))
	await _frames(3)
	for button in tabs.get_popup().find_children("*", "Button", true, false):
		if button.text == text and not button.disabled:
			button.pressed.emit()
			await _frames(6)
			return true
	tabs.get_popup().hide()
	return false


static func _test_placing() -> void:
	var dock_manager = await _new_dock(LEFT_UR)
	var control = dock_manager.plugin_control
	_check("placed in default", dock_manager.get_current_slot() == LEFT_UR)
	_check("binds dock_manager", control.dock_manager == dock_manager)
	_check("binds button", dock_manager.dock_button == control.dock_button)
	await dock_manager.dock_instance(RIGHT_BL)
	await _frames()
	_check("moves between sides", dock_manager.get_current_slot() == RIGHT_BL)
	await dock_manager.dock_instance(BOTTOM)
	await _frames()
	_check("moves to bottom", dock_manager.get_current_slot() == BOTTOM)
	dock_manager.remove_control_from_parent()
	await _frames()
	_check("detaches", control.get_parent() == null and not dock_manager.is_floating())
	
	# A control handed to another window, as script_dock does in a floated script editor.
	var host = Window.new()
	host.size = Vector2i(200, 200)
	EditorInterface.get_base_control().add_child(host)
	host.add_child(control)
	await _frames()
	_check("another window isn't a float", not dock_manager.is_floating() and dock_manager.get_dock_manager_window() == null)
	host.remove_child(control)
	host.queue_free()
	
	await dock_manager.dock_instance(dock_manager.default_dock)
	await _frames()
	_check("reattaches to default", dock_manager.get_current_slot() == LEFT_UR)
	await _free_dock(dock_manager)
	_check("frees", not is_instance_valid(dock_manager))

static func _test_popup() -> void:
	var dock_manager = await _new_dock(LEFT_BL, true)
	dock_manager.allow_scene_reload = true
	var control = dock_manager.plugin_control
	for text in ["Free Instance", "Reload", "Custom"]:
		_check("offers " + text, _action(dock_manager, text) != null)
	_check("make floating follows can_float", (_action(dock_manager, "Make Floating") != null) == dock_manager._backend.can_float())
	_check("no always on top while docked", _action(dock_manager, "Always on Top") == null)
	
	dock_manager.show_popup()
	await _frames(2)
	var popup = _find_popup()
	_check("popup opens", popup != null)
	if is_instance_valid(popup):
		var grid = popup.find_children("*", "Control", true, false).filter(func(n): return n is DockManager.DockPopup.SlotGrid)
		var expected_rows = 8 if _minor() >= 7 else 6
		_check("popup holds the grid", grid.size() == 1)
		_check("grid rows match the version", grid.size() == 1 and grid[0]._grid_size.y == expected_rows)
		var buttons = popup.find_children("*", "Button", true, false)
		_check("one button per action", buttons.size() == dock_manager.get_popup_actions().size())
		popup.hide_and_free()
	
	var menu = PopupMenu.new()
	EditorInterface.get_base_control().add_child(menu)
	dock_manager.add_popup_items(menu)
	_check("menu items added", menu.item_count == dock_manager.get_popup_actions().size())
	menu.id_pressed.emit(DockManager.POPUP_ID_BASE + menu.item_count - 1)
	await _frames(1)
	_check("menu item runs its action", control.custom_called)
	var submenu = dock_manager.get_submenu()
	_check("submenu holds the actions", submenu.item_count == menu.item_count)
	submenu.free()
	menu.queue_free()
	
	await dock_manager._on_popup_slot_chosen(RIGHT_UL)
	await _frames()
	_check("popup slot moves the dock", dock_manager.get_current_slot() == RIGHT_UL)
	await _free_dock(dock_manager)

static func _test_reload() -> void:
	var dock_manager = await _new_dock(RIGHT_BL)
	var control = dock_manager.plugin_control
	control.data = {"n": 7}
	await dock_manager.reload_control()
	await _frames(8)
	var reloaded = dock_manager.plugin_control
	_check("reload makes a new control", reloaded != control and is_instance_valid(reloaded))
	_check("reload restores data", int(reloaded.data.n) == 7)
	_check("reload rebinds", reloaded.dock_manager == dock_manager and dock_manager.dock_button == reloaded.dock_button)
	await _free_dock(dock_manager)

static func _test_our_float() -> void:
	if _minor() >= 8 and not EditorInterface.is_multi_window_enabled():
		var fallback = await _new_dock(RIGHT_BL)
		await fallback.undock_instance()
		await _frames()
		_check("no sub-windows falls back to a slot", not fallback.is_floating() and fallback.get_current_slot() == RIGHT_BL)
		_check("make floating not offered", _action(fallback, "Make Floating") == null)
		await _free_dock(fallback)
		return
	
	var dock_manager = await _new_dock(BOTTOM)
	var window = await dock_manager.undock_instance()
	await _frames(6)
	_check("floats", dock_manager.is_floating() and window != null and dock_manager.get_current_slot() == FLOATING)
	_check("always on top offered", _action(dock_manager, "Always on Top") != null and _action(dock_manager, "Make Floating") == null)
	await dock_manager.dock_instance(LEFT_BL)
	await _frames(6)
	_check("float to slot", dock_manager.get_current_slot() == LEFT_BL and not dock_manager.is_floating())
	await _free_dock(dock_manager)

static func _test_no_dock_button() -> void:
	var control = FixtureBare.new()
	var dock_manager = DockManager.new(_plugin, control, BOTTOM, null, false)
	await dock_manager.add_to_tree()
	await _frames(6)
	_check("buttonless control stays", is_instance_valid(control) and dock_manager.get_current_slot() == BOTTOM)
	_check("no button bound", dock_manager.dock_button == null)
	dock_manager.show_popup()
	await _frames(2)
	var popup = _find_popup()
	_check("popup opens without a button", popup != null)
	if is_instance_valid(popup):
		popup.hide_and_free()
	await _free_dock(dock_manager)

## CURRENT_DOCK held the old Slot enum: floating 0, bottom 1, then side slots from 3.
static func _test_migration() -> void:
	var path = FIXTURE_CONTROL_PATH
	DockManager.save_plugin_layout_data(_plugin, {"meta":{"next_id":5}, "docks":{
		"0":{"type":"freeable", "scene_path":path, "scene_uid":"", "current_dock":6.0, "allow_reload":true},
		"1":{"type":"freeable", "scene_path":path, "scene_uid":"", "current_dock":1.0},
		"2":{"type":"freeable", "scene_path":path, "scene_uid":"", "current_dock":0.0},
	}})
	var manager = DockManager.InstanceManager.new(_plugin, false)
	manager.load_freeable_docks()
	await _frames(8)
	_check("old layout restores every dock", manager.instances.size() == 3)
	var by_id = {}
	for instance in manager.instances:
		by_id[instance.dock_id] = instance
	_check("old side slot", by_id[0].default_dock == 3)
	_check("old bottom", by_id[1].default_dock == BOTTOM)
	_check("old floating", by_id[2].default_dock == FLOATING)
	_check("old reload flag", by_id[0].allow_scene_reload)
	manager.save_layout_data()
	var saved = DockManager.get_plugin_layout_data(_plugin).docks["1"]
	_check("saves the new key", int(saved.slot) == BOTTOM and not saved.has("current_dock"))
	await _frames()
	manager.clean_up()
	await _frames(6)

## The 4.8 backend only needs the API it shares with 4.6, so this also runs on 4.6 and 4.7.
static func _test_engine_backend() -> void:
	var first = DockManager.new(_plugin, FixtureControl.new(), LEFT_UR, null, false)
	first._backend = EngineBackend.new(first)
	first.can_be_freed = true
	var second = DockManager.new(_plugin, FixtureControl.new(), LEFT_UR, null, false)
	second._backend = EngineBackend.new(second)
	await first.add_to_tree()
	await second.add_to_tree()
	await _frames(6)
	
	var dock = first._backend.dock
	var key_one = dock.layout_key
	var key_two = second._backend.dock.layout_key
	_check("engine places", first.get_current_slot() == LEFT_UR and first.plugin_control.get_parent() == dock)
	_check("same frame docks get their own layout keys", key_one != key_two and key_one != "" and key_two != "")
	_check("freeable docks stay out of the docks menu", not dock.global and dock.closable)
	await first.dock_instance(RIGHT_UL)
	await _frames()
	_check("engine moves", first.get_current_slot() == RIGHT_UL)
	
	first.plugin_control.data = {"n": 9}
	await first.reload_control()
	await _frames(8)
	_check("reload keeps the dock and slot", first._backend.dock == dock and first.get_current_slot() == RIGHT_UL)
	_check("reload swaps the child", first.plugin_control.get_parent() == dock and int(first.plugin_control.data.n) == 9)
	
	first.remove_control_from_parent()
	await _frames()
	_check("detach keeps the slot", first.plugin_control.get_parent() == null and first.get_current_slot() == RIGHT_UL)
	await first.dock_instance(first.default_dock)
	await _frames()
	_check("reattach", first.plugin_control.get_parent() == dock and first.get_current_slot() == LEFT_UR)
	
	var freed = [false]
	first.free_requested.connect(func(_dock_manager): freed[0] = true)
	_close(dock)
	await _frames(8)
	_check("closing frees a freeable dock", not is_instance_valid(first) and freed[0])
	_close(second._backend.dock)
	await _frames(8)
	_check("closing keeps a persistent dock", is_instance_valid(second))
	await _free_dock(second)

static func _test_engine_slots() -> void:
	var dock_manager = await _new_dock(MAIN_SCREEN)
	var control = dock_manager.plugin_control
	_check("main screen", dock_manager.get_current_slot() == MAIN_SCREEN)
	# Script is one of the tabs that refuses make_visible, 2D would hide a regression.
	EditorInterface.set_main_screen_editor("Script")
	await _frames(4)
	dock_manager.show_in_editor()
	await _frames(6)
	_check("main screen shows", control.is_visible_in_tree())
	await dock_manager.dock_instance(BOTTOM_L)
	await _frames()
	_check("bottom left", dock_manager.get_current_slot() == BOTTOM_L)
	await dock_manager.dock_instance(BOTTOM_R)
	await _frames()
	_check("bottom right", dock_manager.get_current_slot() == BOTTOM_R)
	await _free_dock(dock_manager)

static func _test_engine_close() -> void:
	var freeable = await _new_dock(RIGHT_BL, true)
	_check("engine close pressed", await _press_engine_button(freeable._backend.dock, "Close"))
	await _frames(6)
	_check("engine close frees a freeable dock", not is_instance_valid(freeable))
	
	var persistent = await _new_dock(RIGHT_BR)
	var dock = persistent._backend.dock
	_check("engine close pressed on persistent", await _press_engine_button(dock, "Close"))
	await _frames(6)
	_check("persistent dock survives", is_instance_valid(persistent))
	dock.open()
	await _frames()
	_check("persistent dock reopens", dock.get_parent() is TabContainer)
	await _free_dock(persistent)

## Windowed only: the engine's float button is disabled without sub-windows.
static func _test_engine_float() -> void:
	var dock_manager = await _new_dock(RIGHT_BL)
	var changes = [0]
	dock_manager.dock_changed.connect(func(_dock_manager): changes[0] += 1)
	_check("engine float pressed", await _press_engine_button(_engine_dock(dock_manager), "Make Floating"))
	await _frames(8)
	_check("engine float detected", dock_manager.is_floating() and dock_manager.get_current_slot() == FLOATING)
	var window = dock_manager.get_dock_manager_window()
	_check("engine owns the window", window is Window and not window is DockManager.PanelWindow)
	_check("offers the float actions", _action(dock_manager, "Make Floating") == null and _action(dock_manager, "Always on Top") != null)
	if not window is Window:
		await _free_dock(dock_manager)
		return
	if _minor() >= 6:
		_check("always on top applied", window.always_on_top)
		_check("title applied", window.title == dock_manager.window_title)
	if _minor() >= 8:
		_check("dock_changed fires for engine moves", changes[0] >= 1)
	
	var before = window.always_on_top
	_check("action follows the window", _action(dock_manager, "Always on Top").active == before)
	_action(dock_manager, "Always on Top").callable.call()
	await _frames(3)
	_check("toggle flips the window", window.always_on_top != before and dock_manager.window_always_on_top == window.always_on_top)
	_action(dock_manager, "Always on Top").callable.call()
	await _frames(3)
	
	dock_manager.show_popup()
	await _frames(2)
	var popups = window.get_children().filter(func(n): return n is PopupPanel)
	_check("popup opens in the float", popups.size() == 1)
	if popups.size() == 1:
		popups[0].hide_and_free()
	await _frames(3)
	_check("window survives the popup", is_instance_valid(window) and dock_manager.is_floating())
	
	await dock_manager._on_popup_slot_chosen(LEFT_BL)
	await _frames(10)
	_check("float moves to a slot", dock_manager.get_current_slot() == LEFT_BL and not dock_manager.is_floating())
	_check("engine closed its window", not is_instance_valid(window) or not window.visible)
	
	_check("floats again", await _press_engine_button(_engine_dock(dock_manager), "Make Floating"))
	await _frames(8)
	window = dock_manager.get_dock_manager_window()
	_check("second float detected", window != null)
	if window != null:
		window.close_requested.emit()
		await _frames(10)
		_check("closing returns to the slot", dock_manager.get_current_slot() == LEFT_BL and not dock_manager.is_floating())
	
	_check("floats a third time", await _press_engine_button(_engine_dock(dock_manager), "Make Floating"))
	await _frames(8)
	await _free_dock(dock_manager)
	_check("frees while floating", not is_instance_valid(dock_manager))

## Docks created floating have no slot to go back to, which the engine treats as a close.
static func _test_float_close() -> void:
	var freeable = await _new_dock(FLOATING, true)
	_check("created floating", freeable.is_floating())
	freeable.get_dock_manager_window().close_requested.emit()
	await _frames(8)
	_check("closing frees a freeable float", not is_instance_valid(freeable))
	
	var persistent = await _new_dock(FLOATING)
	persistent.get_dock_manager_window().close_requested.emit()
	await _frames(8)
	_check("closing docks a persistent float", is_instance_valid(persistent) and persistent.get_current_slot() == BOTTOM)
	await _free_dock(persistent)
