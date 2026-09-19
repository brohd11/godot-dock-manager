@tool
class_name DockManager
extends Node

#! import_p Keys,
#! import_show_global DockManager,

const UFile = preload("uid://bqfy5cvhth0m1") #! resolve UtilR.Files.UFile
const UVersion = preload("uid://dn156lc18d1vt") #! resolve UtilR.UVersion
const UWindow = preload("uid://d1yl3cuumcudy") #! resolve UtilR.Nodes.UWindow
const UResource = preload("uid://xwy6i4dlbtvs") #! resolve UtilR.Resources.UResource
const UObject = preload("uid://3ris0kamdyic") #! resolve UtilR.Objects.UObject
const UName = preload("uid://b8sil7xrxxs20") #! resolve UtilR.Strings.UName
const EditorColors = preload("uid://cpw0fsrs38esk") #! resolve UtilE.Colors

const Docks = preload("uid://ct3weeqse5sf5") #! resolve EditorNodeRef.Refs.Docks
const BottomPanel = preload("uid://b0bnfv62aocty") #! resolve EditorNodeRef.Refs.BottomPanel
const MainScreen = preload("uid://raukp4vq6c3v").MainScreen #! resolve EditorNodeRef.Refs.MainScreen

# dock manager
const DockPopupHandler = preload("res://addons/addon_lib/dock_manager/dock_popup/dock_popup_handler.gd")
const MainScreenHandler = preload("res://addons/addon_lib/dock_manager/class/main_screen_handler.gd")
const MainScreenHandlerMulti = preload("res://addons/addon_lib/dock_manager/class/main_screen_handler_multi.gd")
const PanelWindow = preload("res://addons/addon_lib/dock_manager/class/panel_window.gd")

const WORKING_FILE_DIR = "user://addons/dock_manager"

const SET_DOCK_DATA = "set_dock_data"
const GET_DOCK_DATA = "get_dock_data"

var _engine_minor_version:int

var main_screen_handler
var external_main_screen_flag := false

var dock_tab_style:= 0

# init args
var plugin:EditorPlugin
var plugin_control:Control
var dock_button:Button
var default_dock:int
var last_dock:int
var can_be_freed:bool = false

var plugin_has_main:bool = false
var window_title:String = ""
var empty_panel:bool = false
var _default_window_size:= Vector2i(1200,800)
var save_layout:bool = true
var allow_scene_reload:bool = false
var _docked_name:String = ""

#4.6
var editor_dock

# persistent
var window_always_on_top:bool = true
var _last_window_size = null
var _last_window_pos = null


var dock_id:= -1
var dock_id_key:
	get:
		return str(dock_id)

enum Slot{
	FLOATING,
	BOTTOM_PANEL,
	MAIN_SCREEN,
	DOCK_SLOT_LEFT_UL,
	DOCK_SLOT_LEFT_BL,
	DOCK_SLOT_LEFT_UR,
	DOCK_SLOT_LEFT_BR,
	DOCK_SLOT_RIGHT_UL,
	DOCK_SLOT_RIGHT_BL,
	DOCK_SLOT_RIGHT_UR,
	DOCK_SLOT_RIGHT_BR,
}
const _slot = {
	Slot.FLOATING: -3,
	Slot.BOTTOM_PANEL: -2,
	Slot.MAIN_SCREEN: -1,
	Slot.DOCK_SLOT_LEFT_UL: EditorPlugin.DockSlot.DOCK_SLOT_LEFT_UL,
	Slot.DOCK_SLOT_LEFT_BL: EditorPlugin.DockSlot.DOCK_SLOT_LEFT_BL,
	Slot.DOCK_SLOT_LEFT_UR: EditorPlugin.DockSlot.DOCK_SLOT_LEFT_UR,
	Slot.DOCK_SLOT_LEFT_BR: EditorPlugin.DockSlot.DOCK_SLOT_LEFT_BR,
	Slot.DOCK_SLOT_RIGHT_UL: EditorPlugin.DockSlot.DOCK_SLOT_RIGHT_UL,
	Slot.DOCK_SLOT_RIGHT_BL: EditorPlugin.DockSlot.DOCK_SLOT_RIGHT_BL,
	Slot.DOCK_SLOT_RIGHT_UR: EditorPlugin.DockSlot.DOCK_SLOT_RIGHT_UR,
	Slot.DOCK_SLOT_RIGHT_BR: EditorPlugin.DockSlot.DOCK_SLOT_RIGHT_BR,
}

