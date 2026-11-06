@tool
extends RefCounted
## Placement for engines older than 4.8, where the bottom panel and main screen aren't dock slots.
## Works in the old location codes (-3 floating, -2 bottom, -1 main screen, 0-7 sides); DockManager
## speaks engine slots, so values are converted at this boundary.

const UVersion = preload("uid://dn156lc18d1vt") #! resolve UtilR.UVersion
const UWindow = preload("uid://d1yl3cuumcudy") #! resolve UtilR.Nodes.UWindow
const EditorColors = preload("uid://cpw0fsrs38esk") #! resolve UtilE.Colors

const Docks = preload("uid://ct3weeqse5sf5") #! resolve EditorNodeRef.Refs.Docks
const BottomPanel = preload("uid://b0bnfv62aocty") #! resolve EditorNodeRef.Refs.BottomPanel

const MainScreenHandler = preload("res://addons/_lib/dock_manager/src/class/main_screen_handler.gd")
const PanelWindow = preload("res://addons/_lib/dock_manager/src/class/panel_window.gd")

const DOCK_TAB_STYLE = &"interface/editor/dock_tab_style"

var dm
var _engine_minor_version:int

var main_screen_handler
var plugin_has_main:bool = false
var dock_tab_style:= 0
var last_dock
var editor_dock #4.6

# False once the control is handed elsewhere, so a window it's reparented into isn't taken for a float.
var _placed := false
var _last_window_size = null
var _last_window_pos = null


func _init(dock_manager, _main_screen_handler) -> void:
	dm = dock_manager
	_engine_minor_version = UVersion.get_minor_version()
	
	if DockManager._plugin_has_main_screen(dm.plugin):
		plugin_has_main = dm.plugin._has_main_screen()
	
	if _main_screen_handler != null:
		main_screen_handler = _main_screen_handler
	
	# Tab style is the engine's job from 4.6, and this path only exists in settings migrated from then.
	if _engine_minor_version < 6:
		_set_editor_settings()
		EditorInterface.get_editor_settings().settings_changed.connect(_set_editor_settings)

func _set_editor_settings():
	var ed_settings = EditorInterface.get_editor_settings()
	dock_tab_style = ed_settings.get_setting(DOCK_TAB_STYLE)
	
	await dm.plugin.get_tree().create_timer(3).timeout
	if is_instance_valid(dm):
		_set_dock_tab_style()

func normalize_slot(slot:int, fallback:int) -> int:
	if slot == DockManager.DOCK_SLOT_MAIN_SCREEN and not plugin_has_main:
		return fallback # if cant handle main, use the fallback
	if slot in [DockManager.DOCK_SLOT_BOTTOM_L, DockManager.DOCK_SLOT_BOTTOM_R] and _engine_minor_version < 7:
		return DockManager.DOCK_SLOT_BOTTOM
	return slot

func get_available_slots() -> Array:
	var slots = range(9)
	if _engine_minor_version >= 7:
		slots.append_array([DockManager.DOCK_SLOT_BOTTOM_L, DockManager.DOCK_SLOT_BOTTOM_R])
	if plugin_has_main:
		slots.append(DockManager.DOCK_SLOT_MAIN_SCREEN)
	return slots

func can_float() -> bool:
	return true

func prepare():
	if plugin_has_main:
		if not is_instance_valid(main_screen_handler):
			main_screen_handler = MainScreenHandler.new(dm.plugin, dm.plugin_control)
			dm.plugin.add_child(main_screen_handler)
	if is_instance_valid(main_screen_handler) and not plugin_has_main:
		printerr("Dock Manager has MainScreenHandler, but plugin doesn't handle main screen.")

## Only the main screen is restored by hand here, the engine places everything else.
func get_startup_slot(saved_slot:int) -> int:
	if saved_slot == DockManager.DOCK_SLOT_MAIN_SCREEN:
		return saved_slot
	return dm.default_dock

func load_window_settings(dock_layout_data:Dictionary):
	var window_size = dock_layout_data.get(DockManager.Keys.WINDOW_SIZE)
	if window_size != null:
		window_size = str_to_var(window_size)
		_last_window_size = window_size
	
	var current_screen = dock_layout_data.get(DockManager.Keys.CURRENT_SCREEN, 0)
	if DisplayServer.get_screen_count() <= current_screen:
		return
	
	var window_pos = dock_layout_data.get(DockManager.Keys.WINDOW_POSITION)
	if window_pos != null:
		window_pos = str_to_var(window_pos)
		_last_window_pos = window_pos

