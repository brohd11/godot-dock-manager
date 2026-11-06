@tool
class_name DockManager
extends Node

#! import_p Keys,
#! import_show_global DockManager,

const UFile = preload("uid://bqfy5cvhth0m1") #! resolve UtilR.Files.UFile
const UVersion = preload("uid://dn156lc18d1vt") #! resolve UtilR.UVersion
const UResource = preload("uid://xwy6i4dlbtvs") #! resolve UtilR.Resources.UResource
const UObject = preload("uid://3ris0kamdyic") #! resolve UtilR.Objects.UObject
const UName = preload("uid://b8sil7xrxxs20") #! resolve UtilR.Strings.UName

const MainScreen = preload("uid://raukp4vq6c3v").MainScreen #! resolve EditorNodeRef.Refs.MainScreen

# dock manager
const DockPopup = preload("res://addons/_lib/dock_manager/src/dock_popup/dock_popup.gd")
const EngineBackend = preload("res://addons/_lib/dock_manager/src/backend/engine_backend.gd")
const LegacyBackend = preload("res://addons/_lib/dock_manager/src/backend/legacy_backend.gd")
const MainScreenHandler = preload("res://addons/_lib/dock_manager/src/class/main_screen_handler.gd")
const MainScreenHandlerMulti = preload("res://addons/_lib/dock_manager/src/class/main_screen_handler_multi.gd")
const PanelWindow = preload("res://addons/_lib/dock_manager/src/class/panel_window.gd")

const WORKING_FILE_DIR = "user://addons/dock_manager"

const SET_DOCK_DATA = "set_dock_data"
const GET_DOCK_DATA = "get_dock_data"
const GET_DOCK_NAME = "get_dock_name"

# Engine DockSlot values. EditorDock lacks some of these before 4.8, which would be a parse error.
const DOCK_SLOT_NONE = -1
const DOCK_SLOT_BOTTOM = 8
const DOCK_SLOT_BOTTOM_L = 9
const DOCK_SLOT_BOTTOM_R = 10
const DOCK_SLOT_MAIN_SCREEN = 11

const POPUP_ID_BASE = 7000 # keeps our ids clear of the host menu's own

var external_main_screen_flag := false

var _backend

# init args
var plugin:EditorPlugin
var plugin_control:Control
var dock_button:Button
var default_dock:int
var can_be_freed:bool = false

var window_title:String = ""
var empty_panel:bool = false
var _default_window_size:= Vector2i(1200,800)
var save_layout:bool = true
var allow_scene_reload:bool = false
var _docked_name:String = ""

# persistent
var window_always_on_top:bool = true


var dock_id:= -1
var dock_id_key:
	get:
		return str(dock_id)

signal dock_changed(dock_manager)
signal free_requested(dock_manager)


## 4.8 made every dock location a slot of the engine's own dock system.
static func uses_engine_docks() -> bool:
	return UVersion.get_minor_version() >= 8

## Converts the old location codes: -3 floating, -2 bottom panel, -1 main screen, 0+ dock slots.
static func legacy_to_slot(code:int) -> int:
	match code:
		-3: return DOCK_SLOT_NONE
		-2: return DOCK_SLOT_BOTTOM
		-1: return DOCK_SLOT_MAIN_SCREEN
	return code

static func slot_to_legacy(slot:int) -> int:
	match slot:
		DOCK_SLOT_NONE: return -3
		DOCK_SLOT_BOTTOM: return -2
		DOCK_SLOT_MAIN_SCREEN: return -1
	return slot

## Null when nothing is saved. Layouts from before 0.7 hold offset old codes in CURRENT_DOCK.
static func _read_saved_slot(dock_layout_data:Dictionary):
	if dock_layout_data.has(Keys.SLOT):
		return int(dock_layout_data.get(Keys.SLOT))
	if dock_layout_data.has(Keys.CURRENT_DOCK):
		return legacy_to_slot(int(dock_layout_data.get(Keys.CURRENT_DOCK)) - 3)
	return null