signal dock_changed(dock_manager)
signal free_requested(dock_manager)


static func hide_main_screen_button(_plugin):
	MainScreenHandler.hide_main_screen_button(_plugin)

static func get_plugin_layout_data(_plugin:EditorPlugin):
	var working_dir = get_layout_file_dir(_plugin)
	if not DirAccess.dir_exists_absolute(working_dir):
		DirAccess.make_dir_recursive_absolute(working_dir)
	var working_file = working_dir.path_join("layout.json")
	if not FileAccess.file_exists(working_file):
		var default_data = {
			Keys.META:{Keys.NEXT_ID:0},
			Keys.DOCKS:{}
		}
		UFile.write_to_json(default_data, working_file)
	
	return UFile.read_from_json(working_file)

static func save_plugin_layout_data(_plugin:EditorPlugin, data:Dictionary):
	var working_dir = get_layout_file_dir(_plugin)
	if not DirAccess.dir_exists_absolute(working_dir):
		DirAccess.make_dir_recursive_absolute(working_dir)
	var working_file = working_dir.path_join("layout.json")
	UFile.write_to_json(data, working_file)

static func get_layout_file_path(_plugin:EditorPlugin):
	var layout_dir = get_layout_file_dir(_plugin)
	var layout_file = layout_dir.path_join("layout.json")
	return layout_file

static func get_layout_file_dir(_plugin:EditorPlugin):
	var script = _plugin.get_script()
	var path = script.resource_path
	var dir_name = path.get_base_dir().get_file()
	return WORKING_FILE_DIR.path_join(dir_name)


func _init(_plugin:EditorPlugin, _control, _dock:Slot=Slot.BOTTOM_PANEL, 
	_main_screen_handler=null, _add_to_tree:=true) -> void:
	_engine_minor_version = UVersion.get_minor_version()
	
	plugin = _plugin
	plugin.add_child(self)
	if _control is Control:
		plugin_control = _control
	elif _control is PackedScene:
		plugin_control = _control.instantiate()
	
	
	if _plugin_has_main_screen(plugin):
		plugin_has_main = plugin._has_main_screen()
	else:
		plugin_has_main = false
	
	default_dock = _slot.get(_dock)
	if default_dock == -1 and not plugin_has_main:
		default_dock = -2 # if cant handle main, set to bottom panel
	last_dock = default_dock
	
	if _main_screen_handler != null:
		main_screen_handler = _main_screen_handler
		external_main_screen_flag = true
	
	_docked_name = get_docked_name()
	plugin_control.name = get_docked_name()
	
	_set_editor_settings()
	EditorInterface.get_editor_settings().settings_changed.connect(_set_editor_settings)
	
	if _add_to_tree:
		post_init()

func add_to_tree():
	await post_init()

