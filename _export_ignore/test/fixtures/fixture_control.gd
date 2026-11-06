@tool
extends VBoxContainer
## Dock content with everything DockManager looks for on a control.

var dock_button:Button
var dock_manager
var data := {"n": 0}
var custom_called := false

func _init() -> void:
	dock_button = Button.new()
	add_child(dock_button)

func get_dock_data() -> Dictionary:
	return data

func set_dock_data(dock_data:Dictionary) -> void:
	data = dock_data

func get_custom_dock_popup_buttons() -> Array:
	return [{"text":"Custom", "icon":"Node", "callable":func(): custom_called = true}]