static func hide_main_screen_button(_plugin):
	if uses_engine_docks():
		return
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


func _init(_plugin:EditorPlugin, _control, _dock:int=DOCK_SLOT_BOTTOM, 
	_main_screen_handler=null, _add_to_tree:=true) -> void:
	plugin = _plugin
	plugin.add_child(self)
	if _control is Control:
		plugin_control = _control
	elif _control is PackedScene:
		plugin_control = _control.instantiate()
	
	if _main_screen_handler != null:
		external_main_screen_flag = true
	
	if uses_engine_docks():
		_backend = EngineBackend.new(self)
	else:
		_backend = LegacyBackend.new(self, _main_screen_handler)
	
	default_dock = _backend.normalize_slot(_dock, DOCK_SLOT_BOTTOM)
	
	_docked_name = get_docked_name()
	plugin_control.name = get_docked_name()
	
	if _add_to_tree:
		post_init()

func add_to_tree():
	await post_init()

func post_init():
	_backend.prepare()
	
	var dock_target = null
	var dock_layout_data
	var dock_data
	if save_layout:
		var layout_data = get_plugin_layout_data(plugin)
		if dock_id == -1:
			var meta = layout_data.get(Keys.META)
			dock_id = meta.get(Keys.NEXT_ID)
			# Reserved now: the editor layout key comes from the id, so docks added in the same frame can't share one.
			var docks = layout_data.get(Keys.DOCKS)
			docks[dock_id_key] = {}
			meta[Keys.NEXT_ID] = _get_next_dock_id(docks)
			save_plugin_layout_data(plugin, layout_data)
			save_layout_data.call_deferred()
		else:
			var docks = layout_data.get(Keys.DOCKS)
			dock_layout_data = docks.get(dock_id_key)
			dock_target = _read_saved_slot(dock_layout_data)
			dock_data = dock_layout_data.get(Keys.DOCK_DATA, {})
	
	if dock_target == null:
		dock_target = default_dock
	
	if dock_layout_data != null:
		window_always_on_top = dock_layout_data.get(Keys.ALWAYS_ON_TOP, true)
	
	if dock_target != DOCK_SLOT_NONE:
		await dock_instance(_backend.get_startup_slot(dock_target))
	else:
		if dock_layout_data != null:
			_backend.load_window_settings(dock_layout_data)
		await undock_instance()
	
	_finish_control_setup(dock_data)

## Shared with reload, which keeps the dock and replaces only the control.
func _finish_control_setup(dock_data):
	if save_layout:
		if plugin_control.has_method(SET_DOCK_DATA) and dock_data != null:
			plugin_control.call(SET_DOCK_DATA, dock_data)
	
	if window_title == "":
		window_title = get_docked_name()
	
	if "dock_button" in plugin_control and plugin_control.dock_button is Button:
		dock_button = plugin_control.dock_button
		dock_button.icon = EditorInterface.get_base_control().get_theme_icon("MakeFloating", &"EditorIcons")
		dock_button.pressed.connect(show_popup)
		dock_button.show()
	
	if "dock_manager" in plugin_control:
		plugin_control.dock_manager = self
	
	_backend.finish_setup()

func _read_saved_dock_data():
	var docks = get_plugin_layout_data(plugin).get(Keys.DOCKS)
	return docks.get(dock_id_key, {}).get(Keys.DOCK_DATA)

func set_default_window_size(size:Vector2i):
	_default_window_size = size

func get_default_window_size() -> Vector2i:
	return _default_window_size

func set_window_title(title:String):
	window_title = title


func get_plugin_control():
	return plugin_control

func show_in_editor():
	_backend.show()


func clean_up():
	save_layout_data()
	await _remove_control_from_parent()
	_backend.clean_up()
	
	plugin_control.queue_free()
	queue_free()