func post_init():
	if plugin_has_main:
		if not is_instance_valid(main_screen_handler):
			main_screen_handler = MainScreenHandler.new(plugin, plugin_control)
			plugin.add_child(main_screen_handler)
	if is_instance_valid(main_screen_handler) and not plugin_has_main:
		printerr("Dock Manager has MainScreenHandler, but plugin doesn't handle main screen.")
	
	var dock_target
	var dock_index = -1
	var dock_layout_data
	var dock_data
	if save_layout:
		var layout_data = get_plugin_layout_data(plugin)
		if dock_id == -1:
			var meta = layout_data.get(Keys.META)
			dock_id = meta.get(Keys.NEXT_ID)
			save_plugin_layout_data(plugin, layout_data)
			save_layout_data.call_deferred()
		else:
			var docks = layout_data.get(Keys.DOCKS)
			dock_layout_data = docks.get(dock_id_key)
			dock_target = dock_layout_data.get(Keys.CURRENT_DOCK)
			dock_index = dock_layout_data.get(Keys.CURRENT_DOCK_INDEX, -1)
			dock_data = dock_layout_data.get(Keys.DOCK_DATA, {})
	
	if dock_target != null:
		dock_target -= 3 #^ to offset saved enum back to working val
	else:
		dock_target = default_dock
	
	if dock_target > -3:
		if dock_target == -1: # main screen
			await dock_instance(int(dock_target))
		else:
			# just place in default, engine will take care of it
			await dock_instance(int(default_dock))
	else:
		if dock_layout_data != null:
			_set_window_settings(dock_layout_data)
		await undock_instance()
		
	
	if save_layout:
		if plugin_control.has_method(SET_DOCK_DATA) and dock_data != null:
			plugin_control.call(SET_DOCK_DATA, dock_data)
	
	if window_title == "":
		window_title = get_docked_name()
	
	if "dock_button" in plugin_control:
		dock_button = plugin_control.dock_button
		dock_button.icon = EditorInterface.get_base_control().get_theme_icon("MakeFloating", &"EditorIcons")
		dock_button.pressed.connect(_on_dock_button_pressed)
		dock_button.show()
	else:
		print("Need dock button in scene to use Dock Manager.")
		plugin_control.queue_free()
		return
	
	if "dock_manager" in plugin_control:
		plugin_control.dock_manager = self
	
	_set_dock_tab_style.call_deferred() # need this even more delayed?

func _set_window_settings(dock_layout_data:Dictionary):
	window_always_on_top = dock_layout_data.get(Keys.ALWAYS_ON_TOP, true)
	
	var window_size = dock_layout_data.get(Keys.WINDOW_SIZE)
	if window_size != null:
		window_size = str_to_var(window_size)
		_last_window_size = window_size
	
	var current_screen = dock_layout_data.get(Keys.CURRENT_SCREEN, 0)
	if DisplayServer.get_screen_count() <= current_screen:
		return
	
	var window_pos = dock_layout_data.get(Keys.WINDOW_POSITION)
	if window_pos != null:
		window_pos = str_to_var(window_pos)
		_last_window_pos = window_pos


func _set_editor_settings():
	var ed_settings = EditorInterface.get_editor_settings()
	dock_tab_style = ed_settings.get_setting(EditorSet.DOCK_TAB_STYLE)
	
	await plugin.get_tree().create_timer(3).timeout
	_set_dock_tab_style()

func set_default_window_size(size:Vector2i):
	_default_window_size = size

func set_window_title(title:String):
	window_title = title


func get_plugin_control():
	return plugin_control

func show_in_editor():
	var current_dock = _get_current_dock()
	if _engine_minor_version < 6:
		if current_dock > -1:
			_show_in_tab_container()
		elif current_dock == -2:
			BottomPanel.show_panel(_docked_name)
	else: #elif _engine_minor_version <= 7: # Deal with when there is an issue in new version
		if current_dock > -1 or current_dock == -2:
			_show_in_tab_container()


func clean_up():
	save_layout_data()
	await _remove_control_from_parent()
	
	if not external_main_screen_flag and plugin_has_main:
		main_screen_handler.clean_up()
		main_screen_handler.queue_free()
	
	plugin_control.queue_free()
	queue_free()

func reload_control():
	save_layout_data() # saves before reloading
	
	var is_scene = plugin_control.scene_file_path != ""
	var control_path = get_scene_or_script(plugin_control)
	
	await _remove_control_from_parent()
	plugin_control.queue_free()
	if main_screen_handler is MainScreenHandler:
		main_screen_handler.queue_free()
		main_screen_handler = null
	
	if is_scene:
		var packed:PackedScene = load(control_path)
		plugin_control = packed.instantiate()
	else:
		var script = load(control_path)
		plugin_control = script.new()
	
	await plugin.get_tree().process_frame
	
	add_to_tree()
	show_in_editor()

func free_instance():
	clean_up()
	_erase_dock_from_data()

func _erase_dock_from_data():
	var layout_data = get_plugin_layout_data(plugin)
	var docks = layout_data.get(Keys.DOCKS)
	docks.erase(dock_id_key)
	layout_data[Keys.META][Keys.NEXT_ID] = _get_next_dock_id(docks)
	
	save_plugin_layout_data(plugin, layout_data)


