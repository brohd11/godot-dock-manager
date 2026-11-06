# Dock Manager class for Godot Plugins

This is a class you can use when creating plugins. It manages your plugin GUI as an editor dock: any number of instances per plugin, saved data for each one, and utilities to float, reload or free them. On Godot older than 4.8 it also moves the GUI between Docks, Bottom Panel and Main Screen, which 4.8 does natively.

https://github.com/user-attachments/assets/60eb7fd6-dd16-4a2e-ba91-3a1e958fc387

Drag "dock_manager" folder anywhere into your plugin, then preload "dock_manager.gd" in your EditorPlugin script.

Create an instance of the DockManager class and pass your scene through.

To open the dock popup from a button, declare it in your GUI as "@onready var dock_button = %DockButton". The "MakeFloating" icon will be added by the dock manager, so no need to assign it. The button is optional, see [Dock popup](#dock-popup).

Known Bug: If you disable the plugin while on a main screen that you have added with multiple GUIs, the plugin will fail to remove the button and you will need to restart the editor. Click onto a different main screen before disabling.

```gdscript
const DockManager = preload("uid://bpxufoy7tnkfk") # dock_manager.gd
var dock_manager:DockManager

const GUI_SCENE = preload("res://addons/my_plugin/gui.tscn")

func _get_plugin_name() -> String:
	return "My Plugin"

func _has_main_screen() -> bool:
	return true


func _enter_tree() -> void:
	dock_manager = DockManager.new(self, GUI_SCENE, DockManager.DOCK_SLOT_BOTTOM)

func _exit_tree() -> void:
	dock_manager.clean_up() # frees GUI, saves layout

func _get_window_layout(configuration: ConfigFile) -> void:
	dock_manager.save_layout_data() # saves layout everytime it is changed, vs on exit
```

## Dock slots

Slots are the engine's `EditorDock.DockSlot` values, as plain ints. `EditorDock` is missing some of them on older versions, which would be a parse error, so use these if your plugin supports them:

| Location | Value |
|---|---|
| Side docks | `EditorPlugin.DOCK_SLOT_LEFT_UL` ... `EditorPlugin.DOCK_SLOT_RIGHT_BR` |
| Floating | `DockManager.DOCK_SLOT_NONE` |
| Bottom panel | `DockManager.DOCK_SLOT_BOTTOM` |
| Bottom left / right (4.7+) | `DockManager.DOCK_SLOT_BOTTOM_L`, `DockManager.DOCK_SLOT_BOTTOM_R` |
| Main screen | `DockManager.DOCK_SLOT_MAIN_SCREEN` |

A plugin that only targets 4.8+ can pass `EditorDock.DOCK_SLOT_*` directly. Below 4.8, the main screen needs `_has_main_screen()` to return true. From 0.7 the `Slot` enum is gone, and layouts saved by older versions are converted on load.

## Dock popup

The popup has a slot grid, which works from floating windows too, plus these actions: Make Floating, Always on Top, Free Instance and Reload. Open it from anywhere, or embed the actions in your own menu:

```gdscript
dock_manager.show_popup() # at the mouse

dock_manager.add_popup_items(my_popup_menu) # append to a PopupMenu, ids start at DockManager.POPUP_ID_BASE
my_popup_menu.add_submenu_node_item("Dock", dock_manager.get_submenu()) # or as a submenu

for action in dock_manager.get_popup_actions(): # or any other menu: text, icon, callable, active
	my_menu.add(action.text, action.callable)
```

Set `allow_scene_reload` to offer Reload. Freeable docks offer Free Instance. A control can add its own actions by implementing `get_custom_dock_popup_buttons()`, which returns the same dictionaries.

On 4.8 the tab's own Close button frees a freeable dock. Closing a floating window sends it back to its last slot, or frees it if it was created floating and is freeable.

## Saved data

Implement `get_dock_data() -> Dictionary` and `set_dock_data(data)` on your control to keep state between sessions. `get_dock_name()` sets the title for that control.

## Multiple GUIs

`InstanceManager` handles more than one GUI per plugin. Freeable docks are torn down when closed and
restored from the saved layout on load, which suits tools that are not open often.

```gdscript
var dm_instance_manager:DockManager.InstanceManager

func _enter_tree() -> void:
	dm_instance_manager = DockManager.InstanceManager.new(self, true)
	dm_instance_manager.new_persistent_dock_manager(MAIN_GUI, DockManager.DOCK_SLOT_BOTTOM)

func _open_extra_panel() -> void:
	dm_instance_manager.new_freeable_dock_manager(OTHER_GUI, DockManager.DOCK_SLOT_NONE)

func _exit_tree() -> void:
	dm_instance_manager.clean_up()
```