func reload_control():
	save_layout_data() # saves before reloading
	
	var is_scene = plugin_control.scene_file_path != ""
	var control_path = get_scene_or_script(plugin_control)
	
	await _backend.release_for_reload()
	
	if is_scene:
		var packed:PackedScene = load(control_path)
		plugin_control = packed.instantiate()
	else:
		var script = load(control_path)
		plugin_control = script.new()
	plugin_control.name = _docked_name
	
	await plugin.get_tree().process_frame
	
	_backend.finish_reload()

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
	var slot = get_current_slot()
	
	var layout_data = get_plugin_layout_data(plugin)
	var docks = layout_data.get(Keys.DOCKS)
	var scene_data = docks.get(dock_id_key, {})
	var file_path = get_scene_or_script(plugin_control)
	scene_data[Keys.SCENE_PATH] = file_path
	scene_data[Keys.SCENE_UID] = UFile.path_to_uid(file_path)
	if slot != null:
		scene_data[Keys.SLOT] = slot
	scene_data.erase(Keys.CURRENT_DOCK)
	scene_data[Keys.ALWAYS_ON_TOP] = window_always_on_top
	_backend.save_window_data(scene_data)
	
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


## Opens the slot grid and actions at the mouse. Connected to dock_button when the control has one.
func show_popup():
	var popup = DockPopup.new()
	popup.slot_chosen.connect(_on_popup_slot_chosen)
	popup.open(plugin_control, get_current_slot(), _backend.get_available_slots(), get_popup_actions())

## Everything the popup offers besides moving, for hosts with their own menu: text, icon, callable,
## and an optional active flag. Icons are editor theme names or textures.
func get_popup_actions() -> Array:
	var actions = []
	var window = get_dock_manager_window()
	if is_instance_valid(window):
		actions.append({"text":"Always on Top", "icon":"Pin", "callable":_toggle_always_on_top, "active":window.always_on_top})
	elif _backend.can_float():
		actions.append({"text":"Make Floating", "icon":"MakeFloating", "callable":_make_floating})
	if can_be_freed:
		actions.append({"text":"Free Instance", "icon":"Clear", "callable":_free_from_popup})
	if allow_scene_reload:
		actions.append({"text":"Reload", "icon":"Reload", "callable":reload_control})
	if plugin_control.has_method(&"get_custom_dock_popup_buttons"):
		actions.append_array(plugin_control.get_custom_dock_popup_buttons())
	return actions

## Appends the popup actions to a host menu. Item ids start at POPUP_ID_BASE.
func add_popup_items(popup:PopupMenu):
	for action in get_popup_actions():
		var id = POPUP_ID_BASE + popup.item_count
		var icon = action.get("icon")
		if icon is String:
			icon = EditorInterface.get_editor_theme().get_icon(icon, "EditorIcons")
		popup.add_icon_item(icon, action.get("text", ""), id)
		popup.set_item_metadata(popup.get_item_index(id), action.get("callable"))
	if not popup.id_pressed.is_connected(_on_popup_item_pressed):
		popup.id_pressed.connect(_on_popup_item_pressed.bind(popup))

## The popup actions in their own menu, for PopupMenu.add_submenu_node_item.
func get_submenu() -> PopupMenu:
	var submenu = PopupMenu.new()
	add_popup_items(submenu)
	return submenu

func _on_popup_item_pressed(id:int, popup:PopupMenu):
	if id < POPUP_ID_BASE:
		return
	var callable = popup.get_item_metadata(popup.get_item_index(id))
	if callable is Callable:
		callable.call()

func _on_popup_slot_chosen(slot:int):
	await dock_instance(slot)
	show_in_editor()
	save_layout_data()

func _make_floating():
	await undock_instance()
	save_layout_data()

func _free_from_popup():
	free_requested.emit(self)
	free_instance.call_deferred()

## Follows the window, which can differ from the setting when the engine opened it.
func _toggle_always_on_top():
	var window = get_dock_manager_window()
	if not is_instance_valid(window):
		return
	window_always_on_top = not window.always_on_top
	window.always_on_top = window_always_on_top
	save_layout_data()