func save_window_data(scene_data:Dictionary):
	var window = get_floating_window()
	if is_instance_valid(window):
		scene_data[DockManager.Keys.CURRENT_SCREEN] = window.current_screen
		scene_data[DockManager.Keys.WINDOW_SIZE] = var_to_str(window.size)
		scene_data[DockManager.Keys.WINDOW_POSITION] = var_to_str(UWindow.get_window_global_position(window, false))
	
	var tab_idx = _get_tab_index()
	if tab_idx != null:
		scene_data[DockManager.Keys.CURRENT_DOCK_INDEX] = tab_idx

func finish_setup():
	_set_dock_tab_style.call_deferred() # need this even more delayed?

func show():
	var current_dock = _get_current_code()
	if _engine_minor_version < 6:
		if current_dock > -1:
			_show_in_tab_container()
		elif current_dock == -2:
			BottomPanel.show_panel(dm.get_docked_name())
	else:
		if current_dock > -1 or current_dock == -2:
			_show_in_tab_container()

func clean_up():
	if not dm.external_main_screen_flag and plugin_has_main:
		main_screen_handler.clean_up()
		main_screen_handler.queue_free()

func release_for_reload():
	await remove_control()
	dm.plugin_control.queue_free()
	if main_screen_handler is MainScreenHandler:
		main_screen_handler.queue_free()
		main_screen_handler = null

func finish_reload():
	dm.add_to_tree()
	dm.show_in_editor()

func place(slot:int):
	var target_dock = DockManager.slot_to_legacy(slot)
	var plugin = dm.plugin
	var plugin_control = dm.plugin_control
	var window = get_floating_window()
	if is_instance_valid(window):
		_last_window_size = window.size
		_last_window_pos = window.position
	
	await remove_control()
	if _engine_minor_version < 6:
		if target_dock > -1:
			plugin.add_control_to_dock(target_dock, plugin_control)
			_set_dock_tab_style()
		elif target_dock == -1:
			var panel_wrapper = PanelWrapper.new(plugin_control, dm.empty_panel)
			panel_wrapper.name = dm.get_docked_name()
			main_screen_handler.add_main_screen_control(panel_wrapper)
		elif target_dock == -2:
			plugin.add_control_to_bottom_panel(plugin_control, dm.get_docked_name())
	
	else:
		if target_dock > -1 or target_dock == -2:
			if not is_instance_valid(editor_dock):
				editor_dock = DockManager.EngineBackend.new_managed_dock()
				editor_dock.layout_changed.connect(_on_editor_dock_layout_changed)
				editor_dock.title = dm.get_docked_name()
				editor_dock.dock_icon = dm._get_plugin_icon()
				editor_dock.available_layouts = editor_dock.DOCK_LAYOUT_ALL
			var dock_slot = target_dock
			if target_dock == -2:
				dock_slot = DockManager.DOCK_SLOT_BOTTOM
			editor_dock.default_slot = dock_slot
			if plugin_control.get_parent() == null:
				editor_dock.add_child(plugin_control)
			else:
				plugin_control.reparent(editor_dock)
			plugin.add_dock(editor_dock)
			
		elif target_dock == -1:
			var panel_wrapper = PanelWrapper.new(plugin_control, dm.empty_panel)
			panel_wrapper.name = dm.get_docked_name()
			main_screen_handler.add_main_screen_control(panel_wrapper)
	
	_placed = true

func make_floating():
	await remove_control()
	var window_size = dm.get_default_window_size()
	if _last_window_size is Vector2i:
		window_size = _last_window_size
	window_size = Vector2i(50,50).max(window_size)
	
	var window_pos = null
	if _last_window_pos is Vector2i:
		window_pos = _last_window_pos
	var window = PanelWindow.new(dm.plugin_control, dm.empty_panel, window_size, window_pos)
	
	window.title = dm.window_title
	if dm.window_title == "":
		window.title = dm.get_docked_name()
	window.always_on_top = dm.window_always_on_top
	window.close_requested.connect(_window_close_requested)
	_placed = true
	return window