func _get_next_dock_id(docks:Dictionary):
	var count:= 0
	while docks.has(str(count)):
		count += 1
	return count

func save_layout_data():
	if not save_layout:
		return
	if not is_instance_valid(plugin_control):
		return
	var current_dock = _get_current_dock()
	var adjusted_dock_val = current_dock + 3 #^ offset to get the enum val
	
	var layout_data = get_plugin_layout_data(plugin)
	var docks = layout_data.get(Keys.DOCKS)
	var scene_data = docks.get(dock_id_key, {})
	var file_path = get_scene_or_script(plugin_control)
	scene_data[Keys.SCENE_PATH] = file_path
	scene_data[Keys.SCENE_UID] = UFile.path_to_uid(file_path)
	scene_data[Keys.CURRENT_DOCK] = adjusted_dock_val
	scene_data[Keys.ALWAYS_ON_TOP] = window_always_on_top
	var window = get_dock_manager_window()# as Window
	if is_instance_valid(window):
		scene_data[Keys.CURRENT_SCREEN] = window.current_screen
		scene_data[Keys.WINDOW_SIZE] = var_to_str(window.size)
		scene_data[Keys.WINDOW_POSITION] = var_to_str(UWindow.get_window_global_position(window, false))
	
	
	var tab_idx = _get_tab_index()
	if tab_idx != null:
		scene_data[Keys.CURRENT_DOCK_INDEX] = tab_idx
	
	if can_be_freed:
		scene_data[Keys.TYPE] = Keys.FREEABLE
	else:
		scene_data[Keys.TYPE] = Keys.PERSISTENT
	if allow_scene_reload:
		scene_data[Keys.ALLOW_RELOAD] = true
	
	if plugin_control.has_method(GET_DOCK_DATA):
		scene_data[Keys.DOCK_DATA] = plugin_control.call(GET_DOCK_DATA)
	
	docks[dock_id_key] = scene_data
	layout_data[Keys.DOCKS] = docks
	
	var meta = layout_data.get(Keys.META)
	meta[Keys.NEXT_ID] = _get_next_dock_id(docks)
	
	save_plugin_layout_data(plugin, layout_data)


func _on_dock_button_pressed():
	var dock_popup_handler = DockPopupHandler.new(plugin_control)
	if can_be_freed:
		dock_popup_handler.can_be_freed()
	if not plugin_has_main:
		dock_popup_handler.disable_main_screen()
	if allow_scene_reload:
		dock_popup_handler.allow_reload()
	var plugin_window = get_dock_manager_window()
	if is_instance_valid(plugin_window):
		dock_popup_handler.show_always_on_top(window_always_on_top)
	if plugin_control.has_method(&"get_custom_dock_popup_buttons"):
		var buttons = plugin_control.get_custom_dock_popup_buttons()
		for b in buttons:
			dock_popup_handler.add_custom_button(b)
	
	var handled = await dock_popup_handler.handled
	if handled is String:
		return
	if handled is Callable:
		handled.call()
		return
	
	var current_dock
	if plugin_control.get_parent() is PanelWrapper:
		current_dock = _slot.get(Slot.MAIN_SCREEN)
	else:
		current_dock = Docks.get_current_dock(plugin_control)
	if current_dock == handled:
		return
	
	if handled == 20:
		free_requested.emit(self)
		free_instance.call_deferred()
	elif handled == 30:
		reload_control()
		return
	elif handled == 40:
		window_always_on_top = not window_always_on_top
		plugin_window.always_on_top = window_always_on_top
	elif handled == _slot.get(Slot.FLOATING):
		await undock_instance()
	else:
		await dock_instance(handled)
	
	save_layout_data()