## DOCK_SLOT_NONE docks back to the default location, undock_instance is what floats.
func dock_instance(target_dock:int):
	if target_dock == DOCK_SLOT_NONE:
		target_dock = default_dock if default_dock != DOCK_SLOT_NONE else DOCK_SLOT_BOTTOM
	await _backend.place(_backend.normalize_slot(target_dock, default_dock))
	dock_changed.emit(self)

func undock_instance():
	var window = await _backend.make_floating()
	dock_changed.emit(self)
	return window

func remove_control_from_parent():
	_remove_control_from_parent()

func _remove_control_from_parent():
	await _backend.remove_control()

## Engine DockSlot value, DOCK_SLOT_NONE when floating. Null if the location can't be determined.
func get_current_slot():
	return _backend.get_current_slot()

func is_floating() -> bool:
	return _backend.is_floating()

func get_current_dock_control():
	return _backend.get_dock_control()

func get_dock_manager_window():
	return _backend.get_floating_window()

func on_plugin_make_visible(visible:bool):
	_backend.on_plugin_make_visible(visible)

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

func get_docked_name():
	if _docked_name != "":
		return _docked_name
	# Lets several docks from one plugin get their own titles, including restored freeable ones.
	if plugin_control.has_method(GET_DOCK_NAME):
		return plugin_control.call(GET_DOCK_NAME)
	if not external_main_screen_flag:
		if plugin.has_method("_get_plugin_name"):
			return plugin._get_plugin_name()
	var _name = plugin_control.name
	return _name

static func get_scene_or_script(control):
	return UObject.get_object_file_path(control)

static func _plugin_has_main_screen(_plugin:EditorPlugin):
	return _plugin.has_method("_has_main_screen")

class InstanceManager:
	var instances:Array[DockManager] = []
	var _msh#:MainScreenHandlerMulti
	var _plugin:EditorPlugin
	var _single_instance:bool
	
	func _init(_plug:EditorPlugin, _load_freeable_docks:=true, single_instance:=false) -> void:
		_plugin = _plug
		_single_instance = single_instance
		if DockManager._plugin_has_main_screen(_plugin) and not DockManager.uses_engine_docks():
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
			var saved_slot = DockManager._read_saved_slot(data)
			if saved_slot == null:
				saved_slot = DOCK_SLOT_BOTTOM
			
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
			var ins = DockManager.new(_plugin, scn, saved_slot, _msh, false)
			ins.can_be_freed = true
			var allow_reload = data.get(Keys.ALLOW_RELOAD, false)
			if allow_reload:
				ins.allow_scene_reload = true
			ins.dock_id = id_int
			ins.add_to_tree()
			instances.append(ins)
			current_ids.append(id_int)
	
	func new_persistent_dock_manager(scene, slot:int, _add_to_tree:=true):
		return _new_dock_manager(scene, slot, false, _add_to_tree)
	func new_freeable_dock_manager(scene, slot:int, _add_to_tree:=true):
		return _new_dock_manager(scene, slot, true, _add_to_tree)
	
	func _new_dock_manager(scene, slot:int, _can_be_freed:=false, _add_to_tree:=true):
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



class Keys:
	const DOCKS = "docks"
	const TYPE = "type"
	const FREEABLE = "freeable"
	const PERSISTENT = "persistent"
	const ALLOW_RELOAD = "allow_reload"
	const SCENE_PATH = "scene_path"
	const SCENE_UID = "scene_uid"
	const SLOT = "slot"
	const CURRENT_DOCK = "current_dock" # pre 0.7, offset old codes
	const CURRENT_DOCK_INDEX = "current_dock_index"
	const DOCK_DATA = "dock_data"
	const ALWAYS_ON_TOP = &"ALWAYS_ON_TOP"
	const WINDOW_SIZE = &"WINDOW_SIZE"
	const WINDOW_POSITION = &"WINDOW_POSITION"
	const WINDOW_TRANSFORM = &"WINDOW_TRANSFORM"
	const CURRENT_SCREEN = &"CURRENT_SCREEN"
	
	const META = "meta"
	const NEXT_ID = "next_id"
