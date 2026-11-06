@tool
extends RefCounted
## Placement for 4.8+, where every location is an EditorDock slot. Floating has no bound call, but
## a dock added with no slot opens in a window, so moving is always remove, re-slot and add.
## EditorDock isn't named here because this file also has to parse below 4.6.

# Compiled on use: a script file extending EditorDock logs an error on first scan below 4.6.
# The virtuals are the only way to hear where the engine puts a dock. 4.8 calls the first, 4.6 and 4.7 the second.
const MANAGED_DOCK_SOURCE = """@tool
extends EditorDock

signal slot_changed(slot:int)
signal layout_changed(layout:int)

func _update_layout_and_slot(_layout, slot) -> void:
	slot_changed.emit(slot)

func _update_layout(layout) -> void:
	layout_changed.emit(layout)
"""

const DOCK_LAYOUT_MAIN_SCREEN = 8 # not part of DOCK_LAYOUT_ALL

var dm
var dock

var _added := false
var _placing := false
var _slot:int = DockManager.DOCK_SLOT_NONE
var _last_slot:int = DockManager.DOCK_SLOT_NONE

static var _managed_dock_script:GDScript


static func new_managed_dock():
	if _managed_dock_script == null:
		_managed_dock_script = GDScript.new()
		_managed_dock_script.source_code = MANAGED_DOCK_SOURCE
		_managed_dock_script.reload()
	return _managed_dock_script.new()

func _init(dock_manager) -> void:
	dm = dock_manager

func normalize_slot(slot:int, _fallback:int) -> int:
	return slot

func get_available_slots() -> Array:
	return range(DockManager.DOCK_SLOT_MAIN_SCREEN + 1)

func can_float() -> bool:
	return EditorInterface.is_multi_window_enabled()

func prepare():
	pass

## Saved slots are the fallback for docks the editor layout doesn't know, it overrides them otherwise.
func get_startup_slot(saved_slot:int) -> int:
	return saved_slot

func load_window_settings(_dock_layout_data:Dictionary):
	pass

func save_window_data(_scene_data:Dictionary):
	pass

func finish_setup():
	pass

func show():
	if not _added:
		return
	dock.make_visible()
	# The main screen ignores make_visible unless its current tab allows switching, and most don't.
	if _slot == DockManager.DOCK_SLOT_MAIN_SCREEN:
		var main_screen = dock.get_parent()
		main_screen.current_tab = main_screen.get_tab_idx_from_control(dock)

func clean_up():
	if is_instance_valid(dock):
		dock.queue_free()

func release_for_reload():
	var control = dm.plugin_control
	if not _added:
		await remove_control()
	elif control.get_parent() == dock:
		dock.remove_child(control)
	control.queue_free()

## Only the child is swapped, so the dock keeps its slot, tab and window.
func finish_reload():
	if not _added:
		dm.add_to_tree()
		return
	dock.add_child(dm.plugin_control)
	dm._finish_control_setup(dm._read_saved_dock_data())
	dm.show_in_editor()

func place(slot:int):
	if slot == DockManager.DOCK_SLOT_NONE and not can_float():
		slot = _get_return_slot()
	
	_ensure_dock()
	_attach_control()
	
	_placing = true
	if _added:
		dm.plugin.remove_dock(dock)
	dock.default_slot = slot
	dock.closable = dm.can_be_freed
	dock.global = not dm.can_be_freed
	dm.plugin.add_dock(dock)
	_added = true
	if slot == DockManager.DOCK_SLOT_NONE:
		dock.open()
	_placing = false
	
	_remember_slot(slot)
	if slot == DockManager.DOCK_SLOT_NONE:
		_apply_window_settings.call_deferred(true)

func make_floating():
	if not is_floating():
		place(DockManager.DOCK_SLOT_NONE)
	return get_floating_window()

func remove_control():
	var control = dm.plugin_control
	var parent = control.get_parent()
	if _added:
		dm.plugin.remove_dock(dock)
		_added = false
	if is_instance_valid(parent):
		parent.remove_child(control)

## Survives remove_control, so a dock moved out of the editor's slots saves where it came from.
func get_current_slot():
	return _slot

func get_dock_control():
	if _added:
		return dock.get_parent()

func get_floating_window():
	if not is_floating() or not dock.is_inside_tree():
		return null
	var window = dock.get_window()
	if window == EditorInterface.get_base_control().get_window():
		return null
	return window

func is_floating() -> bool:
	return _added and _slot == DockManager.DOCK_SLOT_NONE

func on_plugin_make_visible(_visible:bool):
	pass


func _ensure_dock():
	if is_instance_valid(dock):
		return
	dock = new_managed_dock()
	dock.title = dm.get_docked_name()
	dock.dock_icon = dm._get_plugin_icon()
	dock.available_layouts = dock.DOCK_LAYOUT_ALL | DOCK_LAYOUT_MAIN_SCREEN
	# Titles repeat across instances, and the editor layout maps docks by this key.
	if dm.dock_id > -1:
		dock.layout_key = "%s/%d" % [DockManager.get_layout_file_dir(dm.plugin).get_file(), dm.dock_id]
	dock.slot_changed.connect(_on_slot_changed)
	dock.closed.connect(_on_closed, CONNECT_DEFERRED)

func _attach_control():
	var control = dm.plugin_control
	var parent = control.get_parent()
	if parent == dock:
		return
	if parent == null:
		dock.add_child(control)
	else:
		control.reparent(dock)

func _remember_slot(slot:int):
	if slot != DockManager.DOCK_SLOT_NONE:
		_last_slot = slot
	elif _slot != DockManager.DOCK_SLOT_NONE:
		_last_slot = _slot
	_slot = slot

func _get_return_slot() -> int:
	if _last_slot != DockManager.DOCK_SLOT_NONE:
		return _last_slot
	if dm.default_dock != DockManager.DOCK_SLOT_NONE:
		return dm.default_dock
	return DockManager.DOCK_SLOT_BOTTOM

func _on_slot_changed(slot:int):
	if _placing:
		return
	var changed = slot != _slot
	_remember_slot(slot)
	if slot == DockManager.DOCK_SLOT_NONE:
		_apply_window_settings.call_deferred(false)
	if changed:
		dm.dock_changed.emit.call_deferred(dm)

## Also fires for a window with no slot to return to, and when the editor layout loads a closed dock.
func _on_closed():
	if _placing or not _added:
		return
	var has_return_slot = _last_slot != DockManager.DOCK_SLOT_NONE
	if is_floating() and (has_return_slot or not dm.can_be_freed):
		await dm.dock_instance(_get_return_slot())
		dm.save_layout_data()
	elif dm.can_be_freed:
		dm.free_requested.emit(dm)
		dm.free_instance()

func _apply_window_settings(reset_size:bool):
	var window = get_floating_window()
	if window == null:
		return
	window.always_on_top = dm.window_always_on_top
	window.title = dm.window_title if dm.window_title != "" else dm.get_docked_name()
	if reset_size:
		window.size = dm.get_default_window_size()
		window.move_to_center()