func dock_instance(target_dock:int):
	if target_dock == -3:
		if default_dock > -3:
			target_dock = default_dock
		else:
			target_dock = -2
	if target_dock == -1 and not plugin_has_main:
		target_dock = default_dock
	var window = get_dock_manager_window()
	if is_instance_valid(window):
		_last_window_size = window.size
		_last_window_pos = window.position
	
	await _remove_control_from_parent()
	if _engine_minor_version < 6:
		if target_dock > -1:
			plugin.add_control_to_dock(target_dock, plugin_control)
			_set_dock_tab_style()
		elif target_dock == -1:
			var panel_wrapper = PanelWrapper.new(plugin_control, empty_panel)
			panel_wrapper.name = get_docked_name()
			main_screen_handler.add_main_screen_control(panel_wrapper)
		elif target_dock == -2:
			plugin.add_control_to_bottom_panel(plugin_control, get_docked_name())
	
	else: #elif _engine_minor_version <= 7: # Deal with when there is an issue in new version
		if target_dock > -1 or target_dock == -2:
			if not is_instance_valid(editor_dock):
				editor_dock = ClassDB.instantiate("EditorDock")
				editor_dock.title = get_docked_name()
				editor_dock.dock_icon = _get_plugin_icon()
				editor_dock.available_layouts = editor_dock.DOCK_LAYOUT_ALL
			var dock_slot = target_dock
			if target_dock == -2:
				dock_slot = 8 # EditorDock.DockSlot.DOCK_SLOT_BOTTOM
			editor_dock.default_slot = dock_slot
			if plugin_control.get_parent() == null:
				editor_dock.add_child(plugin_control)
			else:
				plugin_control.reparent(editor_dock)
			plugin.add_dock(editor_dock)
			
		elif target_dock == -1:
			var panel_wrapper = PanelWrapper.new(plugin_control, empty_panel)
			panel_wrapper.name = get_docked_name()
			main_screen_handler.add_main_screen_control(panel_wrapper)
	
	dock_changed.emit(self)


func undock_instance():
	await _remove_control_from_parent()
	var window_size = _default_window_size
	if _last_window_size is Vector2i:
		window_size = _last_window_size
	window_size = Vector2i(50,50).max(window_size)
	
	var window_pos = null
	if _last_window_pos is Vector2i:
		window_pos = _last_window_pos
	var window = PanelWindow.new(plugin_control, empty_panel, window_size, window_pos)
	
	window.title = window_title
	if window_title == "":
		window.title = get_docked_name()
	window.always_on_top = window_always_on_top
	window.close_requested.connect(window_close_requested)
	window.mouse_entered.connect(_on_window_mouse_entered.bind(window))
	#window.mouse_exited.connect(_on_window_mouse_exited)
	
	dock_changed.emit(self)
	return window

func remove_control_from_parent():
	_remove_control_from_parent()

func _remove_control_from_parent():
	var window = get_dock_manager_window()
	var current_dock = _get_current_dock()
	if current_dock != null:
		last_dock = current_dock
	
	var control_parent = plugin_control.get_parent()
	if is_instance_valid(control_parent):
		if _engine_minor_version < 6:
			if current_dock > -1:
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
		else: #elif _engine_minor_version <= 7: # Deal with when there is an issue in new version
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

func _get_current_dock():
	if plugin_control.get_parent() is PanelWrapper:
		return _slot.get(Slot.MAIN_SCREEN)
	else:
		return Docks.get_current_dock(plugin_control)

func get_current_dock_control():
	return Docks.get_current_dock_control(plugin_control)

func get_dock_manager_window():
	var window = plugin_control.get_window()
	if window is PanelWindow:
		return window
	return null

func window_close_requested() -> void:
	dock_instance(last_dock)
func _on_window_mouse_entered(window:Window):
	return
	if plugin.get_window().gui_is_dragging():
		window.grab_focus()
func _on_window_mouse_exited():
	EditorInterface.get_base_control().get_window().grab_focus()

func on_plugin_make_visible(visible:bool):
	main_screen_handler.on_plugin_make_visible(visible)

static func clean_dock_manager_array(instances:Array):
	InstanceManager._clean_dock_manager_array(instances)


func _get_plugin_icon():
	if not external_main_screen_flag:
		if plugin.has_method("_get_plugin_icon"):
			return plugin._get_plugin_icon()
	if "icon" in plugin_control:
		return plugin_control.get("icon")
	elif "plugin_icon" in plugin_control:
		return plugin_control.get("plugin_icon")
	return null

