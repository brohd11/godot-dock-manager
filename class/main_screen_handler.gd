@tool
extends Node

const MainScreen = DockManager.MainScreen

var editor_plugin:EditorPlugin
var plugin_control:Control
var main_screen_button:Button

static func hide_main_screen_button(_editor_plugin):
	EditorNodeRef.call_on_ready(_hide_main_screen_button.bind(_editor_plugin))

static func _hide_main_screen_button(_editor_plugin):
	var bar_children = MainScreen.get_button_container()
	for child in bar_children.get_children():
		if String(child.name) == _editor_plugin._get_plugin_name():
			child.hide()
			break

func _init(_editor_plugin, _plugin_control) -> void:
	editor_plugin = _editor_plugin
	plugin_control = _plugin_control
	EditorNodeRef.call_on_ready(_setup)

func _setup():
	_connect_buttons()
	var main_bar = MainScreen.get_button_container()
	main_bar.child_entered_tree.connect(_child_entered_tree)
	for child in main_bar.get_children():
		if String(child.name) == editor_plugin._get_plugin_name():
			main_screen_button = child
			main_screen_button.hide()
			break

func _child_entered_tree(_c:Node):
	_connect_buttons()

func clean_up():
	pass

func _on_main_screen_control_vis_changed(main_screen_control):
	if not is_instance_valid(plugin_control):
		print("MAINSCREENHANDLER - CONTROL VIS CHANGED",plugin_control," ", is_queued_for_deletion())
		return
	if not main_screen_control.visible:
		return
	if plugin_control.get_parent() != EditorInterface.get_editor_main_screen():
		return
	if main_screen_control != plugin_control and main_screen_control.visible:
		plugin_control.hide()


func _connect_buttons():
	var main_bar = MainScreen.get_button_container()
	for button:Button in main_bar.get_children():
		if not button.pressed.is_connected(_on_main_screen_bar_button_pressed):
			button.pressed.connect(_on_main_screen_bar_button_pressed.bind(button))
	
	for child in EditorInterface.get_editor_main_screen().get_children():
		if child is Control:
			if not child.visibility_changed.is_connected(_on_main_screen_control_vis_changed):
				child.visibility_changed.connect(_on_main_screen_control_vis_changed.bind(child))

func _on_main_screen_bar_button_pressed(button:Button):
	pass
	#if not is_instance_valid(plugin_control):
		#print("MAINSCREENHANDLER - MAIN SCREEN BUTTON PRESSED",plugin_control," ", is_queued_for_deletion(), " button", main_screen_button)
		#return
	#if button == main_screen_button and main_screen_button.button_pressed:
		#EditorInterface.set_main_screen_editor.call_deferred(editor_plugin._get_plugin_name())
		#plugin_control.show()
	#else:
		#if plugin_control.get_parent() == EditorInterface.get_editor_main_screen():
			#plugin_control.hide()


func add_main_screen_control(control):
	plugin_control = control
	main_screen_button.show()
	EditorInterface.get_editor_main_screen().add_child(control)
	plugin_control.name = editor_plugin._get_plugin_name()
	plugin_control.hide()

func remove_main_screen_control(control):
	if is_instance_valid(main_screen_button):
		main_screen_button.hide()
	EditorInterface.get_editor_main_screen().remove_child(control)
	EditorInterface.set_main_screen_editor("Script")

func on_plugin_make_visible(visible):
	await get_tree().process_frame
	if is_instance_valid(plugin_control):
		plugin_control.visible = visible
