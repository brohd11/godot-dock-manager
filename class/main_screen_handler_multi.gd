@tool
extends Node

const UName = DockManager.UName
const MainScreen = DockManager.MainScreen

var editor_plugin:EditorPlugin
var main_screen_button:Button

var current_visible_button:Button
var plugin_buttons = {}
var setting_main_screen:=false

func _init(_editor_plugin) -> void:
	editor_plugin = _editor_plugin
	editor_plugin.add_child(self)
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


func clean_up():
	if is_instance_valid(main_screen_button):
		main_screen_button.text = editor_plugin._get_plugin_name()
	
	for button in plugin_buttons.keys():
		if is_instance_valid(button):
			button.queue_free()


func _child_entered_tree(_c:Node) -> void:
	_connect_buttons()

func _connect_buttons():
	var main_bar = MainScreen.get_button_container()
	for button:Button in main_bar.get_children():
		if not button.pressed.is_connected(_on_main_screen_bar_button_pressed):
			button.pressed.connect(_on_main_screen_bar_button_pressed.bind(button))


func _on_main_screen_bar_button_pressed(button:Button):
	if button == main_screen_button and main_screen_button.button_pressed:
		return
	if not button in plugin_buttons:
		_hide_plugin_controls()
		return
	for plugin_button:Button in plugin_buttons.keys():
		var plugin_control = plugin_buttons.get(plugin_button)
		if button != plugin_button:
			plugin_control.hide()
			plugin_button.button_pressed = false
		else:
			_set_custom_main_screen(plugin_button)

func _hide_plugin_controls():
	for plugin_button in plugin_buttons.keys():
		var plugin_control = plugin_buttons.get(plugin_button)
		plugin_control.hide()
		plugin_button.button_pressed = false
	
	await get_tree().process_frame # needed for windowed script editor
	current_visible_button = null


func add_main_screen_control(control):
	_add_main_screen_button(control)
	control.hide()

func _add_main_screen_button(control):
	var plugin_button = Button.new()
	var main_bar = MainScreen.get_button_container()
	var unique_name = UName.incremental_name_check_in_nodes(control.name, main_bar)
	control.name = unique_name
	plugin_button.name = unique_name
	plugin_button.text = unique_name
	EditorInterface.get_editor_main_screen().add_child(control)
	control.hide()
	plugin_button.icon = _get_control_icon(control)
	plugin_button.theme_type_variation = &"MainScreenButton"
	plugin_button.toggle_mode = true
	
	main_bar.add_child(plugin_button)
	
	plugin_buttons[plugin_button] = control
	_connect_buttons()

func remove_main_screen_control(control):
	_remove_main_screen_button(control)
	EditorInterface.get_editor_main_screen().remove_child(control)
	EditorInterface.set_main_screen_editor("Script")

func remove_main_screen_button(control):
	_remove_main_screen_button(control)

func _remove_main_screen_button(control):
	for plugin_button in plugin_buttons.keys():
		var plugin_control = plugin_buttons.get(plugin_button)
		if plugin_control != control:
			continue
		plugin_buttons.erase(plugin_button)
		plugin_button.queue_free()
		return

func _get_control_icon(panel_control):
	var plugin_base_control = panel_control.get_child(0)
	if "icon" in plugin_base_control: # change load method to allow for editor nodes
		return plugin_base_control.icon
	elif "plugin_icon" in plugin_base_control:
		return plugin_base_control.plugin_icon
	else:
		return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")

func on_plugin_make_visible(visible:bool):
	if not is_instance_valid(main_screen_button):
		return
	main_screen_button.show()
	
	await get_tree().process_frame
	if visible:
		if current_visible_button != null:
			_set_custom_main_screen(current_visible_button)
		else:
			if plugin_buttons.size() == 0:
				return
			var button = plugin_buttons.keys()[0]
			_set_custom_main_screen(button)
	else:
		_hide_plugin_controls()
	
	main_screen_button.hide()

func _set_custom_main_screen(button:Button) -> void:
	if setting_main_screen:
		return
	setting_main_screen = true
	
	main_screen_button.show() # need to do this for the signal to emit properly?
	main_screen_button.pressed.emit()
	main_screen_button.hide()
	var control = plugin_buttons.get(button)
	control.show()
	await get_tree().process_frame
	
	button.button_pressed = true
	current_visible_button = button
	
	setting_main_screen = false

static func print_buttons():
	var buttons = EditorNodeRef.get_registered(EditorNodeRef.Nodes.TITLE_BUTTONS)
	for b:Button in buttons.get_children():
		b.visible = true
		print(b.name)
		print(b.button_pressed)