func _set_dock_tab_style():
	if _engine_minor_version >= 6:
		return
	var dock = get_current_dock_control()
	if dock is not TabContainer:
		return
	var idx = _get_tab_index()
	var plugin_name = get_docked_name()
	var icon = _get_plugin_icon()
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
	var dock  = get_current_dock_control()
	if dock is not TabContainer:
		return
	if _engine_minor_version < 6:
		return dock.get_tab_idx_from_control(plugin_control)
	else: #elif _engine_minor_version <= 7: # Deal with when there is an issue in new version
		return dock.get_tab_idx_from_control(editor_dock)

func _set_tab_index(idx:int):
	var dock_control = get_current_dock_control()
	if dock_control is not TabContainer:
		return
	var control_to_move = plugin_control
	if _engine_minor_version >= 6:
		control_to_move = editor_dock
	dock_control.move_child(control_to_move, idx)

func _show_in_tab_container():
	var dock_control = get_current_dock_control()
	if dock_control is not TabContainer:
		return
	var control_to_show = plugin_control
	if _engine_minor_version >= 6:
		control_to_show = editor_dock
	control_to_show.show()
	return
	var i = dock_control.get_tab_idx_from_control(control_to_show)
	dock_control.current_tab = i

func get_docked_name():
	if _docked_name != "":
		return _docked_name
	if not external_main_screen_flag:
		if plugin.has_method("_get_plugin_name"):
			return plugin._get_plugin_name()
	var _name = plugin_control.name
	return _name

static func get_scene_or_script(control):
	return UObject.get_object_file_path(control)

static func _plugin_has_main_screen(_plugin:EditorPlugin):
	return _plugin.has_method("_has_main_screen")

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
			else: #elif _version <= 7:
				panel_sb = EditorInterface.get_editor_theme().get_stylebox("panel", "Panel").duplicate()
				panel_sb.bg_color = EditorColors.get_theme_color(EditorColors.ThemeColor.BASE)
			
			panel_sb.content_margin_left = 4 * EditorInterface.get_editor_scale()
			panel_sb.content_margin_right = 4 * EditorInterface.get_editor_scale()
		
		add_theme_stylebox_override("panel", panel_sb)

