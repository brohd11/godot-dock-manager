@tool
extends EditorPlugin
## Host for the docks under test. DockManager names its saved layout after this script's folder.

func _get_plugin_name() -> String:
	return "DockFixture"