func remove_control():
	var plugin = dm.plugin
	var plugin_control = dm.plugin_control
	var window = _get_panel_window()
	var engine_float = window == null and get_floating_window() != null
	var current_dock = _get_current_code()
	if current_dock != null:
		last_dock = current_dock
	_placed = false
	
	var control_parent = plugin_control.get_parent()
	if is_instance_valid(control_parent):
		if _engine_minor_version < 6:
			if current_dock > -1 or engine_float:
				plugin.remove_control_from_docks(plugin_control)
			elif current_dock == -1:
				var panel_wrapper = plugin_control.get_parent()
				main_screen_handler.remove_main_screen_control(panel_wrapper)
				panel_wrapper.remove_child(plugin_control)
				panel_wrapper.queue_free()
			elif current_dock == -2:
				plugin.remove_control_from_bottom_panel(plugin_control)
				BottomPanel.show_first_panel()
			else:
				control_parent.remove_child(plugin_control)
		else:
			if control_parent == editor_dock:
				plugin.remove_dock(editor_dock)
				editor_dock.remove_child(plugin_control)
				editor_dock.queue_free()
				editor_dock = null
			elif current_dock == -1:
				var panel_wrapper = plugin_control.get_parent()
				main_screen_handler.remove_main_screen_control(panel_wrapper)
				panel_wrapper.remove_child(plugin_control)
				panel_wrapper.queue_free()
			else:
				control_parent.remove_child(plugin_control)
	
	if is_instance_valid(window):
		window.queue_free()

## Null while the control has no parent, or sits somewhere other than a dock location.
func get_current_slot():
	var code = _get_current_code()
	if code == null:
		return null
	return DockManager.legacy_to_slot(code)

func get_dock_control():
	return Docks.get_current_dock_control(dm.plugin_control)

## Ours or the engine's, which floats from the dock's tab menu.
func get_floating_window():
	if not _placed or not dm.plugin_control.is_inside_tree():
		return null
	var window = dm.plugin_control.get_window()
	if window == EditorInterface.get_base_control().get_window():
		return null
	return window

func is_floating() -> bool:
	return get_floating_window() != null

func on_plugin_make_visible(visible:bool):
	main_screen_handler.on_plugin_make_visible(visible)


func _get_panel_window():
	var window = dm.plugin_control.get_window()
	if window is PanelWindow:
		return window
	return null

func _on_editor_dock_layout_changed(layout:int):
	if layout == editor_dock.DOCK_LAYOUT_FLOATING:
		_apply_window_settings.call_deferred()

func _apply_window_settings():
	if not is_instance_valid(dm):
		return
	var window = get_floating_window()
	if window == null:
		return
	window.always_on_top = dm.window_always_on_top
	window.title = dm.window_title if dm.window_title != "" else dm.get_docked_name()

func _window_close_requested() -> void:
	dm.dock_instance(DockManager.legacy_to_slot(last_dock))

func _get_current_code():
	if dm.plugin_control.get_parent() is PanelWrapper:
		return -1
	return Docks.get_current_dock(dm.plugin_control)

func _set_dock_tab_style():
	if _engine_minor_version >= 6:
		return
	var dock = get_dock_control()
	if dock is not TabContainer:
		return
	var idx = _get_tab_index()
	var plugin_name = dm.get_docked_name()
	var icon = dm._get_plugin_icon()
	if dock_tab_style == 0 or icon == null: #^ text
		dock.set_tab_title(idx, plugin_name)
		dock.set_tab_icon(idx, null)
	elif dock_tab_style == 1: #^ icon
		dock.set_tab_title(idx, "")
		dock.set_tab_icon(idx, icon)
	elif dock_tab_style == 2: #^ text and icon
		dock.set_tab_title(idx, plugin_name)
		dock.set_tab_icon(idx, icon)

func _get_tab_index():
	var dock = get_dock_control()
	if dock is not TabContainer:
		return
	if _engine_minor_version < 6:
		return dock.get_tab_idx_from_control(dm.plugin_control)
	return dock.get_tab_idx_from_control(editor_dock)

func _show_in_tab_container():
	var dock_control = get_dock_control()
	if dock_control is not TabContainer:
		return
	var control_to_show = dm.plugin_control
	if _engine_minor_version >= 6:
		control_to_show = editor_dock
	control_to_show.show()


class PanelWrapper extends PanelContainer:
	var _empty_pan := false
	func _init(control, _empty_panel:= false) -> void:
		add_child(control)
		_empty_pan = _empty_panel
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		
	func _ready() -> void:
		var panel_sb
		if _empty_pan:
			panel_sb = StyleBoxEmpty.new()
		else:
			var _version = UVersion.get_minor_version()
			if _version < 6:
				panel_sb = get_theme_stylebox("panel").duplicate()
			else:
				panel_sb = EditorInterface.get_editor_theme().get_stylebox("panel", "Panel").duplicate()
				panel_sb.bg_color = EditorColors.get_theme_color(EditorColors.ThemeColor.BASE)
			
			panel_sb.content_margin_left = 4 * EditorInterface.get_editor_scale()
			panel_sb.content_margin_right = 4 * EditorInterface.get_editor_scale()
		
		add_theme_stylebox_override("panel", panel_sb)