class InstanceManager:
	var instances:Array[DockManager] = []
	var _msh#:MainScreenHandlerMulti
	var _plugin:EditorPlugin
	var _single_instance:bool
	
	func _init(_plug:EditorPlugin, _load_freeable_docks:=true, single_instance:=false) -> void:
		_plugin = _plug
		_single_instance = single_instance
		if DockManager._plugin_has_main_screen(_plugin):
			_msh = MainScreenHandlerMulti.new(_plugin)
			DockManager.hide_main_screen_button(_plugin)
		
		if _load_freeable_docks:
			load_freeable_docks.call_deferred()
	
	func load_freeable_docks():
		var layout_data = DockManager.get_plugin_layout_data(_plugin)
		var docks = layout_data.get(Keys.DOCKS, {})
		var current_ids = get_current_dock_ids()
		for id in docks.keys():
			var id_int = int(id)
			if id_int in current_ids:
				continue
			var data = docks.get(id, {})
			var type = data.get(Keys.TYPE, "nil")
			if type != Keys.FREEABLE:
				continue
			var current_dock = data.get(Keys.CURRENT_DOCK)
			
			var path = data.get(Keys.SCENE_UID, "")
			if not FileAccess.file_exists(path):
				path = data.get(Keys.SCENE_PATH, "")
				if not FileAccess.file_exists(path):
					printerr("Dock Manager - File doesn't exist: %s, %s" % [path, DockManager.get_layout_file_path(_plugin)])
					continue
			else:
				path = UFile.uid_to_path(path)
			
			var scn = load(path)
			if scn is GDScript:
				scn = scn.new()
			var ins = DockManager.new(_plugin, scn, current_dock, _msh, false)
			ins.can_be_freed = true
			var allow_reload = data.get(Keys.ALLOW_RELOAD, false)
			if allow_reload:
				ins.allow_scene_reload = true
			ins.dock_id = id_int
			ins.add_to_tree()
			instances.append(ins)
			current_ids.append(id_int)
	
	func new_persistent_dock_manager(scene, slot:Slot, _add_to_tree:=true):
		return _new_dock_manager(scene, slot, false, _add_to_tree)
	func new_freeable_dock_manager(scene, slot:Slot, _add_to_tree:=true):
		return _new_dock_manager(scene, slot, true, _add_to_tree)
	
	func _new_dock_manager(scene, slot:Slot, _can_be_freed:=false, _add_to_tree:=true):
		var scene_path:String = DockManager.get_scene_or_script(scene)
		
		if _single_instance:
			for ins in instances:
				if not is_instance_valid(ins):
					continue
				var ins_path:String = DockManager.get_scene_or_script(ins.plugin_control)
				if ins_path == scene_path:
					print("Scene already instanced: ", scene_path)
					return
		
		var ins:DockManager = DockManager.new(_plugin,scene, slot, _msh, false)
		ins.can_be_freed = _can_be_freed
		var id = _get_dock_data(scene, _can_be_freed)
		if id > -1:
			ins.dock_id = id
		if _add_to_tree:
			ins.add_to_tree()
		
		clean_dock_manager_array()
		instances.append(ins)
		return ins
	
	func get_current_dock_ids():
		var _ids:Array = []
		for i in instances:
			if is_instance_valid(i):
				_ids.append(i.dock_id)
		return _ids
	
	func _get_dock_data(scene, _can_be_freed:bool):
		var target_type:String = Keys.FREEABLE if _can_be_freed else Keys.PERSISTENT
		var layout_data:Dictionary = DockManager.get_plugin_layout_data(_plugin)
		var docks:Dictionary = layout_data.get(Keys.DOCKS, {})
		var current_ids:Array = get_current_dock_ids()
		var scene_path:String = ""
		if scene is PackedScene:
			scene_path = scene.resource_path
		elif scene is Control:
			scene_path = DockManager.get_scene_or_script(scene)
		
		for id in docks.keys():
			var id_int = int(id)
			if id_int in current_ids:
				continue
			var data = docks.get(id, {})
			var type = data.get(Keys.TYPE, "nil")
			if type != target_type:
				continue
			var path = data.get(Keys.SCENE_PATH)
			if path == scene_path:
				return id_int
		return -1
	
	func on_plugin_make_visible(visible:bool):
		if is_instance_valid(_msh):
			_msh.on_plugin_make_visible(visible)
	
	func save_layout_data():
		for i in instances:
			if is_instance_valid(i):
				i.save_layout_data()
	
	func clean_dock_manager_array():
		_clean_dock_manager_array(instances)
	
	static func _clean_dock_manager_array(_instances:Array):
		var invalid_positions = []
		for i in range(_instances.size()):
			if is_instance_valid(_instances[i]):
				continue
			invalid_positions.append(i)
	
		invalid_positions.reverse()
		for i in invalid_positions:
			_instances.remove_at(i)
	
	func clean_up():
		for ins in instances:
			if is_instance_valid(ins):
				ins.clean_up()



class EditorSet:
	const DOCK_TAB_STYLE = &"interface/editor/dock_tab_style"

class Keys:
	const DOCKS = "docks"
	const TYPE = "type"
	const FREEABLE = "freeable"
	const PERSISTENT = "persistent"
	const ALLOW_RELOAD = "allow_reload"
	const SCENE_PATH = "scene_path"
	const SCENE_UID = "scene_uid"
	const CURRENT_DOCK = "current_dock"
	const CURRENT_DOCK_INDEX = "current_dock_index"
	const DOCK_DATA = "dock_data"
	const ALWAYS_ON_TOP = &"ALWAYS_ON_TOP"
	const WINDOW_SIZE = &"WINDOW_SIZE"
	const WINDOW_POSITION = &"WINDOW_POSITION"
	const WINDOW_TRANSFORM = &"WINDOW_TRANSFORM"
	const CURRENT_SCREEN = &"CURRENT_SCREEN"
	
	const META = "meta"
	const NEXT_ID = "next_id"
